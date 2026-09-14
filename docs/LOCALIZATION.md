# 多语言维护

资源入口：`crossplatform/packages/waytty_l10n/l10n/waytty_zh.arb` 和 `waytty_en.arb`。默认 `zh_CN`，用户选择保存在 `waytty.locale`。桌面、Android 和内置工具插件使用同一套资源。

`LText('Settings')` 将应用文案延迟到构建时解析，const 子树也会响应语言改变；需要 String 的位置用 `tr(context, 'Settings')`。

带动态值使用 `LMessage('Connected to {0}', [host.label])`。只翻译模板，参数不会递归替换或翻译；用户文件名、连接名、终端输出等直接使用普通 Text 或 `LRaw`。不要将命令、协议字段、存储键交给翻译系统。

添加资源时可通过 `script/add_translation_batch.py zh` / `en` 从标准输入传入 JSON「源文案: 译文」，然后执行：

```sh
python3 script/generate_l10n.py
python3 script/generate_l10n.py --check
```

生成器验证两种语言的覆盖率及 `{0}` 等参数是否一致，生成 `lib/src/messages.g.dart`。不要手工编辑或格式化生成文件。`translation_order.json` 是首次迁移的冻结索引，不可重排；后续新增文案直接使用源字符串作为键。

`crossplatform/app/tool/migrate_l10n.dart` 是初始迁移辅助工具。它能发现静态文本，但动态帮助函数、运行时错误和用户数据需要人工判断，不能盲目将所有 String 视为界面文案。

增加第三种语言时，需要新增 ARB、扩展生成器语言集合、`WayttyStrings.supportedLocales`、语言恢复/选择及 LanguagePicker，并运行布局和持久化测试。系统原生文件选择器使用操作系统语言。
