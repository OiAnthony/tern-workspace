# Tern 参考资料

## 官方文档

- [Tern Plugin SDK](https://docs.stencil.so/tern/)
- [Getting Started](https://docs.stencil.so/tern/guides/getting-started.md)
- [API Reference](https://docs.stencil.so/tern/reference/api.md)
- [Architecture](https://docs.stencil.so/tern/concepts/architecture.md)
- [Packages and Manifests](https://docs.stencil.so/tern/concepts/packages.md)
- [Lifecycle and Reload](https://docs.stencil.so/tern/concepts/lifecycle.md)
- [Runtime, Budgets, and JIT](https://docs.stencil.so/tern/concepts/runtime.md)
- [Trust and Security](https://docs.stencil.so/tern/concepts/security.md)
- [Example Plugins](https://docs.stencil.so/tern/examples/index.md)
- [Distribution](https://docs.stencil.so/tern/guides/distribution.md)

按任务选择：

| 需求 | 起点 |
|---|---|
| 命令输出转原生视图 | [Command Lenses](https://docs.stencil.so/tern/guides/lenses.md) |
| 新增原生 pane | [Blocks](https://docs.stencil.so/tern/guides/blocks.md) |
| 监听 shell/命令生命周期 | [Host Hooks](https://docs.stencil.so/tern/guides/hooks.md) |
| 命令、快捷键、覆盖 | [Commands](https://docs.stencil.so/tern/guides/commands.md) |
| 文件和链接路由 | [Routing](https://docs.stencil.so/tern/guides/routing.md) |
| tab、标题、状态栏、CSS | [Chrome](https://docs.stencil.so/tern/guides/chrome.md) |
| tab/split 布局 | [Layout](https://docs.stencil.so/tern/guides/layout.md) |

## 官方仓库

- [stencil-hq/tern-sdk](https://github.com/stencil-hq/tern-sdk)：插件示例、`plugins/tern.d.luau` 和 Surface Protocol SDK。
- [stencil.so/tern](https://stencil.so/tern)：Tern 产品入口。
- [luau-lsp](https://github.com/JohnnyMorganz/luau-lsp)：Luau 类型检查和编辑器支持。

SDK 的插件示例：

- `plugins/examples/terraform`：command lens、解析和交互
- `plugins/examples/review-queue`：block、轮询、保存状态
- `plugins/examples/jsonx`：文件驱动 block、JSON 树、路由
- `plugins/examples/longrun`：host hooks、toast、状态栏
- `plugins/examples/dirvars`：spawn filter、环境变量
- `plugins/examples/workspaces`：window layout、tab、split
- `plugins/examples/canvas`：持久化 canvas 和 action

## Skill 状态

目前没有发现专门的公开 Tern Plugin Skill。工作区提供一个项目级 skill：

- [tern-plugin-development](../.agents/skills/tern-plugin-development/SKILL.md)：本目录结构、Host/Window 边界、开发命令、官方文档导航和验证清单。

可搭配的通用 skill：

- `find-skills`：继续检索公开 skill
- `git-commit`：需要提交时遵循仓库提交流程
- `writing-technical-design`：维护架构设计文档

不建议把无关的 `stencil`、电商或通用 UI skill 当作 Tern Plugin SDK 参考。
