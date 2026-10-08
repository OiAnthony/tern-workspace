# Tern Plugin Development

本 skill 适用于当前工作区中的 Tern plugin 开发。它补充项目约定，不替代官方 API 文档。

## 工作区边界

- 实际插件放在 `plugins/<plugin-id>/`。
- 新插件从 `templates/basic/` 复制。
- 官方资料和 SDK 入口见 `references/README.md`。
- 不从工作区根目录或其他插件加载运行时模块；跨插件共享代码必须显式设计并记录。

## 开发步骤

1. 确认需求属于哪一侧：
   - Host：block、command lens、host hook、spawn filter、pane 写入。
   - Window：command、bind、override、route、chrome、CSS、layout。
2. 复制模板并修改 `plugin.toml` 的 `id`、`name`、`version`。
3. 运行 `tern plugin types plugins/<plugin-id>` 生成类型定义。
4. 使用 `--!strict` 和 `luau-lsp` 检查 Luau。
5. 使用 `tern plugin link` 注册插件，使用 `tern plugin list` 确认加载。
6. 在真实 Tern window/pane 中触发变更路径；不要只以静态检查通过作为完成条件。
7. 在插件 README 记录安装、权限、外部命令和 Host/Window 选择。

## 关键约束

- `host.luau` 和 `window.luau` 运行在不同 Luau VM。
- Host-only API 不能从 Window 调用；Window-only API 不能从 Host 调用。
- `tern.d.luau` 是生成文件，不能手工修改。
- 插件可访问文件和进程。把安装插件视为信任操作。
- `require` 使用插件目录内的相对模块；避免隐式工作区依赖。

## 参考顺序

1. `references/README.md`
2. 官方 [Getting Started](https://docs.stencil.so/tern/guides/getting-started.md)
3. 官方 [API Reference](https://docs.stencil.so/tern/reference/api.md)
4. `stencil-hq/tern-sdk` 对应的 example plugin
5. 按需求阅读 lens、block、hooks、commands、routing、chrome 或 layout 指南

## 完成检查

- [ ] manifest 能解析
- [ ] `tern plugin types` 已执行
- [ ] luau-lsp 无新增错误
- [ ] `tern plugin list` 显示 ready
- [ ] 真实行为已在 Tern 中触发
- [ ] reload 后行为仍然正常
- [ ] README 和权限说明已更新
