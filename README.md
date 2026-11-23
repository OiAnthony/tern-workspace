# Tern Plugins

给 [Tern](https://stencil.so/tern) 加上窗口标题、自定义快捷动作和 Git 仓库跳转。每个插件都能单独安装，不需要装齐，也不依赖其他插件。

## 选择插件

| 插件 | 用来做什么 | 安装后从哪里开始 |
| --- | --- | --- |
| [Pane Title](plugins/pane-title/README.md) | 在窗口顶部居中显示当前 tab 的原生图标和标题 | 使用 Tern 的 **Vertical tabs** 时默认显示 |
| [Shortcut Manager](plugins/shortcut-manager/README.md) | 为自定义命令配置快捷键，选择后台、分屏、新标签页或浮动终端 | 在命令面板运行 **Shortcut Manager: 管理快捷动作** |
| [Git Open](plugins/git-open/README.md) | 打开当前 Git 仓库的远程页面 | 在仓库终端中先按 `Ctrl+B`，松开后按 `G` |
| [Auto Session](plugins/auto-session/README.md) | 按 main pane 目录名自动命名 Session，手动改名后锁定 | 打开或切换 Session 目录后自动生效 |

## 安装

先安装 Tern，并确认终端可以运行 `tern`。普通使用不需要 Luau、`luau-lsp` 或生成类型定义。

可以直接执行仓库提供的一键安装脚本。脚本会临时 clone 仓库，并安装所有包含 `plugin.toml` 的插件：

```sh
curl -fsSL https://raw.githubusercontent.com/OiAnthony/tern-workspace/main/install.sh | sh
```

需要替换已安装副本时追加 `--force`：

```sh
curl -fsSL https://raw.githubusercontent.com/OiAnthony/tern-workspace/main/install.sh | sh -s -- --force
```

仓库移除插件或更换插件 ID 后，追加 `--prune` 清理当前 Tern 插件目录中不再属于仓库的插件：

```sh
curl -fsSL https://raw.githubusercontent.com/OiAnthony/tern-workspace/main/install.sh | sh -s -- --force --prune
```

`--prune` 只会删除本脚本此前成功安装并登记、但后来不在仓库清单中的插件。它会在 Tern 配置目录旁保存 `.tern-workspace-managed` 清单，因此同一配置中的其他来源插件会保留。首次启用此功能时，脚本无法判断历史上由谁安装了已有插件，旧残留需要手动执行 `tern plugin remove <id>` 一次。

脚本默认安装 `main` 分支，也可以固定到某个分支或 tag：

```sh
curl -fsSL https://raw.githubusercontent.com/OiAnthony/tern-workspace/main/install.sh | sh -s -- --ref v1.0.0
```

一键脚本会执行从仓库下载的安装代码。对代码来源有审核要求时，先下载并查看脚本，再执行：

```sh
curl -fsSLO https://raw.githubusercontent.com/OiAnthony/tern-workspace/main/install.sh
less install.sh
sh install.sh
```

也可以下载本仓库后执行本地批量安装脚本：

```sh
git clone https://github.com/OiAnthony/tern-workspace.git
cd tern-workspace
./install-all.sh
```

更新本地 checkout 中的所有插件：

```sh
git pull --ff-only
./install-all.sh --force
```

也可以按需执行单个插件的安装命令，每行安装一个插件：

```sh
tern plugin install ./plugins/pane-title
tern plugin install ./plugins/shortcut-manager
tern plugin install ./plugins/auto-session
```

Tern 的 `install` 接收一个插件包目录。仓库根目录不是插件包，因此直接安装仓库 URL 会因为缺少根目录 `plugin.toml` 而失败。
安装会将插件复制到 Tern 的插件目录。执行后检查加载状态：

```sh
tern plugin list
```

插件拥有文件和进程访问能力，只安装你信任的代码。各插件的权限和外部依赖见对应 README。

## 使用

### 在顶部显示当前标题

Pane Title 在 **Vertical tabs** 模式下显示当前 tab 的图标和原生标题。

在命令面板运行 **Pane Title: Toggle** 可开关显示。横向 tabs 或窗口宽度不超过 1000 px 时不显示顶部标题。

### 添加自己的快捷动作

1. 从要运行命令的终端打开命令面板，选择 **Shortcut Manager: 管理快捷动作**。
2. 选择已有预设，或点击 **新建**，填写名称和快捷键。比如 `ctrl+b>c` 表示先按 `Ctrl+B`，松开后按 `C`。
3. 填写 `code .` 等命令；要用管道、变量或重定向时，将 **命令解释** 改为 **通过 Shell**。
4. 在 **高级参数** 中选择运行位置、工作目录，以及终端的焦点和复用方式。
5. 检查执行预览，按需 **试运行**，再点击 **保存**。试运行会真实执行草稿，但不会保存配置。

初次加载提供 VS Code、Zed、IDEA、Lazygit 和 Lazydocker 预设，所需程序及其 CLI 要自行安装。快捷键可以留空，动作仍可从命令面板运行。

当前仅支持 macOS / Linux 本机 Host，以及 `sh`、`bash`、`zsh`、`dash`、`ksh`。不支持 fish、Windows 或远程执行。完整的执行模式、快捷键冲突处理和路径配置见 [Shortcut Manager 使用说明](plugins/shortcut-manager/README.md)。

### 打开当前仓库页面

在 Git 仓库内运行 **Git Open: Open in GitHub**，或先按 `Ctrl+B`，松开后按 `G`。虽然命令名包含 GitHub，它也支持 GitLab 和其他可转换为 HTTPS 地址的 remote。

默认在 Tern 内置浏览器打开 `origin` 对应的页面。运行 **Git Open: Toggle Browser** 可切换到系统默认浏览器，选择会在重启后保留。

需要 Tern 环境能找到 `git`，且当前聚焦 pane 位于 Git 工作区。没有 `origin` 时会提示 `No Git remote named origin`。默认快捷键被 Tern 原有键位占用时不会覆盖，可在 Keyboard 设置中为 `plugin.git-open.open` 另设快捷键。

## 更新

在本仓库目录拉取最新代码，再重新安装需要更新的插件：

```sh
git pull
tern plugin install ./plugins/git-open --force
tern plugin install ./plugins/auto-session --force
```

将 `git-open` 换成目标插件的目录名，多个插件需要分别更新。`--force` 替换已安装的副本，不用于覆盖 link 的插件。

如果希望直接加载本地源码，而不是安装副本，可改用 `tern plugin link "$PWD/plugins/git-open"`。link 模式下 Tern 直接使用该目录；修改后通常自动重载，必要时运行 `tern plugin reload`。不要同时为同一个插件保留安装副本和 link。

## 卸载

卸载前先恢复插件管理的设置：

- **Shortcut Manager**：在管理面板停用或删除动作并保存，恢复插件持有的快捷键设置；直接卸载不会自动清理已写入的用户键位

然后按插件 ID 移除，例如：

```sh
tern plugin remove git-open
```

如果使用的是 link 模式，改用：

```sh
tern plugin unlink git-open
```

卸载 Shortcut Manager 不会主动关闭已启动的终端或程序。

## 遇到问题

- **没有出现插件或命令**：运行 `tern plugin list` 查看加载问题，必要时执行 `tern plugin reload`，并检查 Tern 的错误提示
- **快捷动作找不到程序**：先确认 CLI 已安装；后台模式的裸程序名通过 POSIX 登录 Shell 查找，仅在 `.zshrc` 中配置的 `PATH` 不一定可用，可改填可执行文件的绝对路径
- **顶部标题没有出现**：确认已启用 Pane Title、使用 Vertical tabs，且窗口宽度超过 1000 px
- **升级 Tern 后顶部标题异常**：Pane Title 依赖 Tern 的内部 UI 结构，升级后可能需要适配；可先关闭插件，恢复原生界面

## 开发插件

开发和目录约定见 [工作区说明](docs/workspace-structure.md)，官方文档与 SDK 入口见 [参考资料](references/README.md)。新插件可从 [`templates/basic/`](templates/basic/) 开始；各插件 README 保留了静态检查和运行验证命令。
