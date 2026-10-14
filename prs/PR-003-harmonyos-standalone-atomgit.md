# PR-003：独立鸿蒙工程整理与 AtomGit 上传

## 目标

将已完成的鸿蒙适配整理为独立仓库，上传到用户指定的 `https://gitcode.com/Folded_Desk/solar_cell_lab_harmonyos`。

## 范围与约束

- 工程配置、`AppScope/`、`entry/`、`hvigor/` 直接置于仓库根目录，DevEco 可直接打开。
- 保留原生实验、资源、本地存档、导出、构建脚本与回归测试。
- 新仓库移除 Python/Tkinter 桌面代码、Windows 工作流、教学 PDF/DOC、重复文档、临时文件及构建缓存。
- 以已验证的 Python/SciPy 数值基准替代测试对原仓库目录的依赖，基准附带源提交和文件 SHA-256；测试不再依赖 NumPy、SciPy、openpyxl。
- 沿用远端已有 MIT 许可证，补齐年份与仓库作者账号；包元数据统一标明 MIT。
- 上传源代码，不提交 HAP、SDK、个人路径、签名材料或账号凭据。
- 保留远端已有提交，通过普通提交推送到 `main`；不覆盖历史、不强制推送。

## 验收

1. 从独立仓库执行 `python3 scripts/verify.py`，18 项回归及 XLSX/CSV/SVG 校验通过。
2. 执行 `python3 scripts/build.py`，官方工具链 HAP 编译通过，manifest 包含 phone/tablet/2in1。
3. Git 跟踪文件只含有效源码、必要资源、文档和基准数据，无缓存、签名、凭据或二进制构建产物。
4. 远端 `main` 与本地提交 SHA 相同，并能读取到完整工程文件。

## 验证记录

- 2026-10-14：在独立仓库运行 `python3 scripts/verify.py`，18 项测试全部通过；3 份 XLSX 的 ZIP/XML 与单元格内容、CSV、SVG 校验通过。
- 使用 DevEco Studio 6.1.1、Hvigor 6.24.4、SDK 6.1.1.125 执行 `python3 scripts/build.py`，官方构建成功（7.683 秒），生成未签名 HAP。
- 解包 HAP 确认 `deviceTypes` 为 `phone`、`tablet`、`2in1`，应用标识为 `com.sdu.solarcelllab`。
- 上传清单包含 33 个文件；源码、配置、文档及固定数值基准均可独立使用，构建产物与本机缓存由 `.gitignore` 排除。
- 推送完成后以 `git ls-remote origin refs/heads/main` 对比本地提交，核对交付版本。
- 尚未连接鸿蒙设备；实际设备文件选择器、旋转、窗口缩放、键盘和大字体的验证范围见 README。
