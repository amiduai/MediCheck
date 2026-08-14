# MediCheck（吃药提醒）

macOS 14+ 原生菜单栏吃药提醒工具。数据仅保存在本机，不联网，也不提供医疗建议。

## 打开与运行

1. 用 Xcode 打开 `MediCheck.xcodeproj`。
2. 选择 `MediCheck` scheme 和 `My Mac`。
3. 按 `⌘R` 运行；首次运行时允许通知权限。

菜单栏会出现药丸图标。设置页可以修改早、中、晚时间、重复提醒间隔、晚间检查和登录启动。

## 命令行构建与测试

```bash
xcodebuild -project MediCheck.xcodeproj -scheme MediCheck -configuration Release build
xcodebuild -project MediCheck.xcodeproj -scheme MediCheck test
```

## 导出 App

在 Xcode 中选择 Product → Archive，完成后在 Organizer 里选择 Distribute App → Copy App。个人本机使用也可直接复制 Xcode 构建产物中的 `MediCheck.app` 到 `/Applications`。

为了让“登录时自动启动”保持可靠，确定最终位置后再在 App 设置中打开该开关；不要在启用后移动 App。

## 本地数据

App 使用沙盒内的 `UserDefaults`：

`~/Library/Containers/com.local.MediCheck/Data/Library/Preferences/com.local.MediCheck.plist`

记录保留最近 90 天，历史页展示最近 30 天。

