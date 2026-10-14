import { CurvePoint, smoothCurve, ledCombinations, LedResult } from './Physics';
import { LabSession, Experiment, IVRecord, DistanceRecord, sourceName } from './Lab';

export type TableCell = string | number;
export class ExportTable {
  name: string;
  rows: TableCell[][];
  constructor(name: string, rows: TableCell[][]) { this.name = name; this.rows = rows; }
}

export function experimentTable(session: LabSession): ExportTable {
  const rows: TableCell[][] = [];
  if (session.tab === Experiment.IV) {
    rows.push(['电阻 R (Ω)', '电压 U (V)', '电流 I (mA)', '功率 P (mW)', '数据来源']);
    session.ivRows.forEach((r: IVRecord) => rows.push([r.resistance, r.voltage, r.current, r.power(), sourceName(r.source)]));
    return new ExportTable('伏安特性', rows);
  }
  if (session.tab === Experiment.Distance) {
    rows.push(['距离 d (cm)', '光强 E (W/m²)', '开路电压 Voc (V)', '短路电流 Isc (mA)', '记录状态', '数据来源']);
    session.distanceRows.forEach((r: DistanceRecord) => rows.push([r.distance, r.light,
      r.voltage < 0 ? '' : r.voltage, r.current < 0 ? '' : r.current, r.complete() ? '完整' : '待补测', '报告参考数据']));
    return new ExportTable('距离特性', rows);
  }
  const p = session.led;
  rows.push(['电池数量 N', '单块 Vm (V)', '单块 Im (mA)', 'LED 电压 (V)', 'LED 电流 (mA)']);
  rows.push([p.count, p.vm, p.im, p.vled, p.iled]);
  rows.push(['每组并联数 m', '串联组数 n', 'LED 总数', '输出电压 (V)', '输出电流 (mA)', '每支路 LED 数', '并联支路数', '方案']);
  ledCombinations(p).forEach((r: LedResult, i: number) => rows.push([r.parallel, r.series, r.total(), r.voltage,
    r.current, r.perBranch, r.branches, i === 0 ? '最优（理想估算）' : '备选']));
  return new ExportTable('LED 优化', rows);
}

export function csv(table: ExportTable): string {
  return '\uFEFF' + table.rows.map((row: TableCell[]) => row.map((cell: TableCell) =>
    '"' + String(cell).replace(/"/g, '""') + '"').join(',')).join('\r\n') + '\r\n';
}

export function xml(value: string): string {
  return value.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;').replace(/'/g, '&apos;');
}

export function utf8(text: string): Uint8Array {
  const bytes: number[] = [];
  for (let i = 0; i < text.length; i++) {
    let c = text.charCodeAt(i);
    if (c >= 0xD800 && c <= 0xDBFF && i + 1 < text.length) {
      const low = text.charCodeAt(i + 1);
      if (low >= 0xDC00 && low <= 0xDFFF) { c = 0x10000 + ((c - 0xD800) << 10) + low - 0xDC00; i++; }
    }
    if (c >= 0xD800 && c <= 0xDFFF) { c = 0xFFFD; }
    if (c < 0x80) { bytes.push(c); }
    else if (c < 0x800) { bytes.push(0xC0 | (c >> 6), 0x80 | (c & 63)); }
    else if (c < 0x10000) { bytes.push(0xE0 | (c >> 12), 0x80 | ((c >> 6) & 63), 0x80 | (c & 63)); }
    else { bytes.push(0xF0 | (c >> 18), 0x80 | ((c >> 12) & 63), 0x80 | ((c >> 6) & 63), 0x80 | (c & 63)); }
  }
  return new Uint8Array(bytes);
}

class ZipEntry {
  name: string;
  body: string;
  constructor(name: string, body: string) { this.name = name; this.body = body; }
}

function little(bytes: number[], value: number, count: number): void {
  for (let i = 0; i < count; i++) { bytes.push((value >>> (8 * i)) & 255); }
}

function append(bytes: number[], value: Uint8Array): void {
  for (let i = 0; i < value.length; i++) { bytes.push(value[i]); }
}

function crc32(bytes: Uint8Array): number {
  let crc = 0xFFFFFFFF;
  for (let i = 0; i < bytes.length; i++) {
    crc ^= bytes[i];
    for (let j = 0; j < 8; j++) { crc = (crc >>> 1) ^ ((crc & 1) ? 0xEDB88320 : 0); }
  }
  return (crc ^ 0xFFFFFFFF) >>> 0;
}

// Small OOXML workbooks use ZIP STORE, requiring no third-party runtime dependency.
function zip(entries: ZipEntry[]): Uint8Array {
  const bytes: number[] = [];
  const central: number[] = [];
  entries.forEach((entry: ZipEntry) => {
    const name = utf8(entry.name); const data = utf8(entry.body);
    const crc = crc32(data); const offset = bytes.length;
    little(bytes, 0x04034B50, 4); little(bytes, 20, 2); little(bytes, 0x800, 2);
    little(bytes, 0, 2); little(bytes, 0, 2); little(bytes, 33, 2);
    little(bytes, crc, 4); little(bytes, data.length, 4); little(bytes, data.length, 4);
    little(bytes, name.length, 2); little(bytes, 0, 2); append(bytes, name); append(bytes, data);
    little(central, 0x02014B50, 4); little(central, 20, 2); little(central, 20, 2);
    little(central, 0x800, 2); little(central, 0, 2); little(central, 0, 2); little(central, 33, 2);
    little(central, crc, 4); little(central, data.length, 4); little(central, data.length, 4);
    little(central, name.length, 2); little(central, 0, 2); little(central, 0, 2);
    little(central, 0, 2); little(central, 0, 2); little(central, 0, 4); little(central, offset, 4);
    append(central, name);
  });
  const start = bytes.length;
  append(bytes, new Uint8Array(central));
  little(bytes, 0x06054B50, 4); little(bytes, 0, 2); little(bytes, 0, 2);
  little(bytes, entries.length, 2); little(bytes, entries.length, 2);
  little(bytes, central.length, 4); little(bytes, start, 4); little(bytes, 0, 2);
  return new Uint8Array(bytes);
}

export function xlsx(table: ExportTable): Uint8Array {
  const rows = table.rows.map((row: TableCell[], i: number) => '<row r="' + (i + 1) + '">' +
    row.map((cell: TableCell, j: number) => {
      const ref = String.fromCharCode(65 + j) + (i + 1);
      return typeof cell === 'number' ? `<c r="${ref}"><v>${cell}</v></c>` :
        `<c r="${ref}" t="inlineStr"><is><t xml:space="preserve">${xml(cell)}</t></is></c>`;
    }).join('') + '</row>').join('');
  const ns = 'http://schemas.openxmlformats.org';
  return zip([
    new ZipEntry('[Content_Types].xml', `<?xml version="1.0" encoding="UTF-8"?><Types xmlns="${ns}/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/></Types>`),
    new ZipEntry('_rels/.rels', `<Relationships xmlns="${ns}/package/2006/relationships"><Relationship Id="rId1" Type="${ns}/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>`),
    new ZipEntry('xl/workbook.xml', `<workbook xmlns="${ns}/spreadsheetml/2006/main" xmlns:r="${ns}/officeDocument/2006/relationships"><sheets><sheet name="${xml(table.name)}" sheetId="1" r:id="rId1"/></sheets></workbook>`),
    new ZipEntry('xl/_rels/workbook.xml.rels', `<Relationships xmlns="${ns}/package/2006/relationships"><Relationship Id="rId1" Type="${ns}/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/></Relationships>`),
    new ZipEntry('xl/worksheets/sheet1.xml', `<worksheet xmlns="${ns}/spreadsheetml/2006/main"><cols><col min="1" max="8" width="23" customWidth="1"/></cols><sheetData>${rows}</sheetData></worksheet>`)
  ]);
}

export function chartSvg(title: string, xLabel: string, yLabel: string, points: CurvePoint[], smooth: boolean): string {
  const series = smooth ? smoothCurve(points) : points;
  let maxX = 1; let maxY = 1;
  points.forEach((p: CurvePoint) => { maxX = Math.max(maxX, p.x); maxY = Math.max(maxY, p.y); });
  maxX *= 1.08; maxY *= 1.12;
  const mapX = (x: number): number => 90 + x / maxX * 830;
  const mapY = (y: number): number => 480 - y / maxY * 390;
  let axes = '';
  for (let i = 0; i <= 5; i++) {
    const x = mapX(maxX * i / 5); const y = mapY(maxY * i / 5);
    axes += `<path d="M90 ${y}H920 M${x} 90V480" stroke="#DCE6E7"/><text x="${x}" y="510" text-anchor="middle">${(maxX * i / 5).toFixed(2)}</text><text x="78" y="${y + 5}" text-anchor="end">${(maxY * i / 5).toFixed(2)}</text>`;
  }
  const line = series.map((p: CurvePoint) => `${mapX(p.x).toFixed(2)},${mapY(p.y).toFixed(2)}`).join(' ');
  const dots = points.map((p: CurvePoint) => `<circle cx="${mapX(p.x)}" cy="${mapY(p.y)}" r="4" fill="#147D83"/>`).join('');
  return `<svg xmlns="http://www.w3.org/2000/svg" width="1000" height="580" viewBox="0 0 1000 580"><rect width="1000" height="580" fill="white"/><g font-family="sans-serif" font-size="15" fill="#15333F"><text x="90" y="40" font-size="24">${xml(title)}</text><text x="90" y="68">${xml(yLabel)}</text>${axes}<polyline points="${line}" fill="none" stroke="#147D83" stroke-width="3"/>${dots}<text x="500" y="555" text-anchor="middle">${xml(xLabel)} · ${smooth ? 'PCHIP 插值' : '原始数据'}</text></g></svg>`;
}
