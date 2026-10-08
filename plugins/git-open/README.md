# Git Open

在当前 Git 仓库的远程代码托管页面中打开仓库。支持 GitHub、GitLab 以及其他可转换为 HTTPS 地址的 Git remote。

## 行为

- 在 Tern Commands 中提供 `Git Open: Open in GitHub`。
- 仅当当前聚焦 pane 位于 Git 仓库内时显示。
- 仓库检测使用 Tern 的异步 `cx.git:repo`；聚焦 pane、关闭 pane、工作目录变化或 shell 命令结束后刷新。检测完成前暂不显示命令，`available` 只读取缓存，不遍历文件系统。
- 读取 `origin` remote，并将 HTTPS、SSH、scp-like remote 地址转换为 Web URL。
- 缺少 `origin` 时仅提示 `No Git remote named origin`，不禁用命令；添加 remote 后可以直接再次使用。
- 默认使用 Tern 内置浏览器，通过 `cx:open` 新增浏览器 pane。插件调用会跳过 link/open 路由。
- 在 Tern Commands 中运行 `Git Open: Toggle Browser`，可在内置浏览器和系统默认浏览器之间切换。Toast 会显示切换后的模式。
- 选择保存在插件的 `tern.kv` 中，所有窗口共享，插件重载或 Tern 重启后保留；切换命令不要求当前 pane 位于 Git 仓库内。
- 系统默认浏览器通过系统 URL opener 打开：macOS 使用 `open`，Linux 使用 `xdg-open`，Windows 使用 `explorer.exe`。启动失败时显示错误，不自动退回内置浏览器。

## 安装与开发

```sh
tern plugin link "$PWD/plugins/git-open"
tern plugin list
tern plugin reload
```

类型定义和静态检查：

```sh
tern plugin types plugins/git-open
luau-lsp analyze \
  --platform=standard \
  --definitions=@tern=plugins/git-open/tern.d.luau \
  plugins/git-open/*.luau
```

人工验收：在有 `origin` 的 Git 仓库中执行 `Git Open: Open in GitHub`，确认默认新增内置浏览器 pane；切回仓库 pane，执行 `Git Open: Toggle Browser` 后再次打开，确认交给系统默认浏览器；重载插件后再次打开，确认保留选择。再次执行切换命令可恢复内置浏览器。

## 权限与外部依赖

这是一个 Window-side plugin，不包含 Host-side entry。它需要：

- 读取当前 pane 的工作目录；
- 在该目录执行 `git remote get-url origin`；
- 按选择请求 Tern 内置浏览器打开 URL，或执行系统 URL opener；
- 在插件数据目录保存浏览器选择。

插件不修改仓库、不执行 shell 字符串，也不直接发送网络请求。浏览器加载远程页面时会访问网络。
