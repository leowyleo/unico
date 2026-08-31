# Unico v1.1.3 — Community preview

A little less. A little lighter.

Unico finds identical files on your Mac, lets you preview and choose what stays, and moves confirmed extras to Trash.

## Included

- Exact-content comparison across selected folders or the internal disk.
- Explicit folder selection overrides default exclusions only after a risk warning and confirmation. Internal-disk scans retain their default exclusions.
- Thumbnail previews, Quick Look, suggested keeper and per-file cleanup selection.
- Compact native title bar, English by default and instant Simplified Chinese switching.
- Content and identity revalidation immediately before cleanup. At least one copy stays; no permanent-delete operation.
- Universal Apple Silicon + Intel bundle with a macOS 12.0 deployment target.

## Install and trust

Download `Unico-v1.1.3-macOS-universal.dmg`, double-click it, and drag `Unico.app` to the Applications shortcut. A ZIP fallback remains available. The build is **ad-hoc signed, not Developer ID signed, and not notarized by Apple**. Review any macOS app-specific first-launch warning; do not disable Gatekeeper globally. See the repository README for installation steps.

Verified on Apple Silicon / macOS 26.5.1 with 24 passing tests. macOS 12/13 and Intel hardware remain untested in person. This is an early community preview; keep backups.

## Before cleanup

Identical contents do not make every path disposable. Removing app, project or system resources may break functionality. Folder-scope confirmation is separate from cleanup confirmation. Links, hard links, inaccessible items and cloud files not stored locally are skipped.

Moving files to Trash does not immediately free disk space. Unico does not empty Trash. Similar-image matching is not included.

---

## 中文

Unico 的第一个公开社区预览版：找出完全相同的文件，预览后决定留哪份，再确认移到废纸篓。

本版提供指定目录与内置磁盘扫描、缩略图与大图预览、自动推荐保留项、中英切换。主动选择的目录经确认可覆盖默认排除规则，全盘扫描仍保持默认保护。

安装包最低目标为 macOS 12，包含 Apple 芯片和 Intel 两种架构；已在 Apple Silicon / macOS 26.5.1 实测，旧系统与 Intel 实机仍待验证。当前没有 Developer ID 签名及 Apple 公证。

下载 DMG 后双击打开，将 `Unico.app` 拖入“应用程序”快捷入口；ZIP 仍保留作为备用下载。

**删除相同的应用、项目或系统资源仍可能导致功能失效。请保留备份，确认这些位置的副本不再需要。只移到废纸篓，不永久删除。**
