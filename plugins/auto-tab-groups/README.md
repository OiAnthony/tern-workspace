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
- 窗口顶部居中标题已拆分到独立的 [Pane Title](../pane-title/README.md) 插件。需要该功能时单独安装；它不依赖本插件，关闭侧栏也不会关闭顶部标题。
- 点击 pane 聚焦对应终端或原生块；点击 session 切换会话。
- Session 标题只显示名称，不标记 `Current`。多个 Session（包括 `Parked` 区域）之间用 1 px 中性灰（`#808080`）分割线分隔，首个 Session 上方不加分割线。
- pane 行保留 30 px 最小行高、13.5 px 字号、主题选中背景和独立状态指示。项目和 pane 共用名称列，换行后的名称仍对齐；项目折叠箭头和 pane 状态灯独立浮动在左侧标记栏，不占文本宽度。所有 pane 均不显示类型图标。普通 pane 右侧仅保留 7 px padding，只有 Floating 行为 `↗` 预留 24 px。名称不再追加 Busy、Alert、Error、Exit、Floating 文字；每行只表示该 pane，不汇总同一 tab 的其他 panes。状态变化不改变名称位置。
- 侧栏不显示 tab/pane 数量。Session、项目和 pane（含 Parked）名称默认允许换行，最多显示两行，超过两行在末尾显示省略号；连续长英文名称也能换行。按实际排版行数限制可见内容，不按固定字符数截断。hover 不再展开文本或改变行高，侧栏宽度不变；命令面板仍使用完整导航名称。
- 左侧状态灯只表示工作或未读提示：Busy 使用原生中性色 `--t3`，复用 Tern 的 `tnStLive 2.4s steps(12) infinite` 呼吸动画，透明度在 0.55 → 1 → 0.55 间变化；未读 `PaneInfo.alert` 使用 accent 且不呼吸，未读优先于 Busy。Tern 在 pane 被看见时清除 alert，插件随之熄灯；没有 Busy 或未读时不画默认灰点、等待输入绿灯或退出圆环。`at_prompt`、`error`、`exited` 不用于制造未读状态。右侧 `↗` 表示 Floating，不另画 Alert 感叹号。Parked 保留灰色名称且不可点击。
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

pane 呈现使用内部 tone 标记和 CSS 伪元素，不搬运原生 `.tn-dk` 节点，也不设置 `StatusSegment.icon`。Tern 没有公开原生 Tab 行组件，Window PaneInfo 只提供 alert 布尔值，没有原生 Mark 的 working/waiting/bell/failed/done 分类；插件不猜测完成、失败或等待通知的颜色，统一以 accent 表示未读。因此原生 done 的 `--ok` 和 failed 的 `--bad` 仍无法完整对齐，需 Tern 暴露未读 Mark 分类。工作灯复用当前版本原生 keyframes，升级 Tern 后应运行像素回归检查；这里不承诺复合状态逐像素一致。pane 行不复制 tab 编号、数字快捷键提示、split 数量或关闭按钮。

项目列背景透明，沿用 Tern 窗口的 glass/透明外观，不再强制不透明底色。显示项目列表时隐藏底层原生 tabs 和过滤框，避免文字重叠；悬停和当前 pane 的主题高亮保留。插件不改变窗口本身的透明度设置。


没有 focused pane 时，Tern 不渲染 status segments。CSS 的 `:empty` 隐藏投影，Window 事件和每秒元数据刷新恢复原生 tab 列表及过滤框；选回有 pane 的 session 后恢复项目列表。此回退不会创建占位 pane。插件启用期间，原生侧栏 Host 标题、类型和连接状态，以及顶部 Host 按钮始终隐藏；账号头像、Switch Session 和新建按钮保留。Window 入口在加载时按 KV 启用状态注册 CSS，不依赖 focused pane 或 WindowCx，因此空 session 中 reload 也不会恢复 Host 展示；停用后恢复原生 Host 控件。

Toggle Sidebar 关闭时移除 CSS，并恢复插件启用前保存的三项设置；已经被用户改动的值不会覆盖。手动切换横向 tabs、隐藏状态栏或开启 autohide 会使插件停用。卸载或 unlink 前先关闭插件，避免留下为侧栏启用的设置：

```sh
tern plugin unlink auto-tab-groups
```

CSS 依赖 Tern 的 `#statusline`、`#sidebar`、`.sl-plugins`、`.sl-plugin`、`.tn-vt`、`.tn-vt-find`、`.tn-vt-host`、`.tn-host-tab` 和原生布局 class。原生 tab 列表仍保留在视图树中，项目投影在上层绘制并接收点击。Tern 升级后需重新生成定义，并检查侧栏、透明外观、空 session、Files 共存和设置恢复。

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
bash plugins/pane-title/tests/title.sh plugins/pane-title plugins/auto-tab-groups
bash plugins/auto-tab-groups/tests/hosts.sh
bash plugins/auto-tab-groups/tests/pane-appearance.sh
```

分组回归覆盖仓库合并、非 Git 目录隔离、过期 root、同名项目、跨项目 tab 的 pane 归属、稳定的 pane 顺序、当前 Host 过滤、session 边界、Parked、原生文件路径和受保护的 API 数组。

同一 runner 还覆盖 pane 侧栏的独立 Busy/未读状态、已读后即使 at_prompt 仍为 true 也不留下灯、启动错误及退出元数据不伪造未读、Alert 与焦点/Floating 并存、Parked 不可点击、非终端块导航，以及标题回退。

`sidebar.sh` 在临时目录启动隔离的 Tern 原生 runtime，退出后清理进程和文件，不修改日常 Tern。它验证明暗主题下项目列背景透明且底层原生导航隐藏、点击命中项目列、空 session 恢复原生过滤框、返回后恢复透明项目列，以及关闭后恢复原设置和原生导航。也可传入插件目录验证另一份实现。

`pane-appearance.sh` 使用隔离 runtime，以 OSC title/133 驱动长标题和重复 Busy/熄灯转换；明暗主题下用 `layout_pixels.py` 比较 PNG 中项目名称、pane 名称和两行标题的实际绘制起点，验证共用名称列。持续 Busy 期间跨过一个完整呼吸周期采样 PNG，要求至少三个绘制等级、灯始终可见、文字不变，避免把静态圆点或二态闪烁误判为呼吸。另在真实 shell 中记录 finished 通知，切走形成未读，再通过插件导航看见消息，同步检查原生 done 标记和插件 alert 均清除，并检查 PNG 中未读灯确实亮过、已读后该区域没有残留像素。它还验证终端没有额外 SVG 图标、名称位置稳定、reload 和停用后原生导航恢复。feed 会将程序替换为 stand-in，因此通知路径使用独立的真实 shell，不把 OSC prompt 当成消息已读。像素检查由 `pane_pixels.py` 和 `layout_pixels.py` 调用现有 `native_png.py`，只用 Python 标准库。可传入插件目录检查另一份实现。

`hosts.sh` 使用隔离 runtime 和 loopback Host，验证有 pane、空 session 回退、返回及两种状态下 reload 均隐藏原生 Host 行和顶部 Host 按钮，同时保留空 session 的过滤框。停用及停用后空 session reload 必须恢复同一批 Host 控件，作为隐藏断言的正向对照。旧实现只移除了项目投影中的 Host 行；空 session 回退会恢复原生 Host 行，且 reload 时没有 WindowCx，无法重新注册 CSS。该回归在旧实现上失败，在修复后通过。

`session-separators.sh` 同样使用隔离 runtime，在明暗主题中创建两个 Session 并检查原生 PNG：首个标题上方没有横线，第二个标题上方确实绘制横线。像素检查不以标题高度或间距代替绘制结果。当前 Tern runtime 中 Session 边框使用独立的 `border-top-width`、`border-top-style` 和 `border-top-color`；`border-top` 简写未能绘制。

顶部标题回归已迁移到 `plugins/pane-title/tests/`。上面的双插件命令检查项目折叠不改变顶部标题，关闭本插件后标题仍正常显示；标题插件可以单独运行同一脚本，不依赖侧栏。

`navigation.sh` 独立验证 `previous_tab` / `next_tab` 在分屏、跨项目、跨 tab 和跨 Session 中的双向导航、首尾循环、跳过 Parked、用户快捷键、reload 和停用回退。`sidebar.sh` 另外覆盖折叠项目的导航。两个脚本均使用隔离的原生 runtime，可传入插件目录验证另一份实现。

纯 pane 导航场景验证单 pane 不重复、多 pane 直接列在项目下、点击聚焦且不改变分屏、折叠时仍能通过命令访问 pane，以及关闭 split 后只移除对应行。

原生运行验收：嵌套目录合并到 Git root；`cd` 后自动迁组；父目录 `git init` 后子目录缓存更新；pane 点击及命令面板 Enter 聚焦；当前 Host 的 session 导航、远程 cwd 分组且没有 Host 标题；Files/Changes/Refs 共存；列表滚动、窄窗口、其他插件状态段；空 session 露出原生导航，返回后恢复项目列表；关闭后的设置恢复；reload 后折叠和导航正常。检查 toast 中没有 handler 失败。
