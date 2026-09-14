# FlClash 自定义版更新流程

本分支在官方 FlClash 基础上增加节点分享链接导入，并保留 Windows 本地打包支持。官方仓库仍是
`origin`，更新方式是把本分支的提交重新应用到最新的 `origin/main`，不要直接安装应用内提示的官方安装包。

## 更新前

关闭正在运行的 FlClash，然后进入项目目录：

```powershell
cd F:\project\CodexProject\FlClash
git switch codex/proxy-link-import
git status --short
```

`git status --short` 必须没有输出。若还有正在开发的改动，先提交或暂存；不要在脏工作区中更新。

可以在更新前建立一个本地备份分支：

```powershell
git branch backup/custom-before-update
```

## 合并官方更新

```powershell
git fetch origin
git rebase origin/main
git submodule update --init --recursive
flutter pub get
```

`rebase` 会先取得官方新版本，再把本分支的自定义提交依次重新应用到新版代码上。没有冲突时，本地功能会自动保留。

如果出现冲突，运行 `git status` 查看文件，编辑后执行：

```powershell
git add <已解决的文件>
git rebase --continue
```

需要放弃本次更新并回到更新前状态时执行：

```powershell
git rebase --abort
```

## 保留本地化文案

本项目的翻译源文件是：

- `arb/intl_en.arb`
- `arb/intl_zh_CN.arb`
- `arb/intl_ja.arb`
- `arb/intl_ru.arb`

节点导入功能新增了 `profileImportTip`、`invalidProxyLink`、`unsupportedProxyLink`，并修改了 `urlDesc`、
`importFromURL`。发生 ARB 冲突时，以官方新版文件为底稿，同时保留这五组键在四种语言中的值。

`lib/l10n/l10n.dart` 和 `lib/l10n/intl/` 是生成文件，不要手工合并。解决四个 ARB 文件后重新生成：

```powershell
dart run intl_utils:generate
git add arb lib/l10n
git rebase --continue
```

如果上游已经实现了相同的键或功能，应按新版 API 合并语义，避免保留两份重复入口。

## 验证和重新打包

```powershell
flutter test test\common\proxy_share_test.dart test\pages\scan_test.dart test\setup_test.dart
flutter analyze --no-fatal-infos
dart setup.dart windows --targets exe --env stable
```

安装程序输出到：

```text
dist\FlClash-<版本>-windows-amd64-setup.exe
```

安装器沿用官方 AppId，会升级同一份 FlClash 安装并保留通常位于用户数据目录中的配置。反过来安装官方安装包也会覆盖
自定义程序文件，因此应用内更新只作为官方新版通知使用；合并源码并重新打包后，再安装新的自定义安装包。

## 可选：发布自己的更新

当前应用更新地址仍指向 `chen08209/FlClash`。如果需要自定义版独立检查更新，应把仓库 fork 到自己的 GitHub，
将 `lib/common/constant.dart` 中的 `repository` 改为自己的 `<账号>/<仓库>`，并在该仓库发布自定义安装包。
