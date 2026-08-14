# MediCheck

MediCheck 是一个 macOS 14+ 原生菜单栏用药提醒与记录工具。它支持固定疗程、长期计划和按需用药，所有药品与计划都由用户自行录入。

## v2 功能

- 任意数量的药品与每日提醒时间
- 固定起止日期的疗程、长期计划及每周重复日期
- 不定时的按需用药记录
- 到点提醒、未确认重复提醒、睡眠唤醒与跨日检查
- 每次确认或跳过前二次确认
- 日历历史与最近 7 天统计
- 系统通知及通过 `SMAppService` 登录启动
- v1 早/中/晚记录自动迁移

## 隐私与医疗边界

MediCheck 不联网、没有账号，数据仅保存在本机应用沙盒。应用只执行用户录入的提醒和记录，不提供诊断、剂量、相互作用、漏服补服或其他医疗建议。具体用药方案请咨询医生或药师。

请不要在公开 issue、日志或截图中提交处方、病历、姓名等隐私信息。

## 开发

项目使用 [XcodeGen](https://github.com/yonaskolb/XcodeGen) 管理工程文件：

```bash
xcodegen generate --spec project.yml --project .
xcodebuild -project MediCheck.xcodeproj -scheme MediCheck test
xcodebuild -project MediCheck.xcodeproj -scheme MediCheck -configuration Release build
```

也可以用 Xcode 打开 `MediCheck.xcodeproj`，选择 `MediCheck` scheme 和 `My Mac` 后运行。

## 发布说明

源码已启用 App Sandbox 和 Hardened Runtime。面向其他用户分发前仍需使用自己的 Apple Developer 身份签名并完成 notarization；提交 Mac App Store 时还需在 App Store Connect 配置应用记录与隐私信息。

## 本地数据

默认 Bundle ID 为 `com.local.MediCheck`，沙盒数据位于：

`~/Library/Containers/com.local.MediCheck/Data/Library/Preferences/com.local.MediCheck.plist`

用药记录最多保留 730 天。卸载或清除容器可能删除这些本地数据。
