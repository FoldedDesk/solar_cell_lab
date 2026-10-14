#!/usr/bin/env python3
"""Verify the standalone ArkTS project using frozen reference data and stdlib XML/ZIP."""
import csv
import os
from pathlib import Path
import shutil
import subprocess
import sys
import zipfile
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
SHEET_NS = {'s': 'http://schemas.openxmlformats.org/spreadsheetml/2006/main'}


def workbook_cells(path, expected_rows):
    with zipfile.ZipFile(path) as archive:
        if archive.testzip() is not None:
            raise AssertionError(f'{path.name}: ZIP checksum failed')
        parts = {name: ET.fromstring(archive.read(name)) for name in archive.namelist()}
    required = {'[Content_Types].xml', '_rels/.rels', 'xl/workbook.xml',
                'xl/_rels/workbook.xml.rels', 'xl/worksheets/sheet1.xml'}
    assert required.issubset(parts), f'{path.name}: missing OOXML parts'
    sheet = parts['xl/workbook.xml'].find('s:sheets/s:sheet', SHEET_NS)
    assert sheet is not None and sheet.attrib['name'], f'{path.name}: missing sheet name'
    rows = parts['xl/worksheets/sheet1.xml'].findall('s:sheetData/s:row', SHEET_NS)
    assert len(rows) == expected_rows, (path.name, len(rows))
    cells = {}
    for row in rows:
        for cell in row.findall('s:c', SHEET_NS):
            if cell.attrib.get('t') == 'inlineStr':
                value = cell.findtext('s:is/s:t', default='', namespaces=SHEET_NS)
            else:
                value = float(cell.findtext('s:v', namespaces=SHEET_NS))
            cells[cell.attrib['r']] = value
    return cells


def main():
    output = ROOT / 'test-output'
    output.mkdir(exist_ok=True)
    studio = Path(os.environ.get('DEVECO_STUDIO_HOME', '/Applications/DevEco-Studio.app/Contents'))
    node = studio / 'tools/node' / ('node.exe' if os.name == 'nt' else 'bin/node')
    if not node.is_file():
        node = Path(shutil.which('node') or '')
    if not node.is_file():
        sys.exit('Node.js not found. Install DevEco Studio or set DEVECO_STUDIO_HOME.')
    result = subprocess.run([str(node), '--test', 'tests/domain.test.cjs', 'tests/files.test.cjs'],
                            cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    (output / 'verify.log').write_text(result.stdout, encoding='utf-8')
    print(result.stdout, end='')
    if result.returncode:
        return result.returncode
    iv = workbook_cells(output / 'iv.xlsx', 15)
    assert iv['A2'] == 0 and iv['C2'] == 25.2 and iv['D12'] == 48.4
    distance = workbook_cells(output / 'distance.xlsx', 11)
    assert distance['C11'] == '' and distance['E11'] == '待补测'
    led = workbook_cells(output / 'led.xlsx', 7)
    assert led['C4'] == 26
    with (output / 'iv.csv').open(encoding='utf-8-sig', newline='') as handle:
        rows = list(csv.reader(handle))
    assert len(rows) == 15 and rows[0][2] == '电流 I (mA)' and float(rows[1][2]) == 25.2
    for path in [output / 'iv-false.svg', output / 'iv-true.svg']:
        svg = ET.parse(path).getroot()
        assert svg.tag == '{http://www.w3.org/2000/svg}svg'
        assert len(svg.findall('.//{http://www.w3.org/2000/svg}circle')) == 14
    summary = 'PASS: 18 ArkTS tests, frozen numerical references, file services, 3 XLSX workbooks, CSV and SVG'
    with (output / 'verify.log').open('a', encoding='utf-8') as handle:
        handle.write(summary + '\n')
    print(summary)
    return 0


if __name__ == '__main__':
    sys.exit(main())
