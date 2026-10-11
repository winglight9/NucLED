# NucLED for Hades Canyon

A macOS menu bar utility for Intel Hades Canyon NUCs. It provides a manual LED mode switch and a daily on/off schedule. The app accesses the motherboard WMI interface through this project's IOKit kernel driver; without the driver, it reports that control is unavailable instead of claiming success.

[简体中文](README.md) · [English](README-en.md) · [日本語](README-ja.md) · [한국어](README-ko.md)

## Features

- Click the skull in the macOS menu bar to open the control panel.
- The menu bar, control panel, and app icon use the Hades Canyon lid skull silhouette; the menu bar version follows macOS's monochrome tint.
- Enable or disable LED indicator modes manually and read the hardware back to confirm the result.
- Set daily on and off times. The schedule is reconciled after wake, a clock change, or a time-zone change.
- Optionally launch at login. Quitting pauses the schedule; reopening the app resumes it.
- Save a per-zone mode snapshot before disabling LEDs, then validate and restore it one zone at a time.

The interface is available in Simplified Chinese, English, Japanese, and Korean. It follows the preferred language in macOS and falls back to Simplified Chinese when none matches.

The project changes firmware LED modes only. It does not control color or brightness. Reading the Power State mode does not prove that an LED is visibly illuminated.

## Supported hardware and system

- Target: Intel Hades Canyon NUC8i7HVK / NUC8i7HNK with the verified `AMW0` WMI interface.
- App: macOS 13 or later; built with Swift Package Manager.
- Driver: Intel `x86_64`, with a current minimum build target of macOS 15.5; it has only been verified on a macOS 15.5 Hackintosh. An app that launches does not mean the driver can load on that system.

This is not a general Mac LED controller. Apple Silicon and other NUC models are not supported.

## Install the app

Download the latest versioned installer DMG from [GitHub Releases](https://github.com/winglight9/NucLED/releases/latest), open it, and drag `NucLED.app` to Applications. Launch it from Applications, then click the skull in the menu bar. NucLED has no Dock icon or separate main window. If menu bar space is constrained, check macOS's hidden or overflow menu bar items.

The current DMG contains only the app; it does not include the driver, driver installer, or uninstaller. The KEXT built from the driver source is unsigned. The development host used a custom test security configuration, so this does not establish that the driver will load with normal macOS security settings. Third-party KEXTs on macOS 11 and later require user approval and a restart, and Apple no longer recommends KEXTs for general software. See [Apple's KEXT deployment guidance](https://support.apple.com/guide/deployment/system-extensions-in-macos-depa5fb8376f/web) and [`Driver/README.md`](Driver/README.md). This is currently a hardware-validation/developer preview, not a turnkey hardware installer for general users. Do not disable full-system SIP just to run it.

The app currently uses a local ad-hoc signature and is not signed with Developer ID or notarized by Apple. macOS may warn that the developer cannot be verified. Only use Finder's Control-click → Open flow after you trust the download source and have checked the release files. Apple's [notarization guidance](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution) describes the signing and notarization steps for public distribution. Login launch requires the app to be in Applications and may need approval under System Settings → General → Login Items.

## Build from source

Xcode Command Line Tools and the macOS SDK are required:

```sh
swift build --configuration release
./script/build_dmg.sh
```

The script creates a versioned disk image, such as `dist/NucLED-1.0.7-Installer.dmg`. The app is ad-hoc signed; this does not replace Developer ID signing and notarization.

Build the driver bundle with:

```sh
make -C Driver bundle
```

This only builds the unsigned `Driver/.build/NUCLEDDriver.kext`; it does **not** install or load it. The driver contains kernel code and is only intended for compatible Intel Hades Canyon hardware. Read the driver documentation and assess installation risks first.

## Hardware validation

On the development Hades Canyon host, a real WMI write/readback cycle was completed: six LED zones were read, disabled and verified individually, then restored to their prior modes and read back again. This does not establish compatibility with other hosts, and no camera or light sensor was used to verify visible emission. The public DMG contains the app only; there is currently no signed driver package for general users.

## Troubleshooting

- **Clicking the app icon shows no window:** NucLED is a menu bar app. Click the skull in the menu bar to open the controls.
- **The skull is missing:** Confirm NucLED is running and check hidden menu bar items.
- **The panel says the driver is unavailable:** Confirm `NUCLEDDriver` is loaded; the app bundle has no driver installer.
- **A switch action fails:** Follow the status text in the panel. The app reports readback failures instead of treating a request as successful.

## Source and license

The repository contains the macOS app, driver source, build scripts, and icon assets. See [`Driver/README.md`](Driver/README.md) for the driver interface and security boundary. No open-source license has been declared. Public access to the source does not grant permission to copy, modify, or distribute it.

