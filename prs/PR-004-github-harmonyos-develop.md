# PR-004：保留 GitHub 仓库并交付鸿蒙开发分支

## 目标

按用户最新要求继续使用 `https://github.com/FoldedDesk/solar_cell_lab.git`，将整理后的独立鸿蒙工程推送到已存在的 `HarmonyOS_Develop` 分支。分支名称以远端实际大小写为准。

## 范围与约束

- 延续 PR-003 的清理结果，DevEco 工程位于分支根目录；移除本分支中不再使用的桌面实现、Windows 工作流、教学附件及已跟踪的 Python 缓存。
- 原生代码、资源、构建脚本、18 项回归和数值基准与已验证的独立工程保持一致，继续采用 MIT 许可证。
- 在 GitHub 原有提交之后创建普通提交，推送到 `HarmonyOS_Develop`；保留现有历史及 `main` 分支。
- 本地独立鸿蒙工程以 GitHub 为 `origin`，跟踪 `origin/HarmonyOS_Develop`；此前的 AtomGit 地址保留为 `atomgit` 远端。
- 原桌面工作目录中的未提交改动不纳入本次工作目录切换。

## 验收与验证

1. `git ls-remote` 确认远端已有 `HarmonyOS_Develop`，初始提交为 `5f474619f6250a60c397be630dd0dbdabd4ed0bf`。
2. 对比 PR-003 已通过测试与构建的提交 `000d352a4d3a10c653a55c975de3a28c1cbe82f2`，除 README、协作规范及本 PR 文档外，文件内容一致；沿用该版本的 18 项测试和官方 HAP 构建结果。
3. 检查上传文件无构建产物、本机缓存、个人路径和签名材料；`git diff --check` 通过。
4. 普通推送成功后核对远端分支与本地提交 SHA 相同；确认 GitHub `main` 仍为原提交。
5. 本地独立鸿蒙工程位于 `HarmonyOS_Develop`，跟踪 GitHub 对应分支，工作区干净。

## 适用关系

PR-003 记录之前的 AtomGit 交付；本次 GitHub 远端与分支要求以本 PR 为准。实际设备测试范围沿用 README 中的说明。
