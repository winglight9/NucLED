# Changelog

## 1.0.4

- Move the next scheduled action hint directly below the LED master switch, with explicit wording such as “今天 21:30 将关闭 LED”.
- Commit time-field edits and clear the blue text selection after a short idle pause.
- Render the Hades skull as a monochrome system template at standard menu-bar icon size.


## 1.0.3

- Try registering the main app when Service Management reports `.notFound`, instead of treating that initial state as a reinstall error.

## 1.0.2

- Replaced the SwiftUI `MenuBarExtra` click path with an AppKit `NSStatusItem` and `NSPopover` hosting the same SwiftUI controls.
- Added unified log entries for status item setup and click/open/close actions.
- Kept the skull status icon and LED state tint.

## 1.0.1

- Enlarged the skull status item's hit target and exposed an accessibility label.

## 1.0.0

- Initial menu bar app with manual LED control, daily scheduling, and optional login launch.
- Added the Hades Canyon WMI kernel driver and readback-verified state changes.
