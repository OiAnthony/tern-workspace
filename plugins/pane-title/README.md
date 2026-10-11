# Pane Title

在整个 Tern 窗口顶部居中显示当前原生 tab 的图标与标题。由 `auto-tab-groups` 拆出，使用 **Window 半部**，可独立安装，不读取或加载其他插件的模块。

## 安装

在工作区根目录执行：

```sh
tern plugin types plugins/pane-title
tern plugin link "$PWD/plugins/pane-title"
tern plugin list
```

默认启用。必要时执行 `tern plugin reload`。使用 Tern 原生 **Vertical tabs** 设置；插件不修改 tabs、status bar 或 autohide 设置。横向 tabs 保留原生顶部 tab 按钮，不显示标题副本。

## 行为

- 直接显示现有 `.tb-tabs > .tt.on` 的原生 `.tn-dk` 图标和 `.nm` 标题。默认终端图标、Vim 等应用图标、自定义标题图标、Busy／未读装饰和分屏图标组合均由 Tern 绘制，不复制图标资源，不手绘底板，不解析标题字符。
- 使用原生 **tab 标题语义**：手动命名优先；没有手动命名时跟随该 tab 的 focused pane。分屏图标组合表示整个 tab，不是只表示当前 pane。不修改 tab 名称或系统窗口标题。
- 标题和状态跟随 Tern 自身的原生重绘更新，不注册标题事件，不轮询元数据，也不需要 Refresh 命令。
- 图标与标题作为一个整体相对整个窗口居中。Files 展开、项目侧栏折叠或停用不改变居中基准。
- 保留 40 px 顶部栏、原生图标尺寸与材质；标题文字为 13.5 px，单行省略。左右各预留 480 px，组合最大宽度 600 px；图标不收缩，窗口宽度不超过 1000 px 时隐藏整个组合。
- 只显示当前原生 tab，隐藏其背景、简化图标 `.fc`、tab 编号、快捷键提示、关闭按钮和目录副标题；保留完整的原生 dock 图标树。顶部标题不接收鼠标点击，原生侧栏导航和窗口控制按钮不变。
- Vertical tabs 下让原生顶部栏横跨窗口，头像、Switch Session 和新建按钮靠左，保留原生窗口控制按钮安全间距及右侧工具按钮。横向 tabs 使用 Tern 的原生布局。
- 空 session 中 `.tb-tabs:empty` 隐藏标题，不依赖 WindowCx、事件或计时器；空 session reload 也不会保留旧标题。
- 执行 **Pane Title: Toggle**（`plugin.pane-title.toggle`）停用或启用。没有默认快捷键，可在 Tern Keyboard 设置中绑定。开关存入插件 KV；停用移除布局 CSS，恢复原生顶部栏，不留下 UI 设置改动。

CSS 依赖 Tern 内部的 `.tabs-v`、`#tabbar`、`.tb-tabs`、`.tt.on`、`.tn-dk`、`.tx`、`.nm`、`.fc`、`.tn-num`、`.mk`、`.tn-tc` 和 `.sub`。原生 CSS 的 sidebar offset 由有针对性的 `left: 0 !important` 覆盖；停用时整张布局 sheet 被移除。这是对原生节点的布局复用，不是稳定的公开组件接口；Tern 升级后需重新生成定义并运行回归。

## 权限和外部命令

只读取自身 CSS 和 KV，写入自身 KV 和 CSS。没有 Host 入口，不读取 pane 元数据，不运行外部命令，不读取 Git、不访问网络、不更改用户 UI 设置、不移动或关闭 pane。默认图标、应用图标、字体回退和状态装饰沿用 Tern 原生功能。安装插件仍应视为信任代码操作。

## 开发验证

```sh
tern plugin types plugins/pane-title
luau-lsp analyze \
  --platform=standard \
  --definitions=@tern=plugins/pane-title/tern.d.luau \
  plugins/pane-title/window.luau
bash plugins/pane-title/tests/title.sh
bash plugins/pane-title/tests/title.sh plugins/pane-title plugins/auto-tab-groups
```

原生回归需要 Tern、Bash、jq、Python 3（仅标准库）和 `vi`。脚本启动隔离的 `tern serve` runtime，实际打开临时文件验证 Vim 的绿色应用图标；这些工具只用于开发，插件自身不启动外部程序，也不修改日常 Tern。

回归比较真实 PNG 的顶部像素，验证默认图标、应用图标、自定义标题图标、整组居中、明暗主题、分屏组合和焦点切换、原生 tab 命名优先级、Files、reload、中文/引号/反斜杠、长标题裁剪、窄窗口、停用恢复、空 session，以及 system/lights/buttons 三种窗口控制模式的安全间距和原生 Session 点击。双插件模式另验证项目折叠和侧栏停用不影响顶部标题。

标题和焦点场景只等待原生文字更新，不调用插件 Refresh、不触发插件计时器。旧手绘实现无法显示原生默认图标，同一 runner 在旧实现上失败，在原生节点实现上通过。像素解码由插件本地 `native_png.py` 完成，不依赖其他插件或第三方图像库。
