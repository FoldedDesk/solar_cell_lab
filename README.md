# 太阳能电池实验室 · HarmonyOS

基于 ArkTS、ArkUI 和 Stage 模型的原生教学实验应用，适配鸿蒙手机、平板与电脑。计算、记录、分析和导出均在本机完成，无需网络服务。

鸿蒙代码位于现有 GitHub 仓库的 [`HarmonyOS_Develop` 分支](https://github.com/FoldedDesk/solar_cell_lab/tree/HarmonyOS_Develop)。克隆时使用 `git clone --branch HarmonyOS_Develop https://github.com/FoldedDesk/solar_cell_lab.git`。

## 功能

- **伏安特性**：端子接线与校验、电阻调节、报告参考数据、单二极管理论模型、手动实测记录、I–V / P–V 曲线、最大功率与填充因子分析。
- **距离特性**：5～100 cm 距离调节，分别测量 Isc / Voc，按距离合并两次记录，绘制 Voc–E / Isc–E 曲线。
- **LED 优化**：枚举电池串并联组合，按额定电压、电流估算可驱动的 LED 数量。
- **记录与导出**：自动保存并恢复未完成实验；支持 Excel `.xlsx`、UTF-8 `.csv` 和 SVG 曲线导出。
- **多设备布局**：小窗口纵向滚动，840 vp 起分栏；接线端子支持触摸、鼠标点击和键盘聚焦。

## 开始使用

用 DevEco Studio 打开**仓库根目录**，同步工程后构建。最低兼容 HarmonyOS 5.0.0 / API 12，目标 API 21；已在 DevEco Studio 6.1.1、SDK 6.1.1.125（API 24）验证编译。

安装到设备前，在 Project Structure → Signing Configs 中配置本机签名，再选择设备运行 `EntryAbility`。签名材料不包含在仓库中。

命令行构建需要 Python 3.10+ 和 DevEco Studio：

```bash
python3 scripts/build.py
```

输出：`entry/build/default/outputs/default/entry-default-unsigned.hap`。此文件尚未签名，设备安装需要签名。

脚本默认查找 macOS 的 `/Applications/DevEco-Studio.app/Contents`；其他安装位置通过 `DEVECO_STUDIO_HOME` 指定。它使用 IDE 自带的 Hvigor 和 SDK，在 ASCII 临时目录中构建，支持仓库路径包含中文或空格。成功后复制产物并清理临时目录，失败时保留诊断目录；日志位于 `test-output/build.log`。Windows 用户可直接使用 IDE 构建。

## 实验操作

1. 选择实验，依次点选两个器材端子连线；重复同一端子对可以删线，也可使用“一键接线”。
2. 实验一设置电阻后点击记录。同一电阻禁止重复采集，可以编辑或删除已有记录；手动录入可保存真实测量数据。
3. 实验二切换 Isc / Voc 后重新接线，在同一距离分别采集。顺序不限，未完成记录显示“待补测”；完整记录才进入曲线。
4. LED 参数修改后点击计算。默认 15 块电池的推荐组合为每组 5 块并联、3 组串联，理想估算可驱动 26 盏 LED。
5. Excel / CSV 保留单位、数据来源及待补测状态；文件通过系统文件选择器保存。曲线可以导出为可缩放的 SVG。

## 数据说明

报告参考数据及插值规则来自[原桌面项目](https://github.com/FoldedDesk/solar_cell_lab)。报告数据可能不严格满足 U = IR。理论模式使用单二极管模型和负载线求解；两者与手动录入均有来源标记。

界面使用 V、mA、mW 和 W/m²。平滑曲线采用 PCHIP，最大功率分析始终使用原始记录；功率在 1e-9 mW 容差内相同时优先较小电阻。填充因子需短路点与近开路点，Voc 取最大电阻处的电压并标为估算。LED 优化是额定值估算，不包含驱动损耗、温度和电池失配。

## 验证

在独立仓库根目录运行：

```bash
python3 scripts/verify.py
```

验证脚本仅使用 Python 标准库、Node.js 和 DevEco SDK 的 TypeScript 转译器，不依赖原桌面工程、NumPy、SciPy 或 openpyxl。18 项测试直接执行实际 ArkTS 模块，覆盖接线、两种测量顺序、状态恢复、异常文件写入、导出取消及格式校验。

数值回归使用 `tests/fixtures/desktop-reference.json`：包含 27 个电阻取值、191 个距离采样、三组温度与光生电流下的 600 个理论曲线点及 PCHIP 基准。基准由迁移时的 Python/SciPy 实现生成，内含源提交、文件 SHA-256 和生成环境。原生 UI 的语法、资源与完整工程由官方 HAP 构建另行检查。

已通过自动化测试和官方编译。实际设备上的文件选择器、旋转、窗口缩放、系统键盘和大字体仍需验证：手机重点检查 360 vp 纵向布局，平板检查 600/840 vp 与横竖屏切换，电脑检查 1280/1920 vp、鼠标和键盘操作。

## 目录

```text
AppScope/                 应用配置、名称和图标
entry/src/main/ets/
  entryability/           应用入口
  pages/                  自适应实验页面
  components/             接线板与曲线
  model/                  计算、实验状态、XLSX/CSV/SVG 导出
  services/               存档与系统文件选择器
hvigor/                   构建配置
scripts/                  构建与验证入口
tests/                    行为测试与固定数值基准
prs/                      开发要求及验收记录
```

## 许可证

[MIT License](LICENSE)，Copyright © 2026 Folded_Desk。
