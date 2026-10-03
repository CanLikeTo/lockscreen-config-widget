# Lock timeout

An Omarchy bar widget for temporarily extending automatic screen locking at home without changing your configured default.

![Lock timeout popup with Default, 5 min, and 10 min choices](preview.png)

## Usage

Click the lock icon in the bar and choose:

| Choice | Automatic lock timeout |
| --- | --- |
| Default | Current configured timeout, displayed in seconds |
| 5 min | 300 seconds |
| 10 min | 600 seconds |

Default and 5 min remain distinct choices even when your configured default is 300 seconds. A checkmark identifies the selection; hovering does not apply it. The bar icon uses the theme accent for an explicit duration.

Up/Down or j/k navigate, Enter/Space apply, Escape dismisses, and Tab/Shift-Tab switch bar popups. All monitor instances share the same selection.

**Selections are memory-only.** Logout/reboot, shell restart, plugin disable, and global plugin reload reset to Default. Moving the widget does not reset it. Default follows later intentional changes to your configuration.

Only automatic screen locking changes. Screensaver timing, idle inhibitors, stay-awake, suspend, and manual locking remain unchanged. To avoid changing an already-armed deadline, choices are disabled during an active idle cycle; activity/screensaver dismissal must clear that cycle first.

## Requirements and compatibility

- Omarchy Quattro with its stock `omarchy.idle` service and existing Quickshell installation.
- Tested on Omarchy **4.0.3rc4-1**, Hyprland/Wayland, with a top bar on one monitor.
- No additional packages, network access, accounts, daemons, or build step are required by the plugin.

The controller uses the stock idle service's writable `shell` input and existing timeout bindings. This is an inspected implementation seam, **not a public timeout-override API**. Reverify after Omarchy changes the idle service. Missing/incompatible services or foreign ownership reject selections and show a status message; the plugin does not replace the idle implementation.

## Installation

For a published repository, use `omarchy plugin add` with its public GitHub repository URL and `--enable`. Review the source first: Omarchy plugins execute unsandboxed in the shell, and a longer lock timeout increases unattended access time.

To install from an inspected local checkout, first back up `~/.config/omarchy/shell.json`. If the destination already exists, confirm it belongs to this plugin and preserve any local edits before replacing files. From the repository root:

```sh
omarchy plugin validate "$PWD"
mkdir -p "$HOME/.config/omarchy/plugins/local.lockscreen-config"
cp manifest.json Service.qml Widget.qml "$HOME/.config/omarchy/plugins/local.lockscreen-config/"
omarchy-shell shell rescanPlugins
omarchy plugin enable local.lockscreen-config --section right
```

The supported enable command preserves other widgets/settings. Choose placement with `omarchy bar move`; for example, when `omarchy.power` is present:

```sh
omarchy bar move local.lockscreen-config --section right --after omarchy.power
```

For local code updates, repeat validation, the three-file copy, and rescan. For git-managed installs, use `omarchy plugin update local.lockscreen-config`. Reloading resets the selection. No edits to `/usr/share/omarchy/` are needed.

## Disable or remove

```sh
omarchy plugin disable local.lockscreen-config
omarchy plugin remove local.lockscreen-config
```

Disabling or removing restores the canonical timeout while the plugin still owns the idle input; it does not overwrite another controller's replacement. The remove command manages the plugin directory and layout entry. It does not remove unrelated plugins or reset the bar.

## Configuration and permissions

The plugin ID is `local.lockscreen-config`; there are no custom settings. The controller shallow-copies the shell configuration into a service-local view, replacing only `idle.lock`. It never mutates canonical `shellConfig`, writes configuration or selection state, invokes commands, or accesses the network. Normal Omarchy install/enable/move/remove commands manage the plugin files and bar entry separately.

This is not a lock-security enhancement. Existing inhibitors or stay-awake state can still prevent automatic locking. Marketplace listing or automated checks are not a security audit or guarantee.

## Verification

Live checks exercised all three keyboard choices, mouse selection, checkmarks, popup anchoring, Escape/outside dismissal, and effective stock idle timing bindings. With screensaver 150, selecting 10 min produced lock 600 / lockDelay 450; Default and 5 min produced 300 / 150. Canonical and disk lock remained 300 during a real bar move/save, and all existing widget entries/settings were restored exactly. Disable and global reload restored Default.

An isolated real-controller smoke checked invalid choices, missing services, foreign owners, active cycles, destruction restoration, and preservation of a foreign replacement. An unattended timed lock event, logout/reboot, and additional monitors were not exercised.

## License and publication

[MIT](LICENSE). Public attribution is **Lock timeout contributors**; no personal author name is included.

See [PUBLISHING.md](PUBLISHING.md) for the official marketplace requirements, chosen category/tags, release checks, and submission process.
