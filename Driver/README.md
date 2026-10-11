# NUC LED kernel bridge

This is the privileged bridge for the Hades Canyon (`NUC8i7HVK` / `NUC8i7HNK`)
LED WMI interface. macOS user applications cannot evaluate ACPI methods
directly, so the menu bar app talks to a narrowly-scoped IOKit user client; the
driver evaluates only the target WMI method on the verified `AMW0` device.

## Current build status

`make -C Driver bundle` compiles and links an Intel `x86_64` Mach-O kext bundle
into `Driver/.build/NUCLEDDriver.kext`. It uses the SDK's `libkmodc++.a` and
`libkmod.a` and embeds the standard `KMOD_INFO`, `_realmain`, and `_antimain`
metadata. The command does not install or load the bundle. `make -C Driver
objects` compiles only. The generated bundle is unsigned.

On the development host, the user approved and restarted after installing the
bundle at `/Library/Extensions/NUCLEDDriver.kext`. `kmutil showloaded` and
IORegistry confirmed the service active. A live WMI test disabled all six
present zones, read back indicator ID 6 for each, then restored the original
IDs (0, 0, 0, 1, 2, 5) and read them back successfully. This verifies the
firmware mode writes and readback path; it does not measure visible light output.
The host already had Kext Signing disabled in its custom SIP configuration;
that configuration was not changed. `kmutil print-diagnostics` reported a bad
code signature for the unsigned bundle, so this result is specific to this
host's existing configuration and is not a general loadability claim.

## Target validation and methods

The personality's initial candidate match is `IOACPIPlatformDevice` / HID
`PNP0C14`. At runtime, `NUCLEDDriver::start` independently requires the
provider's name in `gIOACPIPlane` to be exactly `AMW0` and `_UID == 0`, then
validates a `_WDG` record with GUID `8C5DA44C-CDC3-46B3-8619-4E26D34390B7`,
object ID `AA`, one instance, method bit set, and string/event bits clear. It
also validates `WMAA` and performs a read-only `QUERYLED` call before publishing
the service. This prevents binding to unrelated WMI providers such as `WTBT`.

The WMI requests implemented are limited to:

- Method 3 `QUERYLED` (actions 0 and 2): enumerate present zones and supported
  indicator IDs.
- Method 4 `NEWGETLEDSTATUS` (action 0): read the current indicator ID.
- Method 5 `SETINDICATOR`: change one zone's indicator ID.

Zones are constrained to IDs 0 through 6 and indicator IDs 0 through 6. The
driver caches each zone's supported-indicator bitmask and rejects attempts to
select an unsupported indicator. There is no raw method invocation selector,
no arbitrary ACPI method name, and no color/brightness configuration path.

## Fixed IOKit user-client wire protocol

`IOServiceMatching("NUCLEDDriver")` and user-client type `0` open the service.
All calls use `IOConnectCallStructMethod`. Integers are single bytes; each
structure is exactly four bytes:

| Selector | Input | Output |
| --- | --- | --- |
| `0` Read inventory | zero bytes | `{ version=1, presentMask, disableSupportedMask, powerStateSupportedMask }` |
| `1` Read indicator | `{ zone, 0, 0, 0 }` | `{ indicatorID, 0, 0, 0 }` |
| `2` Set indicator | `{ zone, indicatorID, 0, 0 }` | zero bytes |

Calls are restricted to local users. Firmware and ACPI errors are returned as
IOKit errors, and successful writes are still followed by a readback in the
Swift controller.

## Safe off/on transaction in the app

Off first reads the complete inventory and current indicator for every present
zone. It refuses the operation if any present zone lacks the Disable mode. The
app atomically writes a mode-only JSON snapshot under the current user's
Application Support directory before the first firmware write, then disables
each non-disabled zone and verifies it by reading it back. A partial failure
causes rollback and readback; the snapshot remains if rollback cannot be
confirmed.

On normally restores a validated snapshot. If the computer starts with every
zone disabled and no snapshot exists, the app journals that state, requires
every present zone to advertise Power State indicator ID 0 before writing,
selects that BIOS policy, and verifies each mode. A partial failure is rolled
back. Reading indicator ID 0 confirms the firmware mode, not that a physical
LED is emitting light (BIOS brightness may be zero). Other currently active
modes are never overwritten by this first-on fallback. If a
restore was interrupted, it can resume when every zone is either still disabled
or already at its snapshotted mode. It refuses to overwrite a third,
externally-changed state. It does not attempt to recreate color or brightness
data because changing indicator modes does not edit those configuration values.

## Source and licensing boundary

The driver code here is newly written and does not copy code from
[`nomego/intel_nuc_led`](https://github.com/nomego/intel_nuc_led), which is
GPL-2.0. That project and Intel's NUC WMI interface description were consulted
for the published method numbering, argument meaning, indicator IDs, and
firmware result conventions. The implementation boundary here is a fresh
IOKit-to-ACPI adapter plus a fixed, limited user-client ABI; no upstream source
file or GPL implementation fragment is included.

## Build command

From the repository root:

```sh
make -C Driver objects
```

There is deliberately no install/load target in this Makefile. Installing on
another system still requires checking its kernel ABI, signing policy, user
approval, and reboot requirements.
