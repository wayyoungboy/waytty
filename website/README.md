# waytty 官网

默认中文、可切换 English，响应式静态官网。产品截图复用 `docs/screenshots/` 已审核图片；首屏终端是明确标注的演示数据示意。平台进展和 AI 规划按实际实现区分，下载入口指向 v0.0.1 Release，明确标注开发版签名和平台范围。

## 本地运行

在仓库根目录：

```sh
python3 script/build_site.py
python3 -m http.server 8765 --bind 127.0.0.1 --directory dist/site
```

浏览器打开 `http://127.0.0.1:8765`。修改 `website/index.html`、`style.css` 或 `app.js` 后重新运行构建命令。无需 npm 或第三方资源服务。

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
- 没有统计脚本、表单、外部字体、第三方图片或服务端。切换语言不设置 cookie。
- 新增截图须确认画面和元数据不含真实主机、账户、终端输出或设备序列号，再加入构建清单。
- 公开应用安装包属于独立发布工作，不能把现有含本机编译路径的开发包直接放入官网。
