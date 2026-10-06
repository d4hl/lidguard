# lidguard

DMS plugin: lid close = screen off instead of suspend.

Toggle in control center (also works as a bar widget). Off = suspend (logind default).

**Note:** while enabled, closing the lid powers off **all** displays, including external ones — intended for laptop-on-the-go use, not docked setups.

**Requires:** systemd user manager (`systemd-run`, `systemd-inhibit`, `systemctl --user`) and logind.

## Install

```
dms plugins install lidguard
```

---

Co-written with AI.
