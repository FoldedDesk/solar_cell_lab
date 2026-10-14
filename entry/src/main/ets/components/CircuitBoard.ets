import { TERMINALS, TERMINAL_NAMES } from '../model/Lab';

@Component
export struct CircuitBoard {
  @Prop @Watch('redraw') wires: string[] = [];
  @Prop selected: string = '';
  onTerminal: (terminal: string) => void = () => {};
  @State private boardWidth: number = 320;
  private context: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true));
  private ready: boolean = false;

  private termX(index: number): number {
    return this.boardWidth * (Math.floor(index / 2) % 2 === 0 ? .25 : .75) + (index % 2 === 0 ? -26 : 26);
  }
  private termY(index: number): number { return index < 4 ? 110 : 270; }

  redraw(): void {
    if (!this.ready) { return; }
    const ctx = this.context;
    ctx.clearRect(0, 0, ctx.width, ctx.height);
    for (let i = 0; i < 4; i++) {
      const x = this.boardWidth * (i % 2 === 0 ? .25 : .75);
      const y = i < 2 ? 60 : 220;
      ctx.fillStyle = i === 0 ? '#DBECEE' : '#E8EEEF';
      ctx.fillRect(x - 62, y - 38, 124, 126);
      ctx.fillStyle = '#173D4A'; ctx.textAlign = 'center'; ctx.font = '14px sans-serif';
      ctx.fillText(['太阳能电池', '电流表', '电压表', '电阻箱'][i], x, y - 17);
      if (i === 0) {
        ctx.fillStyle = '#1B657C'; ctx.fillRect(x - 34, y - 7, 68, 28);
        ctx.strokeStyle = '#9ECED1'; ctx.lineWidth = 1; ctx.beginPath();
        for (let j = 1; j <= 3; j++) { ctx.moveTo(x - 34 + j * 17, y - 7); ctx.lineTo(x - 34 + j * 17, y + 21); }
        ctx.moveTo(x - 34, y + 7); ctx.lineTo(x + 34, y + 7); ctx.stroke();
      } else {
        ctx.font = '24px sans-serif'; ctx.fillStyle = '#147D83';
        ctx.fillText(['', 'A', 'V', 'R'][i], x, y + 16);
      }
    }
    this.wires.forEach((wire: string, i: number) => {
      const parts = wire.split('|');
      const a = TERMINALS.indexOf(parts[0]); const b = TERMINALS.indexOf(parts[1]);
      if (a < 0 || b < 0) { return; }
      const ax = this.termX(a); const ay = this.termY(a);
      const bx = this.termX(b); const by = this.termY(b);
      const offset = 22 + i * 5;
      ctx.strokeStyle = '#398C8F'; ctx.lineWidth = 2.5; ctx.beginPath(); ctx.moveTo(ax, ay);
      ctx.bezierCurveTo(ax, ay + offset, bx, by + offset, bx, by); ctx.stroke();
    });
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Canvas(this.context).width('100%').height(330)
        .onReady(() => { this.ready = true; this.redraw(); })
        .onAreaChange((_old: Area, area: Area) => { this.boardWidth = Number(area.width); this.redraw(); })
        .accessibilityText('太阳能电池、电流表、电压表和电阻箱接线图')
      ForEach(TERMINALS, (terminal: string, index: number) => {
        Button(index % 2 === 0 ? '+' : '−', { type: ButtonType.Circle })
          .width(44).height(44).fontSize(20)
          .backgroundColor(this.selected === terminal ? '#D19A2D' : (index % 2 === 0 ? '#AE4254' : '#365867'))
          .fontColor(Color.White)
          .position({ x: this.termX(index) - 22, y: this.termY(index) - 22 })
          .accessibilityText(TERMINAL_NAMES[index] + (this.selected === terminal ? '，已选中' : '，点击选择接线端子'))
          .onClick(() => this.onTerminal(terminal))
      }, (terminal: string) => terminal)
    }.width('100%').height(330)
  }
}
