# Auto Session

按 main pane 的目录名自动管理原生 Tern Session 名称，检测到手动改名后停止自动改名。

> 空 Session 自动关闭已由 Tern 原生提供（**Settings → Sessions → Closing → Close empty sessions**），本插件不再重复实现。

## 行为与规则

- 新建或首次观察到 Session 时，读取当前 Session 第一 tab 的第一个 tiled leaf 作为 main pane。
- main pane 的 `cwd` 为 `/work/projects/tern` 时，Session name 会变成 `tern`。
- main pane 目录变化后，Session name 会同步更新。
- 如果用户主动修改 Session name，插件会锁定该 Session，之后不再自动改名。
- floating pane、焦点 pane 和其他 split 不改变 main pane 的判断。
- 人工锁定状态保存于插件自己的 Tern KV 数据中，可跨 reload 和 daemon restart 保留。

## 安装

```sh
tern plugin install ./plugins/auto-session
tern plugin list
```

开发时可直接 link：

```sh
tern plugin link "$PWD/plugins/auto-session"
tern plugin reload auto-session
```

如果此前安装或 link 过旧版 `session-name`，请先卸载或取消 link，避免两个插件同时修改 Session 名称：

```sh
tern plugin unlink session-name  # 或 tern plugin remove session-name
```

## 架构与权限

- 仅使用 **Window 侧**（`window.luau`）：调用 `cx.sessions`、`cx.session` 与 `tern.kv`。
- 不运行外部命令，不访问网络，不需要额外权限。

## 开发与验证

```sh
tern plugin types plugins/auto-session
luau-lsp analyze \
  --platform=standard \
  --definitions=@tern=plugins/auto-session/tern.d.luau \
  plugins/auto-session/window.luau plugins/auto-session/lib/logic.luau
luau plugins/auto-session/tests/logic_test.luau
plugins/auto-session/tests/native.sh
```

`tests/native.sh` 会在隔离的 Tern runtime（独立 `STENCIL_FIXTURE_ROOT`、`TERN_CONFIG_DIR`、`TERN_DAEMON_SOCKET` 与 control socket）中验证自动命名、目录切换同步更新以及手动改名锁定行为。需要本机可用 `tern`、`bash` 与 `jq`。
