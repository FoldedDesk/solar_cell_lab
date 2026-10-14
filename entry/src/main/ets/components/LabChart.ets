import { CurvePoint, smoothCurve } from '../model/Physics';

@Component
export struct LabChart {
  @Prop @Watch('redraw') points: CurvePoint[] = [];
  @Prop @Watch('redraw') smooth: boolean = false;
  @Prop @Watch('redraw') xLabel: string = 'U (V)';
  @Prop @Watch('redraw') yLabel: string = 'I (mA)';
  private context: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true));
  private ready: boolean = false;

  redraw(): void {
    if (!this.ready) { return; }
    const ctx = this.context;
    const width = ctx.width; const height = ctx.height;
    if (width < 100 || height < 100) { return; }
    ctx.clearRect(0, 0, width, height);
    const left = 50; const top = 25; const right = width - 20; const bottom = height - 42;
    let maxX = 1; let maxY = 1;
    this.points.forEach((p: CurvePoint) => { maxX = Math.max(maxX, p.x); maxY = Math.max(maxY, p.y); });
    maxX *= 1.08; maxY *= 1.12;
    ctx.font = '11px sans-serif'; ctx.lineWidth = 1;
    for (let i = 0; i <= 4; i++) {
      const x = left + (right - left) * i / 4;
      const y = bottom - (bottom - top) * i / 4;
      ctx.strokeStyle = '#E1EAEB'; ctx.beginPath();
      ctx.moveTo(left, y); ctx.lineTo(right, y); ctx.moveTo(x, top); ctx.lineTo(x, bottom); ctx.stroke();
      ctx.fillStyle = '#536C76'; ctx.textAlign = 'center';
      ctx.fillText((maxX * i / 4).toFixed(maxX > 100 ? 0 : 1), x, bottom + 18);
      ctx.textAlign = 'right'; ctx.fillText((maxY * i / 4).toFixed(maxY > 100 ? 0 : 1), left - 8, y + 4);
    }
    ctx.fillStyle = '#264B57'; ctx.textAlign = 'left'; ctx.fillText(this.yLabel, left, 14);
    ctx.textAlign = 'right'; ctx.fillText(this.xLabel, right, height - 4);
    if (this.points.length === 0) {
      ctx.textAlign = 'center'; ctx.fillStyle = '#738B92';
      ctx.fillText('记录数据后显示曲线', (left + right) / 2, (top + bottom) / 2); return;
    }
    const points = this.smooth ? smoothCurve(this.points) : this.points;
    ctx.strokeStyle = '#147D83'; ctx.lineWidth = 2.5; ctx.beginPath();
    points.forEach((point: CurvePoint, index: number) => {
      const x = left + point.x / maxX * (right - left);
      const y = bottom - point.y / maxY * (bottom - top);
      if (index === 0) { ctx.moveTo(x, y); } else { ctx.lineTo(x, y); }
    });
    ctx.stroke(); ctx.fillStyle = '#147D83';
    this.points.forEach((point: CurvePoint) => {
      ctx.beginPath(); ctx.arc(left + point.x / maxX * (right - left),
        bottom - point.y / maxY * (bottom - top), 3.5, 0, 2 * Math.PI); ctx.fill();
    });
  }

  build() {
    Canvas(this.context)
      .width('100%').height(240)
      .onReady(() => { this.ready = true; this.redraw(); })
      .onAreaChange(() => this.redraw())
      .accessibilityText(`${this.yLabel} 与 ${this.xLabel} 曲线，${this.points.length} 个数据点；数值见下方数据记录`)
  }
}
