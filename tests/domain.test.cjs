require('./runtime.cjs');
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const P = require('../entry/src/main/ets/model/Physics.ets');
const L = require('../entry/src/main/ets/model/Lab.ets');
const E = require('../entry/src/main/ets/model/Export.ets');
const reference = require('./fixtures/desktop-reference.json');
const near = (actual, expected, tolerance = 1e-8) => assert.ok(Math.abs(actual - expected) <= tolerance,
  `${actual} != ${expected} (tolerance ${tolerance})`);

test('report I-V points and interpolation match the frozen desktop Python reference', () => {
  for (const [r, u, i] of reference.iv) { const reading = P.reportIV(r); near(reading.voltage, u); near(reading.current, i); }
});

test('191 distance samples including extrapolation match the frozen desktop reference', () => {
  for (const [d, u, i, e] of reference.distance) {
    const reading = P.distanceReading(d); near(reading.voltage, u); near(reading.current, i); near(P.intensity(d), e);
  }
});

test('600 diode points, Isc, Voc, MPP and FF match frozen SciPy references', () => {
  for (const fixture of reference.theory) {
    const params = new P.CellParameters(); params.iph = fixture.iph;
    const points = P.theoreticalIV(params, fixture.temperature);
    near(P.openCircuit(params, fixture.temperature), fixture.voc);
    near(P.currentAt(0, params, fixture.temperature) * 1000, fixture.isc);
    points.forEach((p, i) => { near(p.voltage, fixture.voltage[i]); near(p.current, fixture.current[i]); });
    const mpp = points.reduce((best, p) => p.power() > best.power() ? p : best);
    near(mpp.voltage, fixture.mpp[0]); near(mpp.current, fixture.mpp[1]); near(mpp.power(), fixture.mpp[2]);
    near(mpp.power() / (fixture.voc * fixture.isc), fixture.ff);
  }
});

test('load-line solutions satisfy U = IR including short circuit and near-open circuit', () => {
  for (const r of [0, .1, 7, 82, 150, 1000, 99999.9]) {
    const p = P.loadReading(r); near(p.voltage, p.current / 1000 * r, 1e-8);
  }
  const dark = new P.CellParameters(); dark.iph = 0;
  near(P.openCircuit(dark), 0); near(P.currentAt(0, dark), 0);
  assert.throws(() => P.theoreticalIV(dark, 298, 1));
  assert.throws(() => P.currentAt(-1));
});

test('PCHIP curve matches the frozen scipy.interpolate reference including extrema', () => {
  const f = reference.pchip;
  const points = P.smoothCurve(f.x.map((x, i) => new P.CurvePoint(x, f.y[i])));
  assert.equal(points.length, f.points.length);
  points.forEach((p, i) => { near(p.x, f.points[i][0]); near(p.y, f.points[i][1]); });
  assert.deepEqual(P.smoothCurve([new P.CurvePoint(1, 2), new P.CurvePoint(1, 4)]), [new P.CurvePoint(1, 3)]);
});

test('input rejects blanks, exponent notation, negative, NaN, Infinity and out-of-range values', () => {
  for (const value of ['', ' ', '-1', '1e3', 'NaN', 'Infinity', '0x10', '1.2.3', '100001']) {
    assert.throws(() => P.numberInput(value, 0, 99999.9));
  }
  assert.equal(P.numberInput(' .5 ', 0, 1), .5);
  assert.throws(() => P.reportIV(NaN)); assert.throws(() => P.distanceReading(0));
});

test('incorrect wiring blocks acquisition, extra shorts invalidate an otherwise correct circuit', () => {
  const s = new L.LabSession(); assert.throws(() => s.record());
  s.autoWire(); assert.equal(s.connected(), true); s.record();
  assert.throws(() => s.record(), /已有记录/);
  assert.throws(() => s.toggleWire('panel_p', 'panel_n'));
});

test('terminal toggling, degree limits and reversed distance meter polarity', () => {
  const s = new L.LabSession();
  assert.throws(() => s.toggleWire('panel_p', 'panel_n'));
  assert.throws(() => s.toggleWire('bogus', 'res_n'));
  s.toggleWire('panel_p', 'amm_p'); s.toggleWire('panel_p', 'vol_p');
  assert.throws(() => s.toggleWire('panel_p', 'res_p'));
  s.toggleWire('amm_p', 'panel_p'); assert.equal(s.wires().length, 1);
  s.autoWire(); s.toggleWire('panel_p', 'vol_p'); assert.equal(s.connected(), false);
  assert.equal(L.validWiring([L.wireKey('panel_p', 'amm_n'), L.wireKey('panel_n', 'amm_p')], L.Experiment.Distance, L.MeasureMode.Isc), true);
});

for (const first of [L.MeasureMode.Isc, L.MeasureMode.Voc]) {
  test(`distance pairs combine in either order, first mode ${first}`, () => {
    const s = new L.LabSession(); s.tab = L.Experiment.Distance; s.changeMode(first); s.autoWire(); s.record();
    assert.equal(s.distanceRows[0].complete(), false); assert.equal(s.chart(false).length, 0);
    assert.throws(() => s.record(), /该项已记录/);
    const recovered = L.LabSession.decode(JSON.stringify(s));
    recovered.changeMode(first === L.MeasureMode.Isc ? L.MeasureMode.Voc : L.MeasureMode.Isc);
    assert.equal(recovered.connected(), false); recovered.autoWire(); recovered.record();
    assert.equal(recovered.distanceRows.length, 1); assert.equal(recovered.distanceRows[0].complete(), true);
    near(recovered.distanceRows[0].voltage, 2.57); near(recovered.distanceRows[0].current, 10.6);
    assert.equal(recovered.chart(false).length, 1); assert.throws(() => recovered.record(), /完整数据/);
    recovered.deleteRow(30); assert.equal(recovered.distanceRows.length, 0);
  });
}

test('manual entries, edits and deleting/clearing stay independent between experiments', () => {
  const s = new L.LabSession(); s.addIV(82, 2, 24.2); s.addIV(0, 0, 25.2);
  near(s.ivRows[0].power(), 48.4); assert.throws(() => s.editIV(82, 0, 1, 1));
  s.editIV(82, 83, 2.01, 24.1); assert.equal(s.ivRows[0].source, L.Source.Manual);
  assert.throws(() => s.addIV(100, 11, 24)); assert.throws(() => s.addIV(100, 1, 201));
  s.tab = L.Experiment.Distance; s.loadStandard(); s.clearRows(); assert.equal(s.ivRows.length, 2);
  s.tab = L.Experiment.IV; s.deleteRow(83); assert.equal(s.ivRows.length, 1);
});

test('state recovery restores methods and rejects corrupt schemas and records', () => {
  const s = new L.LabSession(); s.loadStandard(); s.autoWire();
  const recovered = L.LabSession.decode(JSON.stringify(s));
  assert.equal(recovered.connected(), true); near(recovered.ivRows[10].power(), 48.4);
  for (const bad of ['null', '{}', '{', JSON.stringify({ ...s, schemaVersion: 2 }),
    JSON.stringify({ ...s, ivRows: [null] }), JSON.stringify({ ...s, distance: 31 }),
    JSON.stringify({ ...s, ivWires: ['amm_p|bogus'] }), JSON.stringify({ ...s, led: { ...s.led, count: 1.5 } })]) {
    assert.throws(() => L.LabSession.decode(bad));
  }
  const next = s.clone(); next.deleteRow(0); assert.equal(s.ivRows.length, 14);
});

test('analysis uses measured power and actual short-circuit record', () => {
  const s = new L.LabSession(); s.loadStandard(); const a = L.analyze(s.ivRows);
  near(a.maxPower, 48.4); near(a.resistance, 82); near(a.isc, 25.2); near(a.voc, 2.55);
  near(a.ff, 48.4 / (25.2 * 2.55)); assert.ok(a.hasShortCircuit && a.hasOpenCircuit);
  s.deleteRow(0); assert.equal(L.analyze(s.ivRows).hasShortCircuit, false);
});

test('LED optimum, factor enumeration, zero-LED scenarios and input validation', () => {
  const p = new P.LedInput(); const rows = P.ledCombinations(p);
  assert.equal(rows.length, 4); assert.equal(rows[0].total(), 26); assert.equal(rows[0].parallel, 5);
  for (const row of rows) assert.equal(row.parallel * row.series, 15);
  p.count = 1; p.vm = .1; assert.equal(P.ledCombinations(p)[0].total(), 0);
  for (const n of [0, -1, 1.5, 10001, NaN]) { p.count = n; assert.throws(() => P.ledCombinations(p)); }
});

test('responsive breakpoint selects correct layout at phone, tablet and desktop widths', () => {
  for (const width of [360, 600, 839]) assert.equal(L.wideLayout(width), false);
  for (const width of [840, 1280, 1920]) assert.equal(L.wideLayout(width), true);
});

test('CSV, XLSX and SVG preserve units, Unicode, numeric values and partial records', () => {
  assert.deepEqual(Buffer.from(E.utf8('中文 Ω ☀️ 😀')), Buffer.from('中文 Ω ☀️ 😀'));
  const s = new L.LabSession(); s.loadStandard();
  fs.writeFileSync('test-output/iv.xlsx', E.xlsx(E.experimentTable(s)));
  const csv = E.csv(E.experimentTable(s)); assert.ok(csv.startsWith('\uFEFF')); assert.ok(csv.includes('电流 I (mA)'));
  fs.writeFileSync('test-output/iv.csv', csv);
  for (const smooth of [false, true]) {
    const svg = E.chartSvg('I–V', 'U (V)', 'I (mA)', s.chart(false), smooth);
    assert.equal((svg.match(/<circle /g) || []).length, 14);
    fs.writeFileSync(`test-output/iv-${smooth}.svg`, svg);
  }
  s.tab = L.Experiment.Distance; s.loadStandard(); s.distance = 55; s.autoWire(); s.record();
  assert.equal(E.experimentTable(s).rows.at(-1)[2], '');
  fs.writeFileSync('test-output/distance.xlsx', E.xlsx(E.experimentTable(s)));
  s.tab = L.Experiment.Led; fs.writeFileSync('test-output/led.xlsx', E.xlsx(E.experimentTable(s)));
  assert.ok(E.csv(new E.ExportTable('quotes', [['中文,"测量"']])).includes('"中文,""测量"""'));
});
