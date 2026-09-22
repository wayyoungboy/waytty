# waytty 官网

默认中文、可切换 English 的响应式静态官网。产品叙事依次为：终端工作区 → 常用工作流 → 真实应用界面 → 本地与云端 → 下载与安装 → 常见问题。

官网、[中文 README](../README.md) 与 [English README](../README_EN.md) 使用相同的产品定位、下载版本和功能边界。当前下载指向 **v0.0.1 macOS Universal**；邮箱账号备份明确标为开发预览，不代表已部署的公共服务。

## 页面与设计

- `index.html`：可索引的中文正文、英文翻译属性、语义结构与下载入口。
- `style.css`：白底、深绿、浅绿强调色；统一字体、间距、状态与移动布局。
- `app.js`：语言与 URL 同步、移动导航、独立标签页、截图放大及键盘操作。
- `favicon.svg`：官网与 README 共用的标志。

首页工作区由 HTML / CSS 渲染，终端、文件和监控标签可切换。它是**功能交互示意**，使用虚构主机和固定输出，不会发起 SSH、执行命令或上传信息。不要把它标为真实应用截图。`docs/screenshots/workspace-demo.png` 是该示意的浏览器截图，用于 README 与社交预览。

下方截图来自 `docs/screenshots/` 的真实应用画面。连接管理使用空白演示数据；串口截图保留实际界面，不能据此宣称所有硬件已完成验收。新增图像必须保留准确的来源说明。

## 交互与可访问性

- 语言只保存在本地 `localStorage`；`?lang=en` 可分享英文页面，`?lang=zh-CN` 可指定中文，URL 优先于本地偏好。文档链接和连接截图随语言切换。
- 每组标签页独立工作，支持左右方向键、Home、End，不会隐藏其他组的内容。
- 截图使用原生 `dialog`，支持 Escape，关闭后焦点回到触发链接；FAQ 使用原生 `details`。
- 移动导航提供展开状态与 Escape 关闭；页面有跳过导航、可见键盘焦点及减少动效支持。
- 禁用 JavaScript 后，中文正文、下载、文档、默认真实截图链接和 FAQ 仍可用；语言切换、演示与图库切换需 JavaScript。

维护时检查 1440、768、390 和 320 像素宽度下的中英文布局，特别是英文下载按钮、长标题、平台列表和终端的内部横向滚动。页面本身不应横向溢出。

## 本地运行

在仓库根目录：

```sh
python3 script/build_site.py
python3 -m http.server 8765 --bind 127.0.0.1 --directory dist/site
```

浏览器打开 `http://127.0.0.1:8765`。修改 `website/index.html`、`style.css` 或 `app.js` 后重新运行构建命令。无需 npm 或第三方资源服务。

发布前检查：

```sh
python3 script/check_site.py
python3 -m unittest discover -s script -p 'test_*.py' -v
node --check website/app.js
```

同时在桌面和手机宽度下检查中英文排版、下载入口、导航、截图切换与放大预览。

## GitHub Actions 部署

1. 将审核后的源码推送到 `wayyoungboy/waytty` 的 `main` 分支。
2. 仓库 **Settings → Pages → Build and deployment → Source** 选择 **GitHub Actions**。
3. 在 **Actions → Website → Run workflow** 手动运行一次。之后每次推送到 `main` 自动重新部署；PR 只检查和构建，不发布。
4. 默认地址：`https://wayyoungboy.github.io/waytty/`，以部署任务输出的 `page_url` 为准。

工作流先运行隐私检查及网站构建验证，成功后仅上传 `dist/site`。部署任务使用 `github-pages` environment、`pages: write` 和 `id-token: write`，无需在仓库保存个人访问令牌。

CI 还会阻止带有非 GitHub noreply 邮箱的历史提交。首次公开使用不继承个人开发历史的发布副本；后续提交也应先在 GitHub 邮箱设置中查看自己的 noreply 地址，并仅为本仓库配置相应 Git 提交身份。

使用[官方 GitHub Pages 工作流](https://docs.github.com/en/pages/getting-started-with-github-pages/using-custom-workflows-with-github-pages)的构建产物部署方式，依赖 action 固定到提交 SHA。Gitleaks 固定版本并校验下载文件的 SHA-256。

## 发布边界

- `build_site.py` 使用明确的文件清单，不会把源码、测试密钥、应用配置或本地安装包一起上传。
- 链接和资源使用相对路径，支持 GitHub 项目站点的 `/waytty/` 前缀。
- 没有统计脚本、表单、外部字体、第三方图片或服务端。语言偏好不发送到服务器，也不设置 cookie。
- 新增截图须确认画面和元数据不含真实主机、账户、终端输出或设备序列号，再加入构建清单。
- 公开应用安装包属于独立发布工作，不能把现有含本机编译路径的开发包直接放入官网。
