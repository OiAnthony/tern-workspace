# Shortcut Manager

在 Tern 原生面板中管理自定义快捷动作。支持外部程序、Shell 命令和原生 Tern 动作，无需 Web 服务或额外 UI runtime。

## 安装与打开

```sh
tern plugin link "$PWD/plugins/shortcut-manager"
tern plugin list
```

在 Tern 命令面板选择 **Shortcut Manager: 管理快捷动作**。管理面板会在当前 pane 旁打开。再次从其他 pane 调用该命令，会更新面板的试运行目标；面板标题显示目标目录。

初次加载提供以下可编辑预设。`>` 表示先按前一组键，松开后再按下一组键，不是同时按三键。

| 默认快捷键 | 动作 | 执行方式 |
| --- | --- | --- |
| `ctrl+b>c` | `code .` | 后台进程 |
| `ctrl+b>z` | `zed .` | 后台进程 |
| `ctrl+b>i` | `idea .` | 后台进程 |
| `ctrl+b>l` | `lazygit` | 新标签页，聚焦并复用 |
| `ctrl+b>d` | `lazydocker` | 右下角 PiP，聚焦并复用 |

程序必须已安装。后台模式中的裸程序名（如 `code`）通过用户配置的 POSIX 登录 Shell 查找，因此可使用登录配置中的 `PATH`，不依赖 macOS GUI 进程的精简 `PATH`。含路径的程序直接执行；也可填写可执行文件的绝对路径。仅在交互式 Shell 配置（如 `.zshrc`）中设置的 `PATH` 不一定可用；应放入登录配置，或使用绝对路径。IDE 的 CLI 和 Lazydocker 的 Docker 连接需要由用户自行配置。插件不安装程序、不启动 Docker、不需要 API token。

## 管理动作

1. 在左侧侧边栏搜索并选择已有动作，或点击 **新建**。列表始终可见；初始页也提供 VS Code、Zed、IDEA、Lazygit 和 Lazydocker 预设。
2. 快捷键配置采用单行布局：左侧显示键位，右侧提供 **录制按键** 和 **清除绑定**。连续按键显示为可视化序列；按 Enter 完成，按 Esc 取消。快捷键可留空，动作仍可从命令面板运行。
3. 填写名称与 **运行命令**，如 `code .` 或 `git status --short`。
4. **高级参数默认展开**，也可手动收起。执行方式、运行位置、启用状态、工作目录、焦点与复用、分屏方向、浮窗位置、手动键位及执行预览都在此区域；试运行和删除也在这里。
5. 点击编辑器右上角 **保存**，或按 `ctrl+alt+shift+s`。保存会立即应用配置。**取消** 将已有动作恢复为已保存内容，或放弃未保存的新动作。

面板保持左侧列表、右侧编辑器的两栏布局。编辑器顶部固定显示 **取消** 和 **保存** 主按钮，仅正文滚动；滚动高级参数时，操作按钮仍留在右上角。输入框和按钮采用统一圆角、边框及焦点反馈，参考 [shadcn/ui Input](https://ui.shadcn.com/docs/components/input) 的组件设计，仍使用 Tern 原生 UI，不依赖 React。内部 ID 自动生成；已保存配置的 ID 保持不变。试运行会真实执行当前草稿，但不会保存。

程序命令支持空格分隔参数、单引号、双引号和反斜杠转义。`code "my project"` 会传入一个带空格的参数，`printf '%s' ''` 会保留空参数。不展开 `$变量`、通配符或命令替换；管道和重定向需要明确选择 **Shell 命令**。引号未闭合或输入了不支持的 Shell 语法时，错误显示在命令旁，保存与试运行都会拒绝该草稿，不会执行之前的有效命令。

按键录制只能收到未被操作系统或 Tern 原生 keymap 拦截的按键。保留键可在高级参数手填，例如 `ctrl+b>g`。Tab / Shift+Tab 在当前可见控件间移动，并将目标滚入视野；选项用方向键切换，按钮用 Enter 或 Space 激活。键盘也可使用命令面板中的 **试运行当前草稿**、**选择 Tern 动作**、**查看有效快捷键**。

删除需要再次确认并保存，不会终止已启动程序。编辑后切换其他动作或新建动作时，面板先显示未保存警告。**继续编辑** 或 Esc 保留草稿；**丢弃并继续** 才放弃修改并进入目标动作。点击当前已选动作不会丢弃草稿。要保留修改，请继续编辑后保存，再切换。

## 执行模式

| 模式 | 行为 | 适合 |
| --- | --- | --- |
| 后台进程 | 不创建 terminal；完成或失败时显示 toast | 打开编辑器、短命令 |
| 分屏终端 | 在来源 pane 的左/右/上/下新建 PTY | CLI、交互式工具 |
| 新标签页 | 新建带 PTY 的 tab | Lazygit、长期运行工具 |
| 浮动终端 | 创建 PTY 并置为来源 pane 上的 PiP，可选四角 | Lazydocker、监控工具 |

终端模式可以选择启动后聚焦，以及复用已有实例。后台模式不提供 pane 复用或终端输入。

工作目录可使用触发快捷键时的来源 pane 目录，或固定绝对路径。目录不存在、来源 pane 已关闭、远程 host 或不支持的 Shell 都会报错，不退回其他目录执行。面板试运行使用打开管理面板时捕获的来源 pane；可从其他 pane 再次打开管理命令来更换目标。

**复用范围是动作 ID + 本机 host + 工作目录**。插件只复用自己记录的、仍存活的 terminal/agent pane，并检查程序和目录未变化。复用时仅聚焦，不重新输入或执行命令。程序退出、pane 关闭或目录变化后会创建新实例。修改动作命令或布局不会改造已有实例；需要立即使用新命令时关闭旧实例或暂时关闭复用。不同动作不会共享实例。

## 快捷键与保存

每个动作注册为原生 `plugin.shortcut-manager.<id>` command；管理入口是 `plugin.shortcut-manager.manage`。快捷键由 Tern 原生 keymap 处理，不使用键盘监听或第二套 chord 状态机。

保存会检查本插件动作之间的重复和序列前缀冲突。与其他原生快捷键冲突时，面板列出冲突项，用户必须明确同意替换；不会静默覆盖。移除或停用绑定时，仅恢复仍由本插件持有的 override，保留用户后来改过的键位。

动作配置存入插件 KV；Host 是唯一提交方，并检查配置 revision，拒绝陈旧面板覆盖其他面板的修改。Window 应用原生 keybind 设置，Host 拒绝提交时回滚仍属于该次事务的设置。保存成功会调用 Tern 原生 `reload_plugins`，使新增、删除和名称变化生效；该命令也会 reload 其他插件。后台完成通知和长期任务不是跨 reload 的持久任务系统。

## 权限、边界与卸载

- Host 负责原生 block、草稿与配置提交；Window 负责原生快捷键、设置、进程和布局。两个入口不跨 VM 调用专属 API。
- 插件拥有本机文件读写和进程执行权限。Shell 命令按用户权限执行，只使用可信配置。程序自身可以修改项目、访问网络或读取凭据。
- 当前支持 macOS / Linux 本机 host。终端命令使用 POSIX 引号；配置的 Shell 必须为 `sh`、`bash`、`zsh`、`dash` 或 `ksh`。不支持 fish、Windows 或远程执行。
- PiP 是 Tern 内部浮窗，不是操作系统级置顶窗口。它不能保证跨 tab、跨应用始终显示。
- 后台执行不是服务管理器：没有 PID 管理、日志历史、重试、开机启动或退出 Tern 后继续运行的保证。
- 卸载前在面板停用或删除动作并保存，以恢复插件持有的用户快捷键 override。直接移除插件不会自动删除它曾写入的用户 keybind 设置；可在 Tern 键位设置中手动清理 `plugin.shortcut-manager.*`。卸载不会主动关闭终端实例。

## 开发与验证

基于 Tern **0.6.2**，使用官方命令生成 `tern.d.luau`：

```sh
tern plugin types "$PWD/plugins/shortcut-manager"
luau-lsp analyze --platform=standard \
  --definitions=@opaque="$PWD/plugins/shortcut-manager/analysis.d.luau" \
  --definitions=@tern="$PWD/plugins/shortcut-manager/tern.d.luau" \
  plugins/shortcut-manager/host.luau \
  plugins/shortcut-manager/window.luau \
  plugins/shortcut-manager/lib/*.luau
```

Tern 0.6.2 生成的 `ExportCall.wait` 使用未声明的 `userdata`。`analysis.d.luau` 仅为静态分析补充 `typeof(newproxy())` 表示的真实 opaque 类型，不修改生成文件，也不伪造运行时 API。

已用 luau-lsp 1.70.1 和隔离 `tern serve` / `tern ctl` 验证：原生管理面板、中文及 emoji 编辑、创建/删除动作、保存后立即执行新参数、原生 chord 触发、重复及前缀冲突、重复 ID 拒绝、后台文件输出、缺失程序报错、分屏/标签页/PiP 的真实 PTY 输出、PiP 焦点、实例复用、实际 Lazygit 界面及退出后重新启动、Tern `new_tab` 动作和插件 reload。检查了 1280 与 720 像素窗口中的原生布局。

UI/UX 重构验证：在隔离 `tern serve` / `tern ctl` 中操作了统一命令输入、20 组解析与格式化边界、包含中文/空参数/引号/反斜杠的真实进程参数、Shell 执行、按键序列录制、保存与 reload、Tern 动作搜索/选择/试运行、原生 chord 触发、冲突确认和键盘滚动定位。检查了 1280、720 和 420 像素窗口中的布局及浅色、深色主题。未修改用户现有 Tern 配置或链接状态。

两栏表单调整验证：luau-lsp 1.70.1 静态分析通过；在隔离原生 runtime 中验证了编辑后切换/新建警告、继续编辑与 Esc 保留草稿、确认丢弃后切换、取消还原、保存及 reload、高级参数展开，以及 1280、720、420 像素下保持两栏布局。已同步到本机安装目录，真实 Tern 窗口显示常驻动作列表和“保存 / 取消”表单操作区。保存测试仅修改隔离环境配置。

紧凑编辑器验证：快捷键配置为左右排列的单行；高级参数在选择或新建动作时默认展开。验证了右上角保存、取消、按键录制、未保存切换警告和保存 reload；正文滚动前后，顶部操作栏的实际位置保持不变。输入框具有统一 6px 圆角和 36px 最小高度。

后台 CLI 路径修复验证：使用与真实 macOS GUI 相同的系统 `PATH`，修复前通过 `ctrl+b>c` 复现 `tern.process.run code: No such file or directory`；修复后同一原生 chord 启动 VS Code，`code --status` 显示 `tern-workspace` 窗口。隔离 runtime 验证了来源目录、空参数、空格、引号、中文、Shell 表达式按字面量传递、绝对路径直接执行，以及缺失程序的失败 toast。运行了 `tern plugin types`；本次环境没有 `luau-lsp` 可执行文件，未运行静态分析。

Lazydocker 的 Docker 连接及 Zed / IDEA 应用打开尚未实际操作；VS Code 已在上述后台 CLI 路径修复中验证。其余工具仍需在用户环境确认 CLI 和服务可用。没有修改用户现有 Tern 配置或链接状态。
