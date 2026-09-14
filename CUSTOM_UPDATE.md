# FlClash 自定义版更新手册

这份手册用于维护 `reevebyte/FlClash` 中的节点分享链接导入版。当前约定如下：

- 官方仓库：`https://github.com/chen08209/FlClash`，本地名称是 `upstream`。
- 个人 Fork：`https://github.com/reevebyte/FlClash`，本地名称是 `origin`。
- 官方原始分支：`upstream/main`。
- 自定义开发分支：`codex/proxy-link-import`。
- 本地项目目录：`F:\project\CodexProject\FlClash`。
- Windows 安装器输出目录：`dist`。

## 先理解更新在做什么

```text
官方 upstream/main
        │
        │ git fetch upstream + git rebase upstream/main
        ▼
本地 codex/proxy-link-import（官方新版 + 自定义提交）
        │
        │ git push --force-with-lease origin codex/proxy-link-import
        ▼
个人 Fork 的 codex/proxy-link-import
        │
        │ 测试并打包
        ▼
dist 中的自定义安装程序
```

官方更新不会直接修改自定义提交。`rebase` 会先把分支底座换成最新官方代码，再把节点导入和打包修复等自定义提交
依次重新应用到新底座上。官方和自定义版没有修改同一处代码时，这一过程会自动完成；修改了同一处时，Git 会暂停并要求
人工决定最终内容，这就是“冲突”。

个人 Fork 主要有两个用途：

1. 在 GitHub 上备份自定义源码，电脑损坏时仍能恢复。
2. 可选地创建自己的 Release，保存每次生成的安装程序。

Fork 本身不会让应用自动生成自定义更新。当前应用内更新仍检查官方仓库，只应把它当作“官方发布新版了”的通知。

## 一次性配置

本机已经配置完成，下面的命令仅用于检查：

```powershell
cd F:\project\CodexProject\FlClash
git remote -v
git branch --show-current
```

正确结果应包含：

```text
origin    https://github.com/reevebyte/FlClash.git
upstream  https://github.com/chen08209/FlClash.git
codex/proxy-link-import
```

首次把自定义分支上传到个人 Fork：

```powershell
git push -u origin codex/proxy-link-import
```

## 每次官方更新的完整流程

### 第 1 步：关闭 FlClash 并打开新 PowerShell

关闭 FlClash 是为了避免打包或安装时旧程序占用文件。重新打开 PowerShell 可以确保 Rust、Go、Inno Setup 等环境变量
已加载。

```powershell
cd F:\project\CodexProject\FlClash
git switch codex/proxy-link-import
```

### 第 2 步：确认本地改动已经保存

```powershell
git status --short
```

没有输出表示工作区干净，可以更新。若有输出，说明还有未提交文件：

- 确定要保留的源码改动，先用 `git add` 和 `git commit` 保存。
- 不认识的文件不要随意删除、覆盖或执行 `git reset --hard`，应先确认来源。
- `build`、`.dart_tool` 和 `dist` 通常已被 Git 忽略，不会出现在这里。

### 第 3 步：建立更新前的保险分支

```powershell
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
git branch "backup/proxy-link-import-$stamp"
```

这个分支是更新前的快照。如果后面操作错误，可以切回它。确认新版稳定后，可以稍后删除旧保险分支。

### 第 4 步：下载官方最新代码

```powershell
git fetch upstream --tags
```

`fetch` 只下载，不会改变当前源码，所以是安全的。查看官方有哪些新提交：

```powershell
git log --oneline HEAD..upstream/main
```

没有输出表示当前已是最新官方底座。

### 第 5 步：把自定义提交应用到官方新版

```powershell
git rebase upstream/main
```

出现 `Successfully rebased` 就表示源码更新成功，自定义功能也已重新应用。然后同步 Core 子模块和 Flutter 依赖：

```powershell
git submodule update --init --recursive
flutter pub get
```

不要因为 `flutter pub get` 提示很多包存在新版就运行批量升级；仓库已经锁定了兼容版本。

## 如果 rebase 出现冲突

先查看冲突文件：

```powershell
git status
```

打开标有 `both modified` 的文件，Git 会用以下标记显示两边内容：

```text
[当前分支内容开始]
一边的代码
[两边内容分隔]
另一边的代码
[另一分支内容结束]
```

编辑成最终需要的代码，并删除这些标记。解决一个或多个文件后执行：

```powershell
git add 路径一 路径二
git rebase --continue
```

如果又出现下一批冲突，重复“编辑、`git add`、`git rebase --continue`”，直到完成。

如果不确定如何处理，不要猜，也不要执行硬重置。可随时取消本次更新：

```powershell
git rebase --abort
```

取消后分支会回到第 5 步之前，保险分支仍然存在。

## 本地修改为什么不会丢

当前自定义功能不是散落的未提交文件，而是 Git 提交。`rebase` 会把这些提交逐个复制到官方新版后面，因此普通更新不会
丢失它们。提交哈希在 rebase 后会变化，这是正常的，因为提交的“父版本”已经从旧版官方代码换成了新版。

如果官方以后实现了相同的节点导入功能，可能产生大量冲突。此时应比较两种实现，保留更完整的一套，而不是把两份入口
机械地叠加。

## 本地化文案如何保留

真正需要人工维护的翻译源文件只有：

- `arb/intl_en.arb`
- `arb/intl_zh_CN.arb`
- `arb/intl_ja.arb`
- `arb/intl_ru.arb`

节点导入功能新增了以下键：

- `profileImportTip`
- `invalidProxyLink`
- `unsupportedProxyLink`

同时修改了：

- `urlDesc`
- `importFromURL`

如果 ARB 文件冲突，应以官方新版 ARB 为基础，把以上键和值保留下来，并确保四种语言都存在。不要只修改中文，否则其他
语言会回退成英文或直接显示键名。

以下路径是生成文件，不要手工逐行合并：

- `lib/l10n/l10n.dart`
- `lib/l10n/intl/`

解决四个 ARB 文件后运行生成器：

```powershell
dart run intl_utils:generate
git add arb lib/l10n
git rebase --continue
```

如果当前不在 rebase 冲突流程中，则不需要最后一条 `git rebase --continue`。

## 第 6 步：验证功能

先运行与自定义功能直接相关的测试：

```powershell
flutter test test\common\proxy_share_test.dart test\pages\scan_test.dart test\setup_test.dart
```

再运行静态分析：

```powershell
flutter analyze --no-fatal-infos
```

仓库目前可能显示 `prefer_const_constructors` 的既有 info；命令返回成功且没有 error 时不影响打包。

建议最后启动一次调试版，实际粘贴节点链接验证：

```powershell
flutter run -d windows
```

确认界面和节点正常后按 `q` 退出调试程序。

## 第 7 步：生成新版安装程序

```powershell
dart setup.dart windows --targets exe --env stable
```

完成时会显示 `Successfully packaged`。查看生成文件：

```powershell
Get-ChildItem .\dist\*-windows-amd64-setup.exe |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 1 FullName, Length, LastWriteTime
```

需要记录校验值时：

```powershell
$installer = Get-ChildItem .\dist\*-windows-amd64-setup.exe |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 1
Get-FileHash -LiteralPath $installer.FullName -Algorithm SHA256
```

本地生成的安装器没有代码签名，Windows 可能显示 SmartScreen 提示，这是本地构建的正常现象。

## 第 8 步：上传自定义源码到个人 Fork

rebase 会改变自定义提交哈希。如果该分支以前已经上传过，普通 `git push` 会被拒绝，应执行：

```powershell
git push --force-with-lease origin codex/proxy-link-import
```

`--force-with-lease` 会先确认远程分支仍是自己上次看到的状态，再安全替换历史；比 `--force` 更安全。不要对
`origin/main` 使用这个命令。个人 Fork 的 `main` 保持官方镜像，自定义内容只放在 `codex/proxy-link-import`。

## 可选：在个人 Fork 保存安装程序

可以打开 `https://github.com/reevebyte/FlClash/releases`，创建一个个人 Release，例如使用
`custom-v0.8.98-1` 这样的标签，并上传 `dist` 中的安装器。这用于备份和下载，不会自动改变应用内更新地址。

当前应用仍检查 `chen08209/FlClash` 的官方 Release。看到官方更新提示后，应按本手册合并、测试、重打包；直接安装
官方安装包会覆盖自定义程序文件。若以后确实需要应用内检查个人 Release，需要另外设计能被版本比较器识别的自定义版本号，
再把 `lib/common/constant.dart` 中的 `repository` 改为 `reevebyte/FlClash`，不能只改仓库地址。

## 安装升级与用户配置

自定义安装器沿用官方 AppId，会覆盖升级同一份 FlClash 程序。订阅、设置等用户数据通常位于安装目录之外，正常覆盖安装
会保留它们。源码改动是否保留由 Git 分支和提交负责，用户配置是否保留由应用数据目录负责，这是两件不同的事情。

## 最短命令清单

理解完整流程后，日常无冲突更新通常只需要：

```powershell
cd F:\project\CodexProject\FlClash
git switch codex/proxy-link-import
git status --short
git fetch upstream --tags
git rebase upstream/main
git submodule update --init --recursive
flutter pub get
flutter test test\common\proxy_share_test.dart test\pages\scan_test.dart test\setup_test.dart
flutter analyze --no-fatal-infos
dart setup.dart windows --targets exe --env stable
git push --force-with-lease origin codex/proxy-link-import
```
