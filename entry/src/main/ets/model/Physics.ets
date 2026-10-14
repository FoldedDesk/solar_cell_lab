// Units: V, A, W in the diode model; V, mA, mW in experiment records.
export class CellParameters {
  cells: number = 4;
  iph: number = 0.0275;
  i0: number = 2e-10;
  rs: number = 0.12;
  rsh: number = 200;
  n: number = 1.5;
}

export class Reading {
  voltage: number;
  current: number;
  constructor(voltage: number = 0, current: number = 0) { this.voltage = voltage; this.current = current; }
  power(): number { return this.voltage * this.current; }
}

export class CurvePoint {
  x: number;
  y: number;
  constructor(x: number, y: number) { this.x = x; this.y = y; }
}

export const REPORT_R: number[] = [0, 7, 15, 23, 32, 40, 49, 56, 65, 73, 82, 99, 159, 9999];
export const REPORT_U: number[] = [0, .2, .4, .6, .8, 1, 1.2, 1.4, 1.6, 1.8, 2, 2.2, 2.4, 2.55];
export const REPORT_I: number[] = [25.2, 25.5, 24.8, 24.7, 24.5, 24.3, 24.3, 24.5, 24.4, 24.7, 24.2, 22, 15.1, .2];
export const REPORT_D: number[] = [10, 15, 20, 25, 30, 35, 40, 45, 50];
export const REPORT_E: number[] = [1016, 460, 244, 153.8, 105.1, 79, 63.4, 49.7, 39.8];
export const REPORT_VOC: number[] = [2.92, 2.8, 2.71, 2.63, 2.57, 2.51, 2.46, 2.41, 2.38];
export const REPORT_ISC: number[] = [106.5, 48, 25, 15.4, 10.6, 8, 6.1, 4.8, 3.9];

export function inRange(value: number, min: number, max: number): boolean {
  return Number.isFinite(value) && value >= min && value <= max;
}

export function numberInput(text: string, min: number, max: number): number {
  if (!/^(\d+\.?\d*|\.\d+)$/.test(text.trim())) { throw new Error('请输入有效数字'); }
  const value = Number(text.trim());
  if (!inRange(value, min, max)) { throw new Error(`数值范围：${min}～${max}`); }
  return value;
}

export function interpolate(x: number, xs: number[], ys: number[], extrapolate: boolean = true): number {
  const exact = xs.indexOf(x);
  if (exact >= 0) { return ys[exact]; }
  let j = 0;
  if (x >= xs[xs.length - 1]) { j = xs.length - 2; }
  else { while (j < xs.length - 2 && x > xs[j + 1]) { j++; } }
  const outside = x < xs[0] || x > xs[xs.length - 1];
  if (outside && !extrapolate) { return x < xs[0] ? ys[0] : ys[ys.length - 1]; }
  if (outside && xs[j] > 0 && ys[j] > 0 && ys[j + 1] > 0) {
    const slope = Math.log(ys[j + 1] / ys[j]) / Math.log(xs[j + 1] / xs[j]);
    return ys[j] * Math.pow(Math.max(.1, x) / xs[j], slope);
  }
  return ys[j] + (ys[j + 1] - ys[j]) * (x - xs[j]) / (xs[j + 1] - xs[j]);
}

export function reportIV(resistance: number): Reading {
  if (!inRange(resistance, 0, 99999.9)) { throw new Error('电阻超出量程'); }
  const index = REPORT_R.indexOf(resistance);
  if (index >= 0) { return new Reading(REPORT_U[index], REPORT_I[index]); }
  const u = interpolate(resistance, REPORT_R, REPORT_U, false);
  let i = interpolate(resistance, REPORT_R, REPORT_I, false) * 25.2 / 25.5;
  const target = .75 * 25.2 * 2.55;
  const p0 = 2 * 24.2 * 25.2 / 25.5;
  const alpha = Math.max(.6, Math.min(1.6, target / p0));
  i *= 1 + (alpha - 1) * Math.exp(-Math.pow((resistance - 82) / 20.5, 2));
  return new Reading(Math.max(0, u), Math.max(0, i));
}

export function distanceReading(distance: number): Reading {
  if (!inRange(distance, 5, 100)) { throw new Error('距离范围：5～100 cm'); }
  return new Reading(interpolate(distance, REPORT_D, REPORT_VOC), interpolate(distance, REPORT_D, REPORT_ISC));
}

export function intensity(distance: number): number {
  if (!inRange(distance, 5, 100)) { throw new Error('距离范围：5～100 cm'); }
  return interpolate(distance, REPORT_D, REPORT_E);
}

function checkCell(p: CellParameters, temperature: number): void {
  if (!inRange(p.iph, 0, 100) || !inRange(p.i0, 1e-30, 1) || !inRange(p.rs, 0, 1e6) ||
    !inRange(p.rsh, 1e-9, 1e12) || !inRange(p.n, .01, 100) ||
    !inRange(p.cells, 1, 100000) || !Number.isInteger(p.cells) || !inRange(temperature, 1, 2000)) {
    throw new Error('电池参数无效');
  }
}

function residual(vCell: number, current: number, p: CellParameters, t: number): number {
  const junction = vCell + current * p.rs;
  return p.iph - p.i0 * Math.expm1(Math.min(700, junction / (p.n * 1.381e-23 * t / 1.602e-19))) -
    junction / p.rsh - current;
}

// Monotone residuals permit bounded bisection without SciPy or an initial guess.
export function openCircuit(p: CellParameters = new CellParameters(), t: number = 298.15): number {
  checkCell(p, t);
  let lo = 0;
  let hi = p.n * 1.381e-23 * t / 1.602e-19 * Math.log1p(p.iph / p.i0);
  for (let j = 0; j < 80; j++) {
    const mid = (lo + hi) / 2;
    if (residual(mid, 0, p, t) > 0) { lo = mid; } else { hi = mid; }
  }
  return (lo + hi) / 2 * p.cells;
}

export function currentAt(v: number, p: CellParameters = new CellParameters(), t: number = 298.15): number {
  checkCell(p, t);
  if (!Number.isFinite(v) || v < 0) { throw new Error('电压无效'); }
  let lo = 0;
  let hi = p.iph;
  for (let j = 0; j < 80; j++) {
    const mid = (lo + hi) / 2;
    if (residual(v / p.cells, mid, p, t) > 0) { lo = mid; } else { hi = mid; }
  }
  return (lo + hi) / 2;
}

export function theoreticalIV(p: CellParameters = new CellParameters(), t: number = 298.15, count: number = 200): Reading[] {
  if (!Number.isInteger(count) || !inRange(count, 2, 10000)) { throw new Error('曲线点数无效'); }
  const voc = openCircuit(p, t);
  const result: Reading[] = [];
  for (let j = 0; j < count; j++) {
    const v = voc * 1.02 * j / (count - 1);
    result.push(new Reading(v, currentAt(v, p, t) * 1000));
  }
  return result;
}

export function loadReading(resistance: number, p: CellParameters = new CellParameters()): Reading {
  if (!inRange(resistance, 0, 99999.9)) { throw new Error('电阻超出量程'); }
  let lo = 0;
  let hi = openCircuit(p);
  for (let j = 0; j < 70; j++) {
    const v = (lo + hi) / 2;
    if (v < currentAt(v, p) * resistance) { lo = v; } else { hi = v; }
  }
  const v = (lo + hi) / 2;
  return new Reading(v, currentAt(v, p) * 1000);
}

export class LedInput {
  count: number = 15;
  vm: number = 2.16;
  im: number = 21.7;
  vled: number = 2.8;
  iled: number = 8;
}

export class LedResult {
  parallel: number;
  series: number;
  voltage: number;
  current: number;
  perBranch: number;
  branches: number;
  constructor(parallel: number, series: number, voltage: number,
    current: number, perBranch: number, branches: number) {
    this.parallel = parallel; this.series = series; this.voltage = voltage;
    this.current = current; this.perBranch = perBranch; this.branches = branches;
  }
  total(): number { return this.perBranch * this.branches; }
}

export function ledCombinations(p: LedInput): LedResult[] {
  if (!Number.isInteger(p.count) || !inRange(p.count, 1, 10000) ||
    !inRange(p.vm, .001, 10000) || !inRange(p.im, .001, 100000) ||
    !inRange(p.vled, .001, 10000) || !inRange(p.iled, .001, 100000)) {
    throw new Error('请输入有效的正数，电池数量须为 1～10000 的整数');
  }
  const rows: LedResult[] = [];
  for (let m = 1; m <= p.count; m++) {
    if (p.count % m !== 0) { continue; }
    const n = p.count / m;
    const v = n * p.vm;
    const i = m * p.im;
    rows.push(new LedResult(m, n, v, i, Math.floor(v / p.vled + 1e-12), Math.floor(i / p.iled + 1e-12)));
  }
  return rows.sort((a: LedResult, b: LedResult) => b.total() - a.total() || a.parallel - b.parallel);
}

// Shape-preserving cubic Hermite interpolation (PCHIP); duplicate x values are averaged.
export function smoothCurve(points: CurvePoint[]): CurvePoint[] {
  const sorted = points.slice().sort((a: CurvePoint, b: CurvePoint) => a.x - b.x);
  const knots: CurvePoint[] = [];
  for (let i = 0; i < sorted.length;) {
    let j = i + 1;
    let sum = sorted[i].y;
    while (j < sorted.length && sorted[j].x === sorted[i].x) { sum += sorted[j++].y; }
    knots.push(new CurvePoint(sorted[i].x, sum / (j - i)));
    i = j;
  }
  if (knots.length < 3) { return knots; }
  const h: number[] = [];
  const d: number[] = [];
  for (let i = 0; i < knots.length - 1; i++) {
    h.push(knots[i + 1].x - knots[i].x);
    d.push((knots[i + 1].y - knots[i].y) / h[i]);
  }
  const slopes: number[] = [endSlope(h[0], h[1], d[0], d[1])];
  for (let i = 1; i < knots.length - 1; i++) {
    const w1 = 2 * h[i] + h[i - 1];
    const w2 = h[i] + 2 * h[i - 1];
    slopes.push(d[i - 1] * d[i] <= 0 ? 0 : (w1 + w2) / (w1 / d[i - 1] + w2 / d[i]));
  }
  const last = h.length - 1;
  slopes.push(endSlope(h[last], h[last - 1], d[last], d[last - 1]));
  const output: CurvePoint[] = [];
  for (let i = 0; i < knots.length - 1; i++) {
    for (let j = 0; j < 12; j++) {
      const t = j / 12;
      const t2 = t * t;
      const t3 = t2 * t;
      output.push(new CurvePoint(knots[i].x + h[i] * t,
        (2 * t3 - 3 * t2 + 1) * knots[i].y + (t3 - 2 * t2 + t) * h[i] * slopes[i] +
        (-2 * t3 + 3 * t2) * knots[i + 1].y + (t3 - t2) * h[i] * slopes[i + 1]));
    }
  }
  output.push(knots[knots.length - 1]);
  return output;
}

function endSlope(h0: number, h1: number, d0: number, d1: number): number {
  const result = ((2 * h0 + h1) * d0 - h0 * d1) / (h0 + h1);
  if (result * d0 <= 0) { return 0; }
  if (d0 * d1 < 0 && Math.abs(result) > 3 * Math.abs(d0)) { return 3 * d0; }
  return result;
}
