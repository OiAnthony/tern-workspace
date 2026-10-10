# Tern Plugin Workspace

用于集中开发多个自定义 [Tern](https://stencil.so/tern) plugin。每个 plugin 都是一个独立、可链接、可发布的 Luau package；本仓库负责组织代码、共享规范、参考资料和开发工具。

## 推荐结构

```text
.
├── plugins/                         # 可安装的插件单元；每个子目录独立可运行
│   ├── <plugin-id>/
│   │   ├── plugin.toml
│   │   ├── host.luau                # 可选：host/session 半部
│   │   ├── window.luau              # 可选：window/UI 半部
│   │   ├── lib/                      # 仅该插件使用的 Luau 模块
│   │   ├── styles/                   # CSS，按需使用
│   │   ├── tests/                    # 可执行的插件级检查或 fixture
│   │   └── README.md
│   └── README.md
├── templates/                       # 新插件模板，不是已安装插件
│   └── basic/
├── tooling/                         # 工作区级脚本，不在插件运行时加载
├── docs/                            # 工作区设计、规范和决策
├── references/                      # 官方仓库、文档、版本基线索引
├── .agents/skills/                  # 本项目专用 Agent Skill
│   └── tern-plugin-development/
├── .vscode/                         # Luau LSP 和编辑器设置
└── README.md
```

## 组织原则

1. **一个插件一个目录**：`plugins/<plugin-id>/` 是独立交付单元，包含自己的 `plugin.toml`、入口和 README。
2. **不共享运行时源码**：Tern plugin 的 `require` 只应加载插件目录内的相对模块。跨插件共享代码会引入发布、版本和信任边界问题。需要复用时，优先复制小模块；确实稳定后再做独立 plugin package。
3. **模板与实例分离**：`templates/` 只保存新插件起点，不参与 Tern 加载；实际插件只放在 `plugins/`。
4. **参考资料不 vendor**：官方 SDK 保持外部 Git 仓库引用，避免把示例和类型定义复制后失去版本来源。
5. **Host / Window 边界显式化**：不要为了复用而把两个入口强行合并。插件 README 应注明使用了哪个半部以及原因。
6. **每个插件都可单独 link**：开发时使用 `tern plugin link plugins/<plugin-id>`，不依赖整个工作区被 Tern 当成一个 package。

## 当前插件

- [`git-open`](plugins/git-open/README.md)：打开当前 Git 项目的远程页面。
- [`shortcut-manager`](plugins/shortcut-manager/README.md)：在原生面板管理自定义快捷动作，支持后台进程、分屏、标签页和 PiP。
- [`auto-tab-groups`](plugins/auto-tab-groups/README.md)：按工作目录和 Git 仓库自动分组，在左侧按项目导航全部 panes，与原生 Files / Git 区域并排。

## 新插件流程

```sh
cp -R templates/basic plugins/my-plugin
# 修改 plugins/my-plugin/plugin.toml 的 id、name、version
tern plugin link "$PWD/plugins/my-plugin"
tern plugin types "$PWD/plugins/my-plugin"
tern plugin list
```

修改 Luau 后由 Tern 自动 reload；必要时执行：

```sh
tern plugin reload
```

## 重要边界

- `host.luau` 运行在 session/host 侧；适合 blocks、lenses、host hooks。
- `window.luau` 运行在窗口 UI 侧；适合 commands、keys、routes、chrome、CSS、layout。
- `tern.d.luau` 是生成文件，不手工编辑；升级 Tern 后重新运行 `tern plugin types`。
- 插件拥有文件和进程能力，安装和 link 都应视为信任操作。

详细设计见 [`docs/workspace-structure.md`](docs/workspace-structure.md)，参考入口见 [`references/README.md`](references/README.md)。
