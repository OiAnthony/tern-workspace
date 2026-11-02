---
name: tern-plugin-development
description: 用于本工作区的 Tern 插件开发、Plugin API 更新调查、类型定义同步及隔离 runtime 验证；不用于通用终端或 agent 编排。
---

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
   - Window：command、bind、override、route、chrome、Files 按钮、layout、canvas、agent 事件。
2. 新插件复制模板并修改 `plugin.toml` 的 `id`、`name`、`version`；已有插件沿用自身结构。
3. 先运行 `tern --version`，再运行 `tern plugin types plugins/<plugin-id>` 生成本机 runtime 对应的类型定义。
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
- 类型定义将 Host/Window 成员放在同一个 `tern` 声明里，静态检查不能保证 VM 边界正确；仍需按官方文档核对。
- 异步回调使用回调收到的新 `cx`；插件 handler 返回后，不保留其 `cx` 供后续调用。

## API 更新调查

1. 记录本机 `tern --version`。先在临时目录执行 `tern plugin types DIR`，不要为了调查覆盖插件现有定义。
2. 对比临时定义、目标插件定义和官方 SDK 的 `plugins/tern.d.luau`；不同插件可能有不同基线。
3. 查询 [类型定义提交记录](https://github.com/stencil-hq/tern-sdk/commits/main/plugins/tern.d.luau)，固定提交 SHA 后比较。区分 SDK 同步日期、产品版本和本机已具备能力，不从同步日期推断首次发布版本。
4. 按需核对 [Window API](https://docs.stencil.so/tern/reference/api-window.md)、[Host API](https://docs.stencil.so/tern/reference/api-host.md) 和 [Shared API](https://docs.stencil.so/tern/reference/api-shared.md)。声明与行为不一致时以实际 runtime 为准，并报告差异。
5. 只在隔离 runtime 中执行会改布局、Session 或注册状态的探针。报告分别说明声明已存在、调用已验证、渲染/交互已验证；Carly Lua 能力不等于插件注册 API 已验证。
6. 结束后停止本次 runtime、清理临时夹具。调查不自动升级应用、注册插件或更新仓库类型定义。

### 已核对基线：2026-11-02

本机 `tern 0.9.9 (9c1c09f)` 生成的定义与官方 SDK 提交 `7c997804d7a2e9f4f28fb94abd3672f8c3292ce0` 完全一致。后续任务先重新核对，不将此版本快照当作永久契约。

| 需求 | 当前 API 导航与边界 |
|---|---|
| 原生交互 UI | `tern.ui.button`、`stats`；table 支持稳定行 ID、选择/激活、行菜单、禁用和 badge/button/sparkline 单元格；`BlockDef.font` 支持 sans/mono |
| Files 扩展 | `tern.files.button` 获取 root、host、selection、tab；通过 `tern.chrome.program_icon` 定制程序图标 |
| 精确布局 | `cx:new_block` 和 canvas 支持 target/dir/ratio；`cx.layout:float` 支持 size；`how="over"` 在新 block 关闭后恢复原 pane |
| 选区和窗口路由 | `cx.session:selection` 默认最多 8000 字符、上限 64000；`cx:window_key()` 获取 CLI 路由 key |
| Agent 生命周期 | `cx.agents:get` 返回 Agent 句柄；`Agent:tocarly("finished", message)` 安排 Carly 后续运行；`agent_finished` 区分 done/failed/exited/closed；`agent_state` 观察状态变化 |
| 布局与预算事件 | `float_moved` 仅用户拖动/抛掷触发，不由键盘或插件调用触发；另有 `session_ended`、`budget` |
| Browser | `cx.browser:call` 支持用户点选元素的 pick 和 `open(show=false)`；不绕过驱动或审批策略 |

`cx:pick`、`cx:prompt` 在工作区部分旧定义中已存在，不能统一算作本次新增。Agent 的 idle、finished 或进程退出都不是特定任务成功的充分证据，仍需读取结果。

## 隔离验证与已知限制

- 先读插件现有 native runner，沿用它的启动和清理方式。使用独立的 `STENCIL_FIXTURE_ROOT`、`TERN_CONFIG_DIR`、`TERN_DAEMON_SOCKET`、control socket 和输出目录，避免接入用户日常 Session。
- 开发工具发现使用 `tern help dev`。不要运行 `tern serve --help`：0.9.9 实测会直接启动 runtime，并使用默认 control socket，而不是显示帮助。
- Headless Carly Lua 可调用普通 Window API，但没有插件注册 API 和 `tern.secrets`。需要验证 `tern.command`、`tern.on`、Files 按钮或 chrome 注册时，使用隔离夹具插件，不用 Carly 调用代替。
- Headless `ctl carly lua` 的实际结果读 `.carly.last_tool`；`ctl carly ok` 只证明调用无错误，不证明行为满足要求。对照实际 Session/layout、UI tree 或 PNG 验证结果。
- 预算为 Host 2 秒、Window 50 毫秒、chrome/available 4 毫秒；原生调用不计入 Lua 时间，但整次调用有十倍预算的墙钟上限。超预算 hook 暂停，从 5 秒指数退避到最多 5 分钟。原生调用若一直阻塞，预算不能中断它；Window 侧避免阻塞 I/O，`tern.fs.read` 按需指定 max_bytes。
- 整 tab 跨 Session 无损迁移仍未验证可用。0.9.9 隔离实测 `cx.layout:arrange({session=target,tabs={{tab=source,blocks={}}}})` 返回 `unknown tab … in session …`，原 tab 留在源 Session；现有 `order_tab` 只在自身 Session 内重排，pane 迁移不是整 tab 迁移。
- 若后续版本新增迁移能力，用多层 split、非等分 ratio、floating、name/color 的临时 tab 验证目标 Session、tab/pane IDs、tree、floats、focus 和程序均保留。不能把排序、自绘 sidebar 或按 blocks 重建布局称为无损自动归组。

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
