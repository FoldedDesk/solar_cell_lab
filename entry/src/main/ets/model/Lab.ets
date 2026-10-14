import { Reading, CurvePoint, LedInput, ledCombinations, inRange, reportIV, loadReading,
  distanceReading, intensity, REPORT_R, REPORT_U, REPORT_I, REPORT_D, REPORT_E,
  REPORT_VOC, REPORT_ISC } from './Physics';

export enum Experiment { IV = 0, Distance = 1, Led = 2 }
export enum Source { Report = 0, Theory = 1, Manual = 2 }
export enum MeasureMode { Isc = 0, Voc = 1 }
export const TERMINALS: string[] = ['panel_p', 'panel_n', 'amm_p', 'amm_n', 'vol_p', 'vol_n', 'res_p', 'res_n'];
export const TERMINAL_NAMES: string[] = ['电池 +', '电池 −', '电流表 +', '电流表 −', '电压表 +', '电压表 −', '电阻 +', '电阻 −'];

export class IVRecord {
  resistance: number;
  voltage: number;
  current: number;
  source: Source;
  constructor(resistance: number, voltage: number, current: number, source: Source) {
    this.resistance = resistance; this.voltage = voltage; this.current = current; this.source = source;
  }
  power(): number { return this.voltage * this.current; }
}

export class DistanceRecord {
  distance: number;
  light: number;
  voltage: number;
  current: number;
  constructor(distance: number, light: number, voltage: number = -1, current: number = -1) {
    this.distance = distance; this.light = light; this.voltage = voltage; this.current = current;
  }
  complete(): boolean { return this.voltage >= 0 && this.current >= 0; }
}

export class Analysis {
  isc: number = 0;
  voc: number = 0;
  maxPower: number = 0;
  vm: number = 0;
  im: number = 0;
  resistance: number = 0;
  ff: number = 0;
  hasShortCircuit: boolean = false;
  hasOpenCircuit: boolean = false;
}

export function analyze(rows: IVRecord[]): Analysis {
  const result = new Analysis();
  let largestResistance = -1;
  rows.forEach((row: IVRecord) => {
    if (row.resistance === 0) { result.isc = row.current; result.hasShortCircuit = true; }
    if (row.resistance > largestResistance) {
      largestResistance = row.resistance; result.voc = row.voltage;
      result.hasOpenCircuit = row.current <= .3 && row.resistance >= 9999;
    }
    if (row.power() > result.maxPower + 1e-9 ||
      (Math.abs(row.power() - result.maxPower) <= 1e-9 && row.resistance < result.resistance)) {
      result.maxPower = row.power(); result.vm = row.voltage;
      result.im = row.current; result.resistance = row.resistance;
    }
  });
  if (result.isc * result.voc > 0) { result.ff = result.maxPower / (result.isc * result.voc); }
  return result;
}

export function wireKey(a: string, b: string): string {
  return a < b ? `${a}|${b}` : `${b}|${a}`;
}

export function standardWires(experiment: Experiment, mode: MeasureMode): string[] {
  if (experiment === Experiment.IV) {
    return [wireKey('panel_p', 'amm_p'), wireKey('amm_n', 'res_p'), wireKey('res_n', 'panel_n'),
      wireKey('vol_p', 'res_p'), wireKey('vol_n', 'res_n')];
  }
  return mode === MeasureMode.Isc ? [wireKey('panel_p', 'amm_p'), wireKey('amm_n', 'panel_n')] :
    [wireKey('panel_p', 'vol_p'), wireKey('vol_n', 'panel_n')];
}

function sameWires(a: string[], b: string[]): boolean {
  return a.length === b.length && b.every((wire: string) => a.includes(wire));
}

export function validWiring(wires: string[], experiment: Experiment, mode: MeasureMode): boolean {
  if (sameWires(wires, standardWires(experiment, mode))) { return true; }
  if (experiment === Experiment.IV) { return false; }
  const meter = mode === MeasureMode.Isc ? 'amm' : 'vol';
  return sameWires(wires, [wireKey('panel_p', `${meter}_n`), wireKey('panel_n', `${meter}_p`)]);
}

export function sourceName(source: Source): string {
  if (source === Source.Manual) { return '手动录入'; }
  return source === Source.Theory ? '单二极管模型' : '报告参考数据';
}

export function wideLayout(width: number): boolean { return width >= 840; }

export class LabSession {
  schemaVersion: number = 1;
  tab: Experiment = Experiment.IV;
  source: Source = Source.Report;
  mode: MeasureMode = MeasureMode.Isc;
  resistance: number = 0;
  distance: number = 30;
  ivWires: string[] = [];
  distanceWires: string[] = [];
  ivRows: IVRecord[] = [];
  distanceRows: DistanceRecord[] = [];
  led: LedInput = new LedInput();
  smooth: boolean = false;

  clone(): LabSession {
    const copy = new LabSession();
    copy.tab = this.tab; copy.source = this.source; copy.mode = this.mode;
    copy.resistance = this.resistance; copy.distance = this.distance; copy.smooth = this.smooth;
    copy.ivWires = this.ivWires.slice(); copy.distanceWires = this.distanceWires.slice();
    copy.ivRows = this.ivRows.slice(); copy.distanceRows = this.distanceRows.slice();
    copy.led = this.led;
    return copy;
  }

  wires(): string[] { return this.tab === Experiment.IV ? this.ivWires : this.distanceWires; }
  connected(): boolean { return validWiring(this.wires(), this.tab, this.mode); }
  reading(): Reading {
    return this.tab === Experiment.Distance ? distanceReading(this.distance) :
      (this.source === Source.Theory ? loadReading(this.resistance) : reportIV(this.resistance));
  }

  autoWire(): void { this.setWires(standardWires(this.tab, this.mode)); }
  clearWires(): void { this.setWires([]); }
  private setWires(wires: string[]): void {
    if (this.tab === Experiment.IV) { this.ivWires = wires; } else { this.distanceWires = wires; }
  }

  toggleWire(a: string, b: string): void {
    if (!TERMINALS.includes(a) || !TERMINALS.includes(b) || a.split('_')[0] === b.split('_')[0]) {
      throw new Error('请选择不同器材的两个端子');
    }
    const key = wireKey(a, b);
    const wires = this.wires();
    if (wires.includes(key)) { this.setWires(wires.filter((w: string) => w !== key)); return; }
    const degreeA = wires.filter((w: string) => w.split('|').includes(a)).length;
    const degreeB = wires.filter((w: string) => w.split('|').includes(b)).length;
    if (degreeA >= 2 || degreeB >= 2) { throw new Error('每个端子最多连接两根导线'); }
    this.setWires(wires.concat([key]));
  }

  changeMode(mode: MeasureMode): void {
    if (mode !== this.mode) { this.distanceWires = []; this.mode = mode; }
  }

  record(): string {
    if (!this.connected()) { throw new Error('请先完成正确接线'); }
    const reading = this.reading();
    if (this.tab === Experiment.IV) {
      this.addIV(this.resistance, reading.voltage, reading.current, this.source);
      return '已记录当前电阻的测量值';
    }
    const index = this.distanceRows.findIndex((row: DistanceRecord) => row.distance === this.distance);
    const old = index >= 0 ? this.distanceRows[index] : new DistanceRecord(this.distance, intensity(this.distance));
    if (old.complete()) { throw new Error('该距离已有完整数据，请先删除再测量'); }
    if ((this.mode === MeasureMode.Isc && old.current >= 0) || (this.mode === MeasureMode.Voc && old.voltage >= 0)) {
      throw new Error('该项已记录，请切换测量模式');
    }
    const row = new DistanceRecord(old.distance, old.light,
      this.mode === MeasureMode.Voc ? reading.voltage : old.voltage,
      this.mode === MeasureMode.Isc ? reading.current : old.current);
    if (index < 0) { this.distanceRows.push(row); } else { this.distanceRows[index] = row; }
    return row.complete() ? '同一距离的 Isc 与 Voc 已合成完整记录' :
      `已保存，请切换到 ${this.mode === MeasureMode.Isc ? 'Voc' : 'Isc'} 继续测量`;
  }

  addIV(resistance: number, voltage: number, current: number, source: Source = Source.Manual): void {
    this.checkIV(resistance, voltage, current);
    if (this.ivRows.some((row: IVRecord) => row.resistance === resistance)) { throw new Error('该电阻已有记录，可在数据表中编辑'); }
    if (this.ivRows.length >= 1000) { throw new Error('记录已达 1000 条，请先导出并清空'); }
    this.ivRows.push(new IVRecord(resistance, voltage, current, source));
  }

  editIV(oldResistance: number, resistance: number, voltage: number, current: number): void {
    this.checkIV(resistance, voltage, current);
    const index = this.ivRows.findIndex((row: IVRecord) => row.resistance === oldResistance);
    if (index < 0) { throw new Error('待编辑记录已不存在'); }
    if (this.ivRows.some((row: IVRecord, i: number) => i !== index && row.resistance === resistance)) {
      throw new Error('该电阻已有其他记录');
    }
    this.ivRows[index] = new IVRecord(resistance, voltage, current, Source.Manual);
  }

  private checkIV(r: number, v: number, i: number): void {
    if (!inRange(r, 0, 99999.9) || !inRange(v, 0, 10) || !inRange(i, 0, 200)) {
      throw new Error('量程：R 0～99999.9 Ω，U 0～10 V，I 0～200 mA');
    }
  }

  loadStandard(): void {
    if (this.tab === Experiment.IV) {
      this.ivRows = REPORT_R.map((r: number, i: number) => new IVRecord(r, REPORT_U[i], REPORT_I[i], Source.Report));
    } else {
      this.distanceRows = REPORT_D.map((d: number, i: number) => new DistanceRecord(d, REPORT_E[i], REPORT_VOC[i], REPORT_ISC[i]));
    }
  }

  deleteRow(key: number): void {
    if (this.tab === Experiment.IV) { this.ivRows = this.ivRows.filter((row: IVRecord) => row.resistance !== key); }
    else { this.distanceRows = this.distanceRows.filter((row: DistanceRecord) => row.distance !== key); }
  }

  clearRows(): void {
    if (this.tab === Experiment.IV) { this.ivRows = []; } else { this.distanceRows = []; }
  }

  chart(power: boolean): CurvePoint[] {
    if (this.tab === Experiment.IV) {
      return this.ivRows.map((row: IVRecord) => new CurvePoint(row.voltage, power ? row.power() : row.current))
        .sort((a: CurvePoint, b: CurvePoint) => a.x - b.x);
    }
    return this.distanceRows.filter((row: DistanceRecord) => row.complete())
      .map((row: DistanceRecord) => new CurvePoint(row.light, power ? row.current : row.voltage))
      .sort((a: CurvePoint, b: CurvePoint) => a.x - b.x);
  }

  static decode(text: string): LabSession {
    const data = JSON.parse(text) as LabSession;
    if (!data || data.schemaVersion !== 1 || !Array.isArray(data.ivRows) || !Array.isArray(data.distanceRows) ||
      !Array.isArray(data.ivWires) || !Array.isArray(data.distanceWires) || !data.led ||
      !inRange(data.tab, 0, 2) || !Number.isInteger(data.tab) || !inRange(data.source, 0, 1) ||
      !Number.isInteger(data.source) || !inRange(data.mode, 0, 1) || !Number.isInteger(data.mode) ||
      !inRange(data.resistance, 0, 99999.9) || !inRange(data.distance, 5, 100) || data.distance % 5 !== 0 ||
      typeof data.smooth !== 'boolean' || data.ivRows.length > 1000 || data.distanceRows.length > 20) {
      throw new Error('保存的实验格式无效');
    }
    const session = new LabSession();
    session.tab = data.tab; session.source = data.source; session.mode = data.mode;
    session.resistance = data.resistance; session.distance = data.distance; session.smooth = data.smooth;
    data.ivRows.forEach((row: IVRecord) => {
      if (!row || !inRange(row.source, 0, 2) || !Number.isInteger(row.source)) { throw new Error('记录来源无效'); }
      session.addIV(row.resistance, row.voltage, row.current, row.source);
    });
    data.distanceRows.forEach((row: DistanceRecord) => {
      if (!row || !inRange(row.distance, 5, 100) || row.distance % 5 !== 0 || !inRange(row.light, 0, 10000) ||
        !(row.voltage === -1 || inRange(row.voltage, 0, 10)) || !(row.current === -1 || inRange(row.current, 0, 10000)) ||
        (row.voltage === -1 && row.current === -1) || session.distanceRows.some((r: DistanceRecord) => r.distance === row.distance)) {
        throw new Error('距离记录无效');
      }
      session.distanceRows.push(new DistanceRecord(row.distance, row.light, row.voltage, row.current));
    });
    session.ivWires = validateWires(data.ivWires);
    session.distanceWires = validateWires(data.distanceWires);
    ledCombinations(data.led);
    session.led = data.led;
    return session;
  }
}

function validateWires(wires: string[]): string[] {
  const result: string[] = [];
  if (wires.length > 8) { throw new Error('接线记录无效'); }
  wires.forEach((wire: string) => {
    if (typeof wire !== 'string') { throw new Error('接线记录无效'); }
    const parts = wire.split('|');
    if (parts.length !== 2 || !TERMINALS.includes(parts[0]) || !TERMINALS.includes(parts[1]) ||
      parts[0].split('_')[0] === parts[1].split('_')[0] || result.includes(wire) || wire !== wireKey(parts[0], parts[1])) {
      throw new Error('接线记录无效');
    }
    result.push(wire);
  });
  if (TERMINALS.some((term: string) => result.filter((wire: string) => wire.split('|').includes(term)).length > 2)) {
    throw new Error('接线数量无效');
  }
  return result;
}
