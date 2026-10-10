# Auto Tab Groups

按工作目录和 Git 仓库自动整理项目导航。插件只列出当前窗口所选 Host 的 sessions 和 panes，侧栏层级为 **Session → Project → Pane**，不显示 Host 标题、类型或连接状态。侧栏不展示 tab 层级；只改变导航，不自动移动、重排或关闭 panes。

使用 **Window 半部**。会话、布局、Git 查询、设置和 chrome 都通过 Tern Window API 访问；没有 Host 入口，也不依赖其他插件。

## 安装

在工作区根目录执行：

```sh
tern plugin types plugins/auto-tab-groups
tern plugin link "$PWD/plugins/auto-tab-groups"
tern plugin list
```

Tern 加载后默认启用。必要时执行 `tern plugin reload`。已在 Tern **0.7.0（9ca00e4）** 的隔离原生 runtime 中验证。

## 分组规则

- 仅处理 `cx.hosts:current()` 对应的会话和 panes。不同 session 中的同名目录不会合并；分组键保留 Host ID，避免切换 Host 后折叠状态串用。
- 本地 pane 优先使用 Tern `cx.git:repo()` 返回的仓库 root；无法识别 Git 时按 cwd 分组。
- file、database、notebook 等原生块有文件路径时使用文件所在目录；Git 块使用仓库路径。没有目录信息的 pane 放入 `Unknown`。
- 远程 pane 使用远端报告的 cwd。Window Git API 只支持本机，因此不拿远端路径查询本机 Git，也不推测远端仓库 root。
- cwd 仅去掉尾部分隔符，不按路径前缀合并目录，也不自行解析非 Git 目录的符号链接。
- 每个 pane 直接列在所属项目下。一个 tab 的 panes 属于不同项目时，各 pane 分别显示在自己的项目下，不生成 tab 别名。
- 同名项目先用父目录名区分；仍有歧义时显示完整路径。
- 项目按名称排序，项目内的 panes 按 id 排列。切换焦点、重命名或调整原生 tab 顺序不会重排 pane 列表。
- Parked panes 显示在当前 Host 的 `Parked` 区域，与普通 Session 同级，没有聚焦按钮。请用 Tern 原生 hand 恢复；插件不会隐式 unpark 或改变布局。

Git 查询异步执行，同一 cwd 共用缓存，最多两个查询并行。cwd、打开/关闭、标题、焦点和命令事件驱动更新；每秒补查当前 Host/session 等没有专用事件的元数据。命令完成后刷新仓库信息，包括在父目录执行 `git init` 的情况；已有分组在刷新期间保留，避免来回跳动。首次识别前暂按 cwd 显示。其他程序在 Tern 外部改变仓库结构后，可执行 **Refresh Projects**。

## 交互

- 侧栏不单独显示项目目录路径。点击项目标题展开或折叠。
- 侧栏使用 pane 标题，没有标题时依次使用 program、kind 或 pane id。手动设置的 tab 名称仍由 Tern 原生 tab 功能管理。
- 当前 focused pane 的名称显示在整个窗口顶部中央，不以扣除侧栏后的内容区居中。标题取值与侧栏相同，但不追加 Busy、Exit 等状态标记；split 焦点变化、标题更新和项目折叠不会留下旧标题。顶部文本是侧栏名称的展示副本，不修改系统窗口标题或 tab 名称。
- 点击 pane 聚焦对应终端或原生块；点击 session 切换会话。
- Session 标题只显示名称，不标记 `Current`。多个 Session（包括 `Parked` 区域）之间用 1 px 中性灰（`#808080`）分割线分隔，首个 Session 上方不加分割线。
- 当前 pane 有高亮。pane 行显示 Busy、Alert、Error、Exit 和 Floating 状态。
- 侧栏不显示 tab/pane 数量。所有文本保持单行；超长名称用省略号截断。命令面板仍使用完整导航名称。
- 键盘操作使用原生命令面板：搜索 `Auto Tab Groups`、`Focus pane` 或项目名，用方向键和 Enter 选择。折叠项目中的 pane 仍可通过命令面板访问。
- 启用时接管 Tern 的 `previous_tab` / `next_tab`：原有快捷键按当前 Host 的侧栏顺序切换上一个／下一个 pane，跨 Project（workspace）、原生 tab 和 Session，首尾循环。折叠不影响切换，不进入 Parked，也不切换 Host；整个导航列表只有一个 pane 时保持当前焦点。
- 使用 [`tern.override`](https://docs.stencil.so/tern/guides/commands.md#overrides) 覆盖原生命令，不改用户快捷键配置。菜单和命令面板中的 Previous/Next tab 同样按侧栏顺序切换。插件停用或没有可用导航列表时回退原生行为；`next_tab_across_sessions` / `previous_tab_across_sessions`、数字选 tab、关闭确认和布局操作不受影响。

固定命令：

| 命令 | Action id | 默认快捷键 |
| --- | --- | --- |
| Toggle Sidebar | `plugin.auto-tab-groups.toggle` | `ctrl+alt+shift+t` |
| Refresh Projects | `plugin.auto-tab-groups.refresh` | 无 |

可在 Tern Keyboard 设置中绑定这两个固定命令。项目、pane 和 session 的导航命令随当前窗口状态生成，其 id 不作为持久快捷键接口。

启用开关和折叠标记存入插件 KV，reload 后保留。KV 在窗口之间共享；折叠标记按 host slot、session id 和项目路径定位，原生身份变化后的新分组默认展开。

## UI 边界和回退

Tern 0.7.0 没有独立 sidebar widget API。插件通过 `chrome.status` 和 CSS 将项目列表投影到原生竖向 tab 列表上方，保留左栏宽度约 236 px。原生 Files、Changes、Refs 在另一列，与项目列表并排；窗口窄时可用原生按钮收起 Files。

启用时需要设置 `tabs = Vertical`、`status_bar = true`、`tabs_autohide = false`。其他插件的 status segments 会移到项目列表底部，原生 cwd/Git/pane-size 状态仍留在底部状态栏。

项目列背景透明，沿用 Tern 窗口的 glass/透明外观，不再强制不透明底色。显示项目列表时隐藏底层原生 tabs 和过滤框，避免文字重叠；悬停和当前 pane 的主题高亮保留。插件不改变窗口本身的透明度设置。

顶部标题通过 `#tabbar .tb-tabs::after` 绘制，保留 40 px 顶部栏，不占用终端行数。竖向 tabs 下将原生顶部 tab 容器作为标题载体，隐藏其 tab 按钮；顶部文本背景透明，13 px、中等字重、单行省略，不接收点击。侧栏仍使用原有滚动容器。当前原生 runtime 会裁剪滚动容器外的固定定位 status 子节点，因此顶部标题不放入 status segments。

原生顶部栏横跨整个窗口，头像、Switch Session 和新建按钮靠窗口左侧排列，不再从 236 px 侧栏右侧开始。保留 Tern 原生窗口控制按钮的安全间距，右侧工具按钮不移动，pane 标题继续相对整个窗口居中。仅在插件启用时生效；停用后恢复原生布局。

左右各预留 480 px，覆盖实测长 session 名称与新增按钮的边界；标题宽度不超过 600 px。窗口宽度不超过 1000 px 时隐藏顶部副本，侧栏名称仍可见。Files 展开或收起不改变居中基准。标题内容写入独立 CSS sheet，反斜杠、引号和控制字符使用 CSS 十六进制转义；没有 focused pane 或关闭插件时显式设为 `content: none`。空 session 的原生顶部 tab 容器为空，`.tb-tabs:empty` 直接隐藏标题，避免依赖 Window 回调和元数据刷新时机。Tern 不支持 CSS `:has()`。

没有 focused pane 时，Tern 不渲染 status segments。CSS 的 `:empty` 隐藏投影，Window 事件和每秒元数据刷新恢复原生 tab 列表及过滤框；选回有 pane 的 session 后恢复项目列表。此回退不会创建占位 pane。插件启用期间，原生侧栏 Host 标题、类型和连接状态，以及顶部 Host 按钮始终隐藏；账号头像、Switch Session 和新建按钮保留。Window 入口在加载时按 KV 启用状态注册 CSS，不依赖 focused pane 或 WindowCx，因此空 session 中 reload 也不会恢复 Host 展示；停用后恢复原生 Host 控件。

Toggle Sidebar 关闭时移除 CSS，并恢复插件启用前保存的三项设置；已经被用户改动的值不会覆盖。手动切换横向 tabs、隐藏状态栏或开启 autohide 会使插件停用。卸载或 unlink 前先关闭插件，避免留下为侧栏启用的设置：

```sh
tern plugin unlink auto-tab-groups
```

CSS 依赖 Tern 的 `#statusline`、`#sidebar`、`#tabbar .tb-tabs`、`.sl-plugins`、`.sl-plugin`、`.tn-vt`、`.tn-vt-find`、`.tn-vt-host`、`.tn-host-tab` 和原生布局 class。原生 tab 列表仍保留在视图树中，项目投影在上层绘制并接收点击。Tern 升级后需重新生成定义，并检查侧栏、顶部标题及按钮避让、透明外观、空 session、Files 共存和设置恢复。

## 权限和外部命令

插件读取 pane/tab/session/host 元数据、本地 Git 元数据、自身 CSS 和 KV；写入自身 KV、上述 UI 设置，并响应用户点击执行原生 focus/session-switch。不会运行 shell 命令、扫描整个文件系统、访问网络、修改仓库或关闭进程。Git 识别使用 Tern 内建 Git 引擎，其系统 Git 依赖与原生 Git 功能一致。安装插件仍应视为信任代码操作。

## 开发验证

需要 Tern、`luau-lsp` 和 Luau CLI。原生侧栏回归另外需要 Bash 和 `jq`；Session 分割线像素回归还需要 Python 3（仅标准库）。除 Tern 外，这些工具都只用于开发，不是插件运行依赖。

```sh
tern plugin types plugins/auto-tab-groups
luau-lsp analyze \
  --platform=standard \
  --definitions=@tern=plugins/auto-tab-groups/tern.d.luau \
  plugins/auto-tab-groups/window.luau \
  plugins/auto-tab-groups/lib/*.luau \
  plugins/auto-tab-groups/tests/*.luau
luau plugins/auto-tab-groups/tests/grouping.luau
bash plugins/auto-tab-groups/tests/sidebar.sh
bash plugins/auto-tab-groups/tests/navigation.sh
bash plugins/auto-tab-groups/tests/session-separators.sh
bash plugins/auto-tab-groups/tests/title.sh
bash plugins/auto-tab-groups/tests/hosts.sh
```

分组回归覆盖仓库合并、非 Git 目录隔离、过期 root、同名项目、跨项目 tab 的 pane 归属、稳定的 pane 顺序、当前 Host 过滤、session 边界、Parked、原生文件路径和受保护的 API 数组。

`sidebar.sh` 在临时目录启动隔离的 Tern 原生 runtime，退出后清理进程和文件，不修改日常 Tern。它验证明暗主题下项目列背景透明且底层原生导航隐藏、点击命中项目列、空 session 恢复原生过滤框、返回后恢复透明项目列，以及关闭后恢复原设置和原生导航。也可传入插件目录验证另一份实现。

`hosts.sh` 使用隔离 runtime 和 loopback Host，验证有 pane、空 session 回退、返回及两种状态下 reload 均隐藏原生 Host 行和顶部 Host 按钮，同时保留空 session 的过滤框。停用及停用后空 session reload 必须恢复同一批 Host 控件，作为隐藏断言的正向对照。旧实现只移除了项目投影中的 Host 行；空 session 回退会恢复原生 Host 行，且 reload 时没有 WindowCx，无法重新注册 CSS。该回归在旧实现上失败，在修复后通过。

`session-separators.sh` 同样使用隔离 runtime，在明暗主题中创建两个 Session 并检查原生 PNG：首个标题上方没有横线，第二个标题上方确实绘制横线。像素检查不以标题高度或间距代替绘制结果。当前 Tern runtime 中 Session 边框使用独立的 `border-top-width`、`border-top-style` 和 `border-top-color`；`border-top` 简写未能绘制。

`bash plugins/auto-tab-groups/tests/title.sh` 需要 Tern、Bash、`jq` 和 Python 3（仅标准库）。它在隔离 runtime 中验证原生头像和 Session 区域靠左、system/lights/buttons 三种窗口控制模式的安全间距、头像点击命中区域、Session 按钮打开原生切换面板，以及停用后恢复顶部栏位置；比较原生 PNG 顶部像素，验证标题确实绘制且相对整个窗口居中、split 焦点切换和返回、折叠、Files、reload、含中文及引号的标题、窄窗口隐藏，以及关闭插件和空 session 清除标题。`native_png.py` 由标题和 session 分割线检查共用；不依赖第三方图像库。

`navigation.sh` 独立验证 `previous_tab` / `next_tab` 在分屏、跨项目、跨 tab 和跨 Session 中的双向导航、首尾循环、跳过 Parked、用户快捷键、reload 和停用回退。`sidebar.sh` 另外覆盖折叠项目的导航。两个脚本均使用隔离的原生 runtime，可传入插件目录验证另一份实现。

纯 pane 导航场景验证单 pane 不重复、多 pane 直接列在项目下、点击聚焦且不改变分屏、折叠时仍能通过命令访问 pane，以及关闭 split 后只移除对应行。

原生运行验收：嵌套目录合并到 Git root；`cd` 后自动迁组；父目录 `git init` 后子目录缓存更新；pane 点击及命令面板 Enter 聚焦；当前 Host 的 session 导航、远程 cwd 分组且没有 Host 标题；Files/Changes/Refs 共存；列表滚动、窄窗口、其他插件状态段；空 session 露出原生导航，返回后恢复项目列表；关闭后的设置恢复；reload 后折叠和导航正常。检查 toast 中没有 handler 失败。
