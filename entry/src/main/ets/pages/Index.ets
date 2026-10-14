import { common } from '@kit.AbilityKit';
import { LabSession, Experiment, Source, MeasureMode, IVRecord, DistanceRecord, analyze,
  sourceName, wideLayout, TERMINALS, TERMINAL_NAMES } from '../model/Lab';
import { numberInput, intensity, LedInput, LedResult, ledCombinations } from '../model/Physics';
import { experimentTable, csv, xlsx, chartSvg, utf8 } from '../model/Export';
import { SessionStore, saveDocument } from '../services/Files';
import { CircuitBoard } from '../components/CircuitBoard';
import { LabChart } from '../components/LabChart';

const INK: string = '#173D4A';
const TEAL: string = '#147D83';
const MUTED: string = '#526D76';

@Entry
@Component
struct Index {
  @State private session: LabSession = new LabSession();
  @State private windowWidth: number = 360;
  @State private selectedTerminal: string = '';
  @State private resistanceText: string = '0';
  @State private manualR: string = '0';
  @State private manualU: string = '';
  @State private manualI: string = '';
  @State private editingR: number = -1;
  @State private manualVisible: boolean = false;
  @State private helpVisible: boolean = false;
  @State private exporting: boolean = false;
  @State private storageError: string = '';
  @State private nText: string = '15';
  @State private vmText: string = '2.16';
  @State private imText: string = '21.7';
  @State private vledText: string = '2.8';
  @State private iledText: string = '8';
  private store: SessionStore | undefined = undefined;

  aboutToAppear(): void {
    try {
      this.store = new SessionStore(this.getUIContext().getHostContext() as common.UIAbilityContext);
      this.session = this.store.load();
      this.resistanceText = String(this.session.resistance);
      this.nText = String(this.session.led.count); this.vmText = String(this.session.led.vm);
      this.imText = String(this.session.led.im); this.vledText = String(this.session.led.vled);
      this.iledText = String(this.session.led.iled);
    } catch (error) { this.storageError = `存档读取失败，原文件保留。${(error as Error).message}`; }
  }

  private toast(message: string): void {
    try { this.getUIContext().getPromptAction().showToast({ message: message, duration: 2500 }); }
    catch { console.warn('提示未显示，页面可能已关闭'); }
  }

  private commit(action: (session: LabSession) => void, message: string = ''): void {
    try {
      const next = this.session.clone(); action(next); this.session = next;
      if (this.storageError.length === 0) {
        try { this.store?.save(next); }
        catch (error) { this.storageError = `自动保存失败：${(error as Error).message}`; }
      }
      if (message.length > 0) { this.toast(message); }
    } catch (error) { this.toast((error as Error).message); }
  }

  private confirm(title: string, message: string, action: () => void): void {
    this.getUIContext().showAlertDialog({ title: title, message: message, autoCancel: true,
      primaryButton: { value: '取消', action: () => {} }, secondaryButton: { value: '确认', action: action } });
  }

  private selectTab(index: number): void {
    this.selectedTerminal = ''; this.editingR = -1; this.manualVisible = false;
    this.commit((s: LabSession) => { s.tab = index; });
  }

  private selectTerminal(terminal: string): void {
    if (this.selectedTerminal === terminal) { this.selectedTerminal = ''; return; }
    if (!this.selectedTerminal) { this.selectedTerminal = terminal; return; }
    const from = this.selectedTerminal; this.selectedTerminal = '';
    this.commit((s: LabSession) => s.toggleWire(from, terminal));
  }

  private setResistance(value: number): void {
    this.resistanceText = String(value);
    this.commit((s: LabSession) => { s.resistance = value; });
  }

  private applyResistance(): void {
    try { this.setResistance(Math.round(numberInput(this.resistanceText, 0, 99999.9) * 10) / 10); }
    catch (error) { this.toast((error as Error).message); }
  }

  private record(): void {
    let feedback = '';
    this.commit((s: LabSession) => { feedback = s.record(); });
    if (feedback) { this.toast(feedback); }
  }

  private saveManual(): void {
    try {
      const r = numberInput(this.manualR, 0, 99999.9);
      const u = numberInput(this.manualU, 0, 10); const i = numberInput(this.manualI, 0, 200);
      const next = this.session.clone();
      if (this.editingR >= 0) { next.editIV(this.editingR, r, u, i); } else { next.addIV(r, u, i); }
      this.commit((s: LabSession) => { s.ivRows = next.ivRows; }, '手动数据已保存');
      this.editingR = -1; this.manualVisible = false;
    } catch (error) { this.toast((error as Error).message); }
  }

  private edit(row: IVRecord): void {
    this.manualR = String(row.resistance); this.manualU = String(row.voltage); this.manualI = String(row.current);
    this.editingR = row.resistance; this.manualVisible = true;
    this.toast('编辑表单已打开，请在实验控制区修改');
  }

  private calculateLed(): void {
    try {
      const p = new LedInput();
      p.count = numberInput(this.nText, 1, 10000);
      p.vm = numberInput(this.vmText, .001, 10000); p.im = numberInput(this.imText, .001, 100000);
      p.vled = numberInput(this.vledText, .001, 10000); p.iled = numberInput(this.iledText, .001, 100000);
      ledCombinations(p);
      this.commit((s: LabSession) => { s.led = p; }, '串并联方案已更新');
    } catch (error) { this.toast((error as Error).message); }
  }

  private chartTitle(second: boolean): string {
    return this.session.tab === Experiment.IV ? (second ? '输出功率 P–V' : '伏安特性 I–V') :
      (second ? '短路电流 Isc–E' : '开路电压 Voc–E');
  }
  private xLabel(): string { return this.session.tab === Experiment.IV ? 'U (V)' : 'E (W/m²)'; }
  private yLabel(second: boolean): string {
    return this.session.tab === Experiment.IV ? (second ? 'P (mW)' : 'I (mA)') : (second ? 'Isc (mA)' : 'Voc (V)');
  }

  private async exportFile(extension: string, second: boolean = false): Promise<void> {
    if (this.exporting) { return; }
    const table = experimentTable(this.session);
    if (this.session.tab !== Experiment.Led && table.rows.length <= 1) { this.toast('请先记录实验数据'); return; }
    if (extension === 'svg' && this.session.chart(second).length < 2) { this.toast('曲线至少需要两组完整数据'); return; }
    this.exporting = true;
    try {
      let bytes = extension === 'xlsx' ? xlsx(table) : utf8(csv(table));
      const name = extension === 'svg' ? this.chartTitle(second) : table.name;
      if (extension === 'svg') { bytes = utf8(chartSvg(name, this.xLabel(), this.yLabel(second), this.session.chart(second), this.session.smooth)); }
      const saved = await saveDocument(this.getUIContext().getHostContext() as common.UIAbilityContext,
        `${name}-${Date.now()}.${extension}`, extension, bytes);
      this.toast(saved ? '文件已保存到所选位置' : '已取消导出');
    } catch (error) { this.toast(`导出未完成：${(error as Error).message}`); }
    finally { this.exporting = false; }
  }

  @Builder
  private action(label: string, action: () => void, primary: boolean = false) {
    Button(label, { type: ButtonType.Normal }).fontSize(14).fontWeight(FontWeight.Medium).height(44)
      .padding({ left: 16, right: 16 }).backgroundColor(primary ? TEAL : '#E8F1F1')
      .fontColor(primary ? Color.White : INK).borderRadius(12).margin({ right: 8, bottom: 8 }).onClick(action)
  }

  @Builder
  private field(label: string, value: string, change: (value: string) => void) {
    Column({ space: 6 }) {
      Text(label).fontSize(13).fontColor(MUTED).width('100%')
      TextInput({ text: value }).type(InputType.NUMBER_DECIMAL).fontSize(16).height(44).backgroundColor('#F0F5F5')
        .fontColor(INK).borderRadius(10).onChange(change).accessibilityText(label)
    }.width('100%').alignItems(HorizontalAlign.Start).margin({ bottom: 12 })
  }

  @Builder
  private metric(label: string, value: string, unit: string) {
    Column({ space: 6 }) {
      Text(label).fontSize(12).fontColor(MUTED)
      Text(value).fontSize(this.windowWidth < 380 ? 22 : 26).fontWeight(FontWeight.Bold).fontColor(TEAL)
      Text(unit).fontSize(12).fontColor(MUTED)
    }.layoutWeight(1).padding({ top: 16, bottom: 16 }).backgroundColor('#EDF5F4').borderRadius(12)
  }

  @Builder
  private header() {
    Column({ space: 12 }) {
      Row({ space: 12 }) {
        Image($r('app.media.app_icon')).width(44).height(44).borderRadius(12)
        Column({ space: 3 }) {
          Text('太阳能电池实验室').fontSize(this.windowWidth < 600 ? 20 : 26).fontWeight(FontWeight.Bold).fontColor(INK)
          Text('SOLAR CELL LAB · 光伏特性测量').fontSize(11).fontColor(MUTED)
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        Button('原理', { type: ButtonType.Normal }).height(44).fontSize(14).fontColor(TEAL)
          .backgroundColor('#E0EEEE').borderRadius(12).onClick(() => { this.helpVisible = !this.helpVisible; })
      }.width('100%')
      Row({ space: 6 }) {
        ForEach(['伏安特性', '距离特性', 'LED 优化'], (label: string, index: number) => {
          Button(label, { type: ButtonType.Normal }).layoutWeight(1).height(46).fontSize(14)
            .fontWeight(this.session.tab === index ? FontWeight.Bold : FontWeight.Regular)
            .backgroundColor(this.session.tab === index ? INK : '#E4EEEE')
            .fontColor(this.session.tab === index ? Color.White : MUTED).borderRadius(12).onClick(() => this.selectTab(index))
        })
      }.width('100%')
    }.padding({ left: 20, right: 20, top: 18, bottom: 14 }).width('100%').constraintSize({ maxWidth: 1600 })
  }

  @Builder
  private help() {
    Column({ space: 10 }) {
      Text('从光伏效应到最大功率点').fontSize(18).fontWeight(FontWeight.Bold).fontColor(INK)
      Text('光照使 P-N 结内载流子分离，形成电压与电流。改变负载电阻，测量 U、I，按 P = UI 得到最大功率点。填充因子 FF = Pmax / (Isc × Voc)。')
        .fontSize(14).fontColor(MUTED).lineHeight(23)
      Text('操作：依次点选两个器材端子连线，再选相同端子对可删线；也可使用一键接线。实验二需要在同一距离分别测 Isc 与 Voc，切换模式后重新接线。')
        .fontSize(14).fontColor(MUTED).lineHeight(23)
      Text('报告参考数据保留桌面版插值规则，属于教学参考，不能保证每个点都严格满足 U = IR。理论模式使用单二极管模型；手动录入可用于真实实验。LED 结果是理想额定值估算。')
        .fontSize(14).fontColor(MUTED).lineHeight(23)
    }.alignItems(HorizontalAlign.Start).padding(20).width('100%').backgroundColor('#E4F0EB').borderRadius(18)
  }

  @Builder
  private circuit() {
    Column({ space: 10 }) {
      Row() {
        Text('01  实验接线').fontSize(18).fontWeight(FontWeight.Bold).fontColor(INK).layoutWeight(1)
        Text(this.session.connected() ? '● 接线正确' : '○ 待接线').fontSize(13)
          .fontColor(this.session.connected() ? TEAL : '#986B20')
      }.width('100%')
      Text(this.session.tab === Experiment.IV ? '电流表串联 · 电压表并联于负载' :
        (this.session.mode === MeasureMode.Isc ? 'Isc：电池两端只接电流表，短路测量' : 'Voc：电池两端只接电压表，开路测量'))
        .fontSize(13).fontColor(MUTED).width('100%')
      CircuitBoard({ wires: this.session.wires(), selected: this.selectedTerminal,
        onTerminal: (terminal: string) => this.selectTerminal(terminal) })
      Text(this.selectedTerminal ? `已选 ${TERMINAL_NAMES[TERMINALS.indexOf(this.selectedTerminal)]}，请选择另一端` :
        '依次点选两个端子接线，重复连接可移除导线').fontSize(12).fontColor(MUTED).width('100%').constraintSize({ minHeight: 32 })
      Flex({ wrap: FlexWrap.Wrap }) {
        this.action('一键接线', () => { this.selectedTerminal = ''; this.commit((s: LabSession) => s.autoWire()); }, true)
        this.action('清除导线', () => { this.selectedTerminal = ''; this.commit((s: LabSession) => s.clearWires()); })
      }.width('100%')
    }.padding(16).backgroundColor(Color.White).borderRadius(18).width('100%')
  }

  @Builder
  private controls() {
    Column({ space: 14 }) {
      Text('02  调节与测量').fontSize(18).fontWeight(FontWeight.Bold).fontColor(INK).width('100%')
      if (this.session.tab === Experiment.IV) {
        Row({ space: 8 }) {
          Text('数据来源').fontSize(13).fontColor(MUTED)
          Select([{ value: '报告参考数据' }, { value: '单二极管模型' }]).selected(this.session.source)
            .value(sourceName(this.session.source)).font({ size: 14 }).layoutWeight(1)
            .onSelect((index: number) => this.commit((s: LabSession) => { s.source = index; }))
        }.width('100%')
        Text('固定光照条件 · 单晶硅 · 4 片串联').fontSize(12).fontColor(MUTED).width('100%')
        Row({ space: 8 }) {
          TextInput({ text: this.resistanceText, placeholder: '电阻 R（Ω）' }).type(InputType.NUMBER_DECIMAL)
            .height(46).layoutWeight(1).fontColor(INK).backgroundColor('#F0F5F5')
            .accessibilityText('电阻 R，单位欧姆，范围 0 到 99999.9')
            .onChange((value: string) => { this.resistanceText = value; }).onSubmit(() => this.applyResistance())
          Button('设置 Ω').height(46).fontSize(14).backgroundColor(TEAL).onClick(() => this.applyResistance())
        }.width('100%')
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach([0, 7, 23, 49, 82, 159, 9999], (r: number) => { this.action(`${r} Ω`, () => this.setResistance(r)) })
        }.width('100%')
        Row({ space: 8 }) {
          this.metric('电压 U', this.session.connected() ? this.session.reading().voltage.toFixed(3) : '—', 'V')
          this.metric('电流 I', this.session.connected() ? this.session.reading().current.toFixed(2) : '—', 'mA')
          this.metric('功率 P', this.session.connected() ? this.session.reading().power().toFixed(2) : '—', 'mW')
        }.width('100%')
      } else {
        Row({ space: 8 }) {
          this.action('测量 Isc', () => { this.selectedTerminal = ''; this.commit((s: LabSession) => s.changeMode(MeasureMode.Isc)); }, this.session.mode === MeasureMode.Isc)
          this.action('测量 Voc', () => { this.selectedTerminal = ''; this.commit((s: LabSession) => s.changeMode(MeasureMode.Voc)); }, this.session.mode === MeasureMode.Voc)
        }.width('100%')
        Text(`光源距离  ${this.session.distance.toFixed(0)} cm`).fontSize(20).fontWeight(FontWeight.Bold).fontColor(INK)
        Slider({ value: this.session.distance, min: 5, max: 100, step: 5, style: SliderStyle.OutSet })
          .width('100%').selectedColor(TEAL).showSteps(true).showTips(true).accessibilityText('光源距离，5 到 100 厘米，每步 5 厘米')
          .onChange((value: number, mode: SliderChangeMode) => {
            const next = this.session.clone(); next.distance = Math.round(value / 5) * 5; this.session = next;
            if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) { this.commit(() => {}); }
          })
        Row({ space: 8 }) {
          this.metric('光强 E', intensity(this.session.distance).toFixed(1), 'W/m²')
          this.metric(this.session.mode === MeasureMode.Isc ? '短路电流 Isc' : '开路电压 Voc',
            this.session.connected() ? (this.session.mode === MeasureMode.Isc ? this.session.reading().current.toFixed(2) : this.session.reading().voltage.toFixed(3)) : '—',
            this.session.mode === MeasureMode.Isc ? 'mA' : 'V')
        }.width('100%')
        Text('10～50 cm 使用报告标准数据；其余距离按原桌面版规则外推。').fontSize(12).fontColor(MUTED).width('100%')
      }
      Button(this.session.tab === Experiment.IV ? '记录当前测量值' : (this.session.mode === MeasureMode.Isc ? '记录 Isc' : '记录 Voc'))
        .width('100%').height(48).fontSize(16).fontWeight(FontWeight.Bold).backgroundColor(TEAL)
        .enabled(this.session.connected()).onClick(() => this.record())
      if (this.session.tab === Experiment.IV) {
        this.action(this.manualVisible ? '收起手动录入' : '手动录入 / 实测数据', () => { this.manualVisible = !this.manualVisible; })
        if (this.manualVisible) {
          Text(this.editingR >= 0 ? '编辑记录' : '新增实测记录').fontSize(16).fontWeight(FontWeight.Bold).fontColor(INK)
          this.field('电阻 R（Ω）', this.manualR, (v: string) => { this.manualR = v; })
          this.field('电压 U（V）', this.manualU, (v: string) => { this.manualU = v; })
          this.field('电流 I（mA）', this.manualI, (v: string) => { this.manualI = v; })
          Flex({ wrap: FlexWrap.Wrap }) {
            this.action(this.editingR >= 0 ? '保存修改' : '保存实测数据', () => this.saveManual(), true)
            this.action('取消', () => { this.editingR = -1; this.manualVisible = false; })
          }
        }
      }
    }.padding(18).backgroundColor(Color.White).borderRadius(18).width('100%')
  }

  @Builder
  private charts() {
    Column({ space: 14 }) {
      Row() {
        Text('03  特性曲线').fontSize(18).fontWeight(FontWeight.Bold).fontColor(INK).layoutWeight(1)
        Text('平滑').fontSize(13).fontColor(MUTED).margin({ right: 8 })
        Toggle({ type: ToggleType.Switch, isOn: this.session.smooth }).selectedColor(TEAL)
          .accessibilityText('使用 PCHIP 平滑插值').onChange((value: boolean) => this.commit((s: LabSession) => { s.smooth = value; }))
      }.width('100%')
      ForEach([false, true], (second: boolean) => {
        Text(this.chartTitle(second)).fontSize(15).fontWeight(FontWeight.Medium).fontColor(INK).width('100%')
        LabChart({ points: this.session.chart(second), smooth: this.session.smooth, xLabel: this.xLabel(), yLabel: this.yLabel(second) })
        Button('导出此曲线 SVG').height(44).fontSize(13).fontColor(TEAL).backgroundColor('#E8F1F1')
          .enabled(!this.exporting).onClick(() => { this.exportFile('svg', second); })
      })
      Text(this.session.tab === Experiment.IV ? '建议采集至少 10 组数据，并包含短路和近开路点。平滑曲线仅用于显示，分析始终使用记录值。' :
        '曲线仅使用已完成 Isc 与 Voc 两次测量的数据，横轴为光强 E。').fontSize(12).fontColor(MUTED).lineHeight(20).width('100%')
      if (this.session.tab === Experiment.IV && this.session.ivRows.length > 0) {
        Divider().color('#E3EBEC')
        Text(`记录中的最大功率  ${analyze(this.session.ivRows).maxPower.toFixed(2)} mW`)
          .fontSize(17).fontWeight(FontWeight.Bold).fontColor(TEAL).width('100%')
        Text(`Um = ${analyze(this.session.ivRows).vm.toFixed(3)} V  ·  Im = ${analyze(this.session.ivRows).im.toFixed(2)} mA  ·  R = ${analyze(this.session.ivRows).resistance} Ω`)
          .fontSize(13).fontColor(MUTED).width('100%')
        if (analyze(this.session.ivRows).hasShortCircuit && analyze(this.session.ivRows).hasOpenCircuit) {
          Text(`填充因子 FF ≈ ${analyze(this.session.ivRows).ff.toFixed(3)}（以近开路点估算 Voc）`).fontSize(14).fontColor(INK).width('100%')
        } else {
          Text('补充 R = 0 的短路点与 R ≥ 9999 Ω、I ≤ 0.3 mA 的近开路点后估算 FF。').fontSize(13).fontColor(MUTED).width('100%')
        }
        Text('混合不同数据来源时，分析结果仅供参考。').fontSize(12).fontColor(MUTED).width('100%')
      }
    }.padding(18).backgroundColor(Color.White).borderRadius(18).width('100%')
  }

  @Builder
  private dataTable() {
    Column({ space: 12 }) {
      Text(`04  数据记录 · ${this.session.tab === Experiment.IV ? this.session.ivRows.length : this.session.distanceRows.length} 组`)
        .fontSize(18).fontWeight(FontWeight.Bold).fontColor(INK).width('100%')
      Flex({ wrap: FlexWrap.Wrap }) {
        this.action('导入标准数据', () => this.confirm('导入标准数据', '将替换当前实验记录，建议先导出已有数据。', () => {
          this.editingR = -1; this.manualVisible = false; this.commit((s: LabSession) => s.loadStandard(), '标准数据已导入');
        }))
        this.action('清空记录', () => this.confirm('清空本实验记录', '此操作同时清除本实验的未完成测量。', () => {
          this.editingR = -1; this.manualVisible = false; this.commit((s: LabSession) => s.clearRows());
        }))
      }.width('100%')
      if ((this.session.tab === Experiment.IV ? this.session.ivRows.length : this.session.distanceRows.length) === 0) {
        Text('还没有记录。完成接线后采集，或导入标准数据开始观察。').fontSize(14).fontColor(MUTED)
          .padding({ top: 24, bottom: 24 }).width('100%')
      }
      if (this.session.tab === Experiment.IV) {
        ForEach(this.session.ivRows, (row: IVRecord) => {
          Column({ space: 6 }) {
            Row() {
              Text(`R  ${row.resistance} Ω`).fontSize(15).fontWeight(FontWeight.Bold).fontColor(INK).layoutWeight(1)
              Text(sourceName(row.source)).fontSize(11).fontColor(MUTED)
            }.width('100%')
            Text(`${row.voltage.toFixed(3)} V    ${row.current.toFixed(2)} mA    ${row.power().toFixed(2)} mW`).fontSize(14).fontColor(TEAL).width('100%')
            Row() {
              this.action('编辑', () => this.edit(row))
              this.action('删除', () => this.commit((s: LabSession) => s.deleteRow(row.resistance)))
            }.width('100%')
          }.padding(12).backgroundColor('#F2F6F6').borderRadius(12).width('100%')
        }, (row: IVRecord) => `${row.resistance}:${row.voltage}:${row.current}:${row.source}`)
      } else {
        ForEach(this.session.distanceRows, (row: DistanceRecord) => {
          Column({ space: 6 }) {
            Row() {
              Text(`${row.distance} cm · ${row.light.toFixed(1)} W/m²`).fontSize(15).fontWeight(FontWeight.Bold).fontColor(INK).layoutWeight(1)
              Text(row.complete() ? '完整' : '待补测').fontSize(12).fontColor(row.complete() ? TEAL : '#986B20')
            }.width('100%')
            Text(`Voc  ${row.voltage < 0 ? '待测' : row.voltage.toFixed(3) + ' V'}    Isc  ${row.current < 0 ? '待测' : row.current.toFixed(2) + ' mA'}`)
              .fontSize(14).fontColor(TEAL).width('100%')
            this.action('删除', () => this.commit((s: LabSession) => s.deleteRow(row.distance)))
          }.padding(12).backgroundColor('#F2F6F6').borderRadius(12).width('100%')
        }, (row: DistanceRecord) => `${row.distance}:${row.voltage}:${row.current}`)
      }
      this.exportButtons()
    }.padding(18).backgroundColor(Color.White).borderRadius(18).width('100%')
  }

  @Builder
  private exportButtons() {
    Flex({ wrap: FlexWrap.Wrap }) {
      Button(this.exporting ? '正在导出…' : '导出 Excel').height(44).fontSize(14).backgroundColor(TEAL)
        .margin({ right: 8, bottom: 8 }).enabled(!this.exporting).onClick(() => { this.exportFile('xlsx'); })
      Button('导出 CSV').height(44).fontSize(14).backgroundColor('#E8F1F1').fontColor(INK)
        .margin({ bottom: 8 }).enabled(!this.exporting).onClick(() => { this.exportFile('csv'); })
    }.width('100%')
  }

  @Builder
  private ledControls() {
    Column({ space: 8 }) {
      Text('配置电池与负载').fontSize(18).fontWeight(FontWeight.Bold).fontColor(INK).width('100%').margin({ bottom: 8 })
      this.field('电池总数 N（整数）', this.nText, (v: string) => { this.nText = v; })
      this.field('单块最大功率点电压 Vm（V）', this.vmText, (v: string) => { this.vmText = v; })
      this.field('单块最大功率点电流 Im（mA）', this.imText, (v: string) => { this.imText = v; })
      this.field('LED 额定电压（V）', this.vledText, (v: string) => { this.vledText = v; })
      this.field('LED 额定电流（mA）', this.iledText, (v: string) => { this.iledText = v; })
      Button('计算串并联方案').width('100%').height(48).backgroundColor(TEAL).fontSize(16).onClick(() => this.calculateLed())
      Text('默认 Vm、Im 对应报告中约 242 W/m² 的光照条件。参数修改后点击计算，更新结果。').fontSize(12).fontColor(MUTED).lineHeight(20).width('100%')
    }.padding(20).backgroundColor(Color.White).borderRadius(18).width('100%')
  }

  @Builder
  private ledResults() {
    Column({ space: 14 }) {
      Text('串并联优化方案').fontSize(20).fontWeight(FontWeight.Bold).fontColor(INK).width('100%')
      Text(`已计算参数：N = ${this.session.led.count}，Vm = ${this.session.led.vm} V，Im = ${this.session.led.im} mA；LED ${this.session.led.vled} V / ${this.session.led.iled} mA`)
        .fontSize(13).fontColor(MUTED).lineHeight(21).width('100%')
      ForEach(ledCombinations(this.session.led), (row: LedResult, index: number) => {
        Column({ space: 8 }) {
          Row() {
            Text(index === 0 ? '推荐方案' : `备选 ${index}`).fontSize(14).fontColor(index === 0 ? TEAL : MUTED).layoutWeight(1)
            Text(`${row.total()} 盏 LED`).fontSize(24).fontWeight(FontWeight.Bold).fontColor(INK)
          }.width('100%')
          Text(`每组 ${row.parallel} 块并联 × ${row.series} 组串联`).fontSize(17).fontWeight(FontWeight.Medium).fontColor(INK).width('100%')
          Text(`输出 ${row.voltage.toFixed(2)} V / ${row.current.toFixed(1)} mA\n每支路 ${row.perBranch} 盏串联，共 ${row.branches} 条并联支路`)
            .fontSize(14).fontColor(MUTED).lineHeight(22).width('100%')
        }.padding(18).width('100%').backgroundColor(index === 0 ? '#E1F1EA' : '#F1F5F5').borderRadius(16)
      }, (row: LedResult) => `${row.parallel}:${row.voltage}:${row.current}:${row.total()}`)
      Text('理想额定值估算：串联提高电压，并联增加电流；未计入驱动电路损耗、温度变化与电池失配。数量相同时优先选择较小的并联数。')
        .fontSize(13).fontColor(MUTED).lineHeight(22).width('100%')
      this.exportButtons()
    }.padding(20).backgroundColor(Color.White).borderRadius(18).width('100%')
  }

  @Builder
  private experimentContent() {
    if (wideLayout(this.windowWidth)) {
      Row({ space: 18 }) {
        Column({ space: 18 }) { this.circuit(); this.controls(); }.width(this.windowWidth >= 1280 ? '38%' : '44%')
        Column({ space: 18 }) { this.charts(); this.dataTable(); }.layoutWeight(1)
      }.alignItems(VerticalAlign.Top).width('100%')
    } else {
      Column({ space: 16 }) { this.circuit(); this.controls(); this.charts(); this.dataTable(); }.width('100%')
    }
  }

  build() {
    Column() {
      this.header()
      Scroll() {
        Column({ space: 18 }) {
          if (this.storageError.length > 0) {
            Column({ space: 10 }) {
              Text(this.storageError + ' 当前修改尚未自动保存，可先导出。').fontSize(13).fontColor('#8A531B').width('100%')
              this.action('用当前实验恢复自动保存', () => this.confirm('恢复自动保存', '将以当前实验替换原本地存档。', () => {
                try { this.store?.save(this.session); this.storageError = ''; this.toast('自动保存已恢复'); }
                catch (error) { this.toast((error as Error).message); }
              }))
            }.padding(16).backgroundColor('#FFF2D9').borderRadius(16).width('100%')
          }
          if (this.helpVisible) { this.help() }
          if (this.session.tab === Experiment.Led) {
            if (wideLayout(this.windowWidth)) {
              Row({ space: 18 }) {
                Column() { this.ledControls() }.width('36%')
                Column() { this.ledResults() }.layoutWeight(1)
              }.alignItems(VerticalAlign.Top).width('100%')
            } else { this.ledControls(); this.ledResults(); }
          } else { this.experimentContent() }
          Text(this.storageError.length > 0 ? '自动保存暂停 · 请先导出数据' : '实验保存在本机 · 无需联网 · 支持 Excel / CSV / SVG 导出')
            .fontSize(12).fontColor(MUTED).padding({ top: 4, bottom: 24 })
        }.padding({ left: this.windowWidth < 600 ? 12 : 20, right: this.windowWidth < 600 ? 12 : 20, top: 4 })
          .width('100%').constraintSize({ maxWidth: 1600 })
      }.layoutWeight(1).width('100%').align(Alignment.Top).scrollBar(BarState.Auto)
    }.width('100%').height('100%').backgroundColor('#F2F6F6')
      .onAreaChange((_old: Area, area: Area) => { this.windowWidth = Number(area.width); })
  }
}
