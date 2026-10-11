# NucLED 冥王 LED

一款面向 Intel 冥王峡谷（Hades Canyon）NUC 的 macOS 菜单栏工具，可手动开关 LED，并按每天设定的时间自动开关。应用通过本项目提供的 IOKit 内核驱动访问主板 WMI 接口；没有驱动时不会假装操作成功。

[简体中文](README.md) · [English](README-en.md) · [日本語](README-ja.md) · [한국어](README-ko.md)

## 功能

- 点击顶部菜单栏的骷髅图标，打开 LED 控制面板。
- 手动启用或停用 LED 指示灯模式；应用会回读硬件状态确认结果。
- 设置每日开启和关闭时间。睡眠唤醒、系统时间或时区改变后会重新核对计划。
- 可选“登录时启动”。应用退出后定时计划暂停，重新打开后继续。
- 关闭 LED 前保存灯区模式快照，恢复时校验快照并逐区回读。

界面支持简体中文、英文、日文和韩文，并根据 macOS 的首选语言自动选择；没有匹配语言时默认使用简体中文。

本项目仅控制固件提供的 LED 模式，不控制颜色或亮度。读到 Power State 模式也不能证明灯珠当前有可见亮度。

## 适用设备与系统

- 目标设备：Intel Hades Canyon NUC8i7HVK / NUC8i7HNK，且固件提供项目验证过的 `AMW0` WMI 接口。
- 应用：macOS 13 或更新版本；Swift Package Manager 项目。
- 驱动：Intel `x86_64`，当前最低构建目标为 macOS 15.5；目前只在 macOS 15.5 黑苹果上验证。应用能运行不代表驱动能在该系统加载。

这不是通用 Mac LED 控制器，也不支持 Apple Silicon 或其他 NUC 型号。

## 安装应用

从 [GitHub Releases](https://github.com/winglight9/NucLED/releases/latest) 下载 `NucLED-Installer.dmg`，双击打开，把 `NucLED.app` 拖入“应用程序”，然后从“应用程序”启动。启动后请点击屏幕顶部菜单栏中的骷髅图标；应用不显示 Dock 图标，也不打开独立主窗口。若菜单栏空间不足，请检查系统的菜单栏隐藏/溢出区域。

当前 DMG 只安装应用，不含驱动、驱动安装器或卸载器。驱动源码构建出的 KEXT 未签名；开发机使用了自定义测试安全配置，不能据此保证它可在常规 macOS 安全配置下加载。macOS 11 及更新版本的第三方 KEXT 需要用户批准并重启；Apple 也不再建议一般软件使用 KEXT。[Apple 的 KEXT 部署说明](https://support.apple.com/guide/deployment/system-extensions-in-macos-depa5fb8376f/web)详述了批准与重启要求。详见 [`Driver/README.md`](Driver/README.md)。本项目目前是硬件验证/开发预览，尚不是可供普通用户一键安装的完整硬件套件；不要为了运行它而关闭整机 SIP。

应用目前使用本地临时签名，没有 Developer ID 签名或 Apple 公证。macOS 可能提示无法验证开发者；仅在你信任下载来源并核对发布文件后，才使用 Finder 的“按住 Control 键点按 → 打开”。Apple 的[公证说明](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)说明了公开分发所需的签名和公证流程。登录启动还要求应用位于“应用程序”，并可能需要在“系统设置 → 通用 → 登录项”批准。

## 从源码构建

需要 Xcode Command Line Tools 和 macOS SDK：

```sh
swift build --configuration release
./script/build_dmg.sh
```

`./script/build_dmg.sh` 会生成 `dist/NucLED-Installer.dmg`。生成应用使用本地临时签名，不能替代 Developer ID 签名与公证流程。

构建驱动 bundle：

```sh
make -C Driver bundle
```

该命令只编译未签名的 `Driver/.build/NUCLEDDriver.kext`，**不会安装或加载驱动**。驱动包含内核态代码，仅适用于匹配的 Intel 冥王峡谷设备。请阅读驱动说明并自行评估安装风险。

## 硬件验证状态

开发机上的冥王峡谷已完成一次真实 WMI 写入与回读：读取六个灯区状态、停用后逐区确认，再恢复原模式并再次回读。该验证不代表其他主机配置可用，也没有用相机或光传感器确认物理发光。公开版 DMG 仅包含应用；目前没有可供普通用户安装的签名驱动包。

## 故障排查

- **点应用图标没有窗口：** 这是菜单栏应用。请改点顶部菜单栏的骷髅图标打开控制面板。
- **找不到骷髅图标：** 确认 NucLED 正在运行，并查看菜单栏隐藏区域。
- **面板显示驱动不可用：** 确认 `NUCLEDDriver` 已加载；应用不包含驱动安装器。
- **开关操作失败：** 以面板状态文字为准。应用在回读确认失败时会报告错误，不会把请求当成成功。

## 源码与许可

仓库包含 macOS 应用、驱动源码、构建脚本和图标资源。驱动接口与安全边界见 [`Driver/README.md`](Driver/README.md)。当前仓库尚未声明开源许可证；公开查看源码不等于授予复制、修改或分发许可。

