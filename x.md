## Type of Change

- [x] New plugin

## New Plugin Checklist

- [x] I have read and followed CONTRIBUTING.md.
- [x] This plugin does not duplicate an existing plugin (no lid-guard plugin in the registry yet).
- [x] The id in the JSON is in camelCase and exactly matches plugin.json in the plugin repository.
- [x] I have validated locally (`python3 .github/generate.py --validate` and `python3 .github/validate_links.py`).
- [x] I understand that non-compliant submissions may be rejected or closed without explanation.

## Description

Lid Guard — a control center / DankBar toggle that takes a `systemd-inhibit` lock on `handle-lid-switch`: closing the lid powers the screens off instead of suspending. With the toggle off, lid behavior is the logind default
(suspend). Co-written with AI.

## Realisation

- **State of truth** — the transient user unit `lidguard.service` (`systemd-run --user --unit=lidguard systemd-inhibit --what=handle-lid-switch sleep infinity`), read via `systemctl --user is-active`; no local flags
persisted anywhere.
- **Fully event-driven, zero polling** — two long-lived `dbus-monitor` processes (part of the base dbus package, no extra dependencies):
 - session bus: `PropertiesChanged` on `/org/freedesktop/systemd1/unit/lidguard_2eservice` → unit active/inactive;
 - system bus: logind `LidClosed` property changes → kernel lid events.
- **Screen power** — DMS built-in `CompositorService.powerOffMonitors()/powerOnMonitors()` (no `dms dpms` CLI calls, no timeout workarounds), so no compositor-specific APIs are touched.
- Persistent across `dms restart` and shell restarts by design; the unit is named and stoppable (`systemctl --user stop lidguard.service`).

## Summary

- **id / name**: `lidguard` / `Lid Guard` (matches plugin.json)
- **capabilities**: `control-center`, `dankbar-widget` (toggle tile in CC, icon pill in the bar; click anywhere on the pill toggles)
- **category**: system
- **settings**: included (`LidGuardSettings.qml`, `settings_read`/`settings_write`)
- **dependencies**: `systemd` user manager (`systemd-run`, `systemd-inhibit`, `systemctl --user`) + logind; `dbus-monitor` ships with base dbus
- **compositors**: `any` (via DMS `CompositorService`) — **tested on Hyprland**; no compositor-specific code is used
- **distro**: `any` (developed and tested on NixOS)
- **Behavior note**: while enabled, closing the lid powers off **all** displays, including external ones — intended for laptop-on-the-go use, documented in the README


