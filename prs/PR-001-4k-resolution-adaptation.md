# PR-001: 多分辨率显示适配（720p / 1080p / 1.5K / 2K / 4K）

## 目标
- 在 `1280x720`、`1920x1080`、`2560x1440(1.5K/2K)`、`3840x2160(4K)` 下，控件都能正常显示与操作。
- 保证“可读、可点、无重叠、无截断、布局稳定”。

## 问题定位
- 当前 `auto` 分辨率上限被限制在 `1920x1080`，4K 屏幕无法充分利用空间。
- 现有控件存在固定像素尺寸（字体、面板宽度、按钮区、图表字号），在不同 DPI 下表现不一致。
- Windows 下若未启用 Per-Monitor DPI Awareness，易出现字体/点击热区/布局缩放不一致。

## 实施建议
1. 启用 DPI 感知（启动前）
- 文件：`main.py`
- 在创建 `Tk()` 前增加（Windows）：
  - `ctypes.windll.shcore.SetProcessDpiAwareness(2)`（优先）
  - 回退 `ctypes.windll.user32.SetProcessDPIAware()`

2. 重构分辨率策略（取消 1080p 硬上限）
- 文件：`gui/main_window.py`
- `auto` 改为：按屏幕比例动态计算，不再 clamp 到 `1920x1080`。
  - 建议：`w = clamp(int(sw * 0.92), 1180, int(sw * 0.96))`
  - 建议：`h = clamp(int(sh * 0.88), 700, int(sh * 0.92))`
- 保留固定档位（便于教学场景统一演示）：
  - `720p`: `1280x720`
  - `1080p`: `1920x1080`
  - `1.5K`: `2560x1440`
  - `2K`: `2560x1440`（与 1.5K 同档，文案可并列）
  - `4K`: `3200x1800`（窗口档位，避免全屏过大导致扫视负担）
  - `auto`: 跟随屏幕（推荐）

3. 建立统一 UI 缩放因子
- 文件：`gui/main_window.py`, `widgets/resistance_knob.py`
- 建议：
  - `ui_scale = clamp(min(sw / 1920, sh / 1080), 1.0, 2.0)`
  - `font_scale = max(ui_scale, 1.25)`（字体单独放大）
  - 所有关键固定像素值改为 `int(base * ui_scale)`：
    - 顶部栏高度与标题字号
    - Notebook Tab 字号与 padding
    - 右侧控制面板宽度（`right_w`）
    - 电阻箱按钮大小、数字字号、显示窗高度
    - 图表字体、图例、marker 大小

4. 图像资源按 UI 缩放重采样
- 文件：`gui/main_window.py`
- 设备图标目标尺寸纳入 `ui_scale`，继续使用 `LANCZOS` 重采样，避免 4K 下图标过小。
- 实验场景图标优先使用 `res/*.svg`（通过 `cairosvg` 运行时转换），PNG 仅作为回退。
- 设备框（`amm/res/vol/panel/lamp`）尺寸与坐标同步纳入 `ui_scale`，避免只放大图标导致接线端子和点击区域错位。
- 增加设备最小缩放下限（`device_scale >= 1.35`），保证 720p~4K 下仪表图标不会过小。
- 设备复位位置与距离实验中的面板移动边界同步按 `ui_scale` 计算，保证多分辨率下布局一致。
- 图标与标题区增加固定垂直留白；接线柱坐标改为贴合图标下缘位置绘制。

5. 交互最小尺寸保障
- 建议最小点击尺寸不低于 `32px`（缩放后）。
- 按钮和输入框垂直 padding 在低分辨率不小于 `4px`，高分辨率随 `ui_scale` 增长。
- 实际实现基线提升：
  - 顶栏高度最小 `48`
  - Tab 字体最小 `12`
  - 按钮字体最小 `13`，padding 基线 `14x10`
  - Treeview 行高最小 `28`
  - 电阻箱关键字体最小 `13/16/18`（标题/读数/数字）
  - 设置/工具箱子菜单字体纳入缩放（`menu_font`），避免高分辨率下菜单项过小
  - `gui/main_window.py` 内硬编码字体已统一接入 `font_scale`（含控制面板、实验台 Canvas、弹窗、帮助页、扩展页）
  - 针对视觉反馈优化：`toast` 提示框字体与设备图标内文字（A/V/R BOX）单独降档，避免相对主界面文字过大

## 验收标准（必须全部通过）
1. 720p（1280x720）
- 主窗口无控件遮挡与重叠。
- 右侧面板可完整滚览或完整展示关键操作项。
- 电阻箱与主要按钮可稳定点击。

2. 1080p（1920x1080）
- 当前体验不退化：布局结构与功能入口保持一致。
- 图表标题、坐标轴、图例清晰可读。

3. 1.5K（2560x1440）
- 控件视觉比例协调，不出现“字太小/按钮太密”。
- 切换标签页无布局跳变。

4. 2K（2560x1440，同档验收）
- 与 1.5K 一致通过；若设备标称 2K，按同分辨率策略验证。

5. 4K（3840x2160，100% 与 150% 缩放）
- `auto` 模式下主窗口尺寸显著高于 1080p 档，非固定在 `1920x1080`。
- 控件无点击热区偏移、无文字截断、无重叠。
- 图表与实验台可读可操作。

## 回归范围
- 功能回归：实验一、实验二、扩展页的核心流程不变。
- 性能回归：窗口初始化时间与图表刷新无明显退化。
- 不改动：`physics.py` 计算逻辑。

## 变更文件范围
- `main.py`
- `gui/main_window.py`
- `widgets/resistance_knob.py`

## 提交信息建议
- `feat(ui): adaptive multi-resolution scaling for 720p/1080p/1.5K/2K/4K`

## 比例冻结（当前基准）
- 说明：以下比例为当前版本的“位置基准”，后续微调应在此基础上变更并记录。

1. 实验场景设备基线
- 设备缩放：`device_scale = max(ui_scale, 1.35)`
- 设备原始尺寸：
  - `lamp`: `104 x 52`
  - `panel`: `122 x 78`
  - `amm/res/vol`: `96 x 96`

2. 光源（太阳能灯）
- 圆灯直径：`lamp_d = min(lamp.w, lamp.h) * 0.54`
- 圆灯中心：`(lamp.x + lamp.w/2, lamp.y + lamp.h/2 + 10)`（下移 10px）
- 光线起点：`ray_x = lamp_x1 + max(6, 6*ui_scale)`

3. 太阳能板内部图形
- 内框宽高比例：
  - `panel_inner_w = panel.w * 0.56`
  - `panel_inner_h = panel.h * 0.44`
- 位置：
  - 水平居中：`panel_inner_x0 = panel.x + (panel.w - panel_inner_w)/2`
  - 垂直：`panel_inner_y0 = panel.y + panel.h*0.28 + 10`（下移 10px）
- 栅线比例：`x = 0.24 / 0.50 / 0.76`

4. 仪表/电阻箱 SVG 区
- 标题高度：`title_h = max(24, 24*ui_scale)`
- 图标区留白：
  - 顶部：`icon_gap_top = max(10, 10*ui_scale)`
  - 底部：`icon_gap_bottom = max(8, 8*ui_scale)`
  - 左右：`icon_x_pad = max(4, 4*ui_scale)`
- 图标容器：
  - `icon_w = dev.w - 2*icon_x_pad`
  - `icon_h = dev.h - title_h - icon_gap_top - icon_gap_bottom`
- 图标资源：优先 `res/*.svg`（`cairosvg` 转换），PNG 回退。

5. 接线柱（amm/vol/res）
- 先按 SVG 实际可见边界定位（非外层容器）。
- 端子比例（橙色圆点区域）：
  - `amm`: `p=(0.32, 0.93)`, `n=(0.68, 0.93)`
  - `vol`: `p=(0.32, 0.93)`, `n=(0.68, 0.93)`
  - `res`: `p=(0.32, 0.93)`, `n=(0.68, 0.93)`
- 防重叠最小间距：`min_sep = max(18, 14*ui_scale)`
- 当前像素偏移：
  - `+`：`x_shift = -9`
  - `-`：`x_shift = +9`
  - `y_shift = -10`

6. 实验二距离刻度台（可用空间自适应）
- 预览画布：`fill=tk.X`，宽度随容器变化。
- 刻度范围：
  - `x0 = max(70, 0.11*canvas_width)`
  - `x1 = min(canvas_width - 40, 0.92*canvas_width)`
  - 最小可用回退：`x1 - x0 < 260` 时回退到安全区间。
- 滑条长度：`length = max(320, canvas_width - 24)`，随画布同步更新。
