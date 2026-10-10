# Plugins

本目录只放实际可安装的 Tern plugin。每个直接子目录都应是一个独立 package：

```text
plugins/<plugin-id>/
├── plugin.toml
├── host.luau       # 可选
├── window.luau     # 可选
├── lib/            # 可选，插件私有模块
├── styles/         # 可选
├── tests/          # 可选
└── README.md
```

不要把官方 SDK 示例直接复制到这里。需要参考时使用 `references/README.md` 中的仓库和文档链接。

## 插件

| 插件 | 用途 |
| --- | --- |
| [git-open](git-open/README.md) | 打开当前 Git 项目的远程页面 |
| [shortcut-manager](shortcut-manager/README.md) | 原生管理面板、自定义快捷键、后台命令、pane / tab / PiP |
