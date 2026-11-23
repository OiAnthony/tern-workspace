# Auto Session

自动管理原生 Tern Session 的命名与空 Session 清理：

- **自动命名**：按 main pane 的目录名同步 Session 名称，检测到手动改名后停止自动改名。
- **自动关闭空 Session**：当曾经有 pane/tab 的 Session 因关闭所有 pane（或将最后一个 pane 移到其他 Session）而变空时，自动关闭该 Session 并切回上一个 Session。

## 行为与保护规则

### 自动命名
- 新建或首次观察到 Session 时，读取当前 Session 第一 tab 的第一个 tiled leaf 作为 main pane。
- main pane 的 `cwd` 为 `/work/projects/tern` 时，Session name 会变成 `tern`。
- main pane 目录变化后，Session name 会同步更新。
- 如果用户主动修改 Session name，插件会锁定该 Session，之后不再自动改名。
- floating pane、焦点 pane 和其他 split 不改变 main pane 的判断。
- 人工锁定状态保存于插件自己的 Tern KV 数据中，可跨 reload 和 daemon restart 保留。

### 自动关闭空 Session
- 仅关闭**曾经有过 tab/pane** 且当前 `tabs == 0` 的 Session；新建的空 Session 或从未有过 pane 的空 Session 不会被误关。
- **尊重锁定**：`locked` 状态的 Session 变空时保持打开，不绕过锁定关闭。
- **保护 Parked panes**：把唯一 pane `park` 到 deck 后 `tabs == 0` 但 pane 仍在后台运行，Session 会保持打开；只有当该 Session 的 parked pane 也全部关闭/移出后才会自动关闭。若存在归属未知的 parked pane（例如插件启动前已 parked），则保守跳过自动关闭。
- **保留最后一个 Session**：同一 Host 上仅剩 1 个 Session 时不执行关闭。
- **跨 Session 移动**：最后一个 pane 被移到其他 Session 导致原 Session 变空时，也会自动关闭变空的原 Session。

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

`tests/native.sh` 会在隔离的 Tern runtime（独立 `STENCIL_FIXTURE_ROOT`、`TERN_CONFIG_DIR`、`TERN_DAEMON_SOCKET` 与 control socket）中验证自动命名、关空自动关闭、锁定保护、parked pane 保护、跨 Session 移动最后一个 pane 以及仅剩单个 Session 的边界行为。需要本机可用 `tern`、`bash` 与 `jq`。
