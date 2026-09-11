# Unico 公网页部署

生产部署使用 GitHub + Cloudflare Pages，网站不依赖这台 Mac：

- GitHub 仓库：`https://github.com/leowyleo/unico`
- Cloudflare Pages 输出目录：`docs/site`
- 公网入口：`https://unico.leowy.cc/`
- 英文隐私政策：`https://unico.leowy.cc/privacy`
- 中文隐私政策：`https://unico.leowy.cc/zh/privacy`
- 英文支持页：`https://unico.leowy.cc/support`
- 中文支持页：`https://unico.leowy.cc/zh/support`

`docs/site/_redirects` 保留 `/privacy`、`/support`、`/zh/privacy`、`/zh/support` 这四个 Apple 可直接访问的稳定路径。正式支持渠道为 GitHub Issues 和 `leowy.lwy@gmail.com`。

本地服务 `127.0.0.1:3021` 与 Cloudflare Tunnel 路由仅保留作开发或回滚，不作为生产依赖。
