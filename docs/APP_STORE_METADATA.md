# Unico · App Store Connect 素材清单

## 已确定

- App 名称：Unico
- Bundle ID：`cc.leowy.unico`
- 类别：Utilities（工具）
- 隐私政策 URL：`https://unico.leowy.cc/privacy`
- 支持 URL：`https://unico.leowy.cc/support`
- 运营者：中文“行与未见”；英文“Leowy”
- 支持邮箱：`leowy.lwy@gmail.com`；GitHub Issues 为正式支持渠道
- 隐私实践：不跟踪、不收集、不上传数据；无第三方 SDK
- App Store 构建：沙盒化，仅扫描用户选择的文件夹

## 仍需在 Apple 账户完成

- App Store Connect App Record：先确认 Business 协议已签，再创建 macOS App Record；Bundle ID 使用 `cc.leowy.unico`。
- Team ID；App Store 应用签名证书；`cc.leowy.unico` 的 Mac App Store Connect provisioning profile。
- Mac Installer Distribution 证书（钥匙串通常显示为 `3rd Party Mac Developer Installer: …`）。
- SKU、定价和销售地区。
- 年龄分级问卷与出口合规问卷
- 中文、英文的名称、简介、关键词和完整描述
- App Store 截图（在最终 App Store 构建上采集）

## 版本提交前

- 使用新的、尚未上传过的 `CFBundleVersion`
- 不要把 GitHub 用的 DMG 或 ZIP 上传到 App Store。
- 使用 `scripts/prepare-app-store-bundle.sh` 生成签名 `.pkg`。脚本需要本机钥匙串和 profile，运行前设置：

  ```zsh
  export APP_STORE_APPLICATION_IDENTITY='Mac App Distribution: …'
  export MAC_APP_STORE_INSTALLER_IDENTITY='Mac Installer Distribution: …'
  export APP_STORE_PROVISIONING_PROFILE="$HOME/Library/MobileDevice/Provisioning Profiles/<profile>.provisionprofile"
  zsh scripts/prepare-app-store-bundle.sh
  ```

- 成功后运行 `zsh scripts/check-app-store-submission.sh`，然后用 Xcode 或 Transporter 上传生成的 `.pkg`（命名为 `Unico-v<版本>-<构建号>-mac-app-store.pkg`）。
- 在 App Store Connect 中核对隐私问卷与本政策一致
