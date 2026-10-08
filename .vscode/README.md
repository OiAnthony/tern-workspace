# VS Code

不同插件可使用不同版本的 Tern API 定义。不要在工作区固定一个隐含的 `tern.d.luau` 路径。

进入某个插件目录后生成类型文件：

```sh
tern plugin types "$PWD"
```

再按官方文档配置 `luau-lsp.types.definitionFiles`，将 `@tern` 指向当前插件目录下的 `tern.d.luau`。如果多个插件确认使用同一 Tern 版本，可以在工作区级复用其中一个生成文件，但升级 Tern 后必须重新生成并检查。
