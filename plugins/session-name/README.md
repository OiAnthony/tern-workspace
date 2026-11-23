# Session Name

将原生 Tern Session 的名称跟随 main pane 目录名更新。

## 行为

- 新建或首次观察到 Session 时，读取当前 Session 第一 tab 的第一个 tiled leaf 作为 main pane。
- main pane 的 `cwd` 为 `/work/projects/tern` 时，Session name 会变成 `tern`。
- main pane 目录变化后，Session name 会同步更新。
- 如果用户主动修改 Session name，插件会锁定该 Session，之后不再自动改名。
- floating pane、焦点 pane 和其他 split 不改变 main pane 的判断。
- 空 Session、未知目录和空目录名会跳过本次同步。
- Session 的人工锁定状态保存于插件自己的 Tern KV 数据中，可跨 reload 和 daemon restart 保留。

Tern 当前没有公开的 Session rename event 或名称来源字段。插件通过记录最近一次自动写入的名称来识别后续人工修改。插件首次观察 Session 前已经完成的人工改名无法从公开 API 中可靠区分，首次观察会按当前设计认领该 Session。

## 安装

```sh
tern plugin install ./plugins/session-name
tern plugin list
```

开发时可直接 link：

```sh
tern plugin link "$PWD/plugins/session-name"
tern plugin reload session-name
```

插件只使用 Window API、Session rename、Session layout、pane cwd 和插件 KV，不运行外部命令，也不需要额外权限。

## 开发检查

```sh
tern plugin types plugins/session-name
luau-lsp analyze \
  --platform=standard \
  --definitions=@tern=plugins/session-name/tern.d.luau \
  plugins/session-name/window.luau plugins/session-name/lib/logic.luau
luau plugins/session-name/tests/logic_test.luau
```

真实使用时验证新建 Session、目录切换、手动改名、reload、split、floating pane 和空 Session。
