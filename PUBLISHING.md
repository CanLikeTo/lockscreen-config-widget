# Marketplace publication

Target: [Omarchy Plugin Marketplace](https://github.com/omacom/omarchy-plugin-marketplace), following its [submission guide](https://github.com/omacom/omarchy-plugin-marketplace/blob/main/SUBMISSION.md) and [security policy](https://github.com/omacom/omarchy-plugin-marketplace/blob/main/SECURITY.md).

## Listing metadata

- Title: **[Plugin]: Lock timeout**
- Plugin ID: `local.lockscreen-config`
- Category: **System**
- Tags: **bar, security, quickshell**
- Author: **Lock timeout contributors**
- License: **MIT**
- Optional preview: root `preview.png`, cropped from the actual popup without desktop content.

The ID is a permanent marketplace identifier. It was absent from current listings and retired IDs during preparation; that check is not a reservation. Check again before submitting, and do not reuse an ID from a retired listing. Any ID change must also migrate `Widget.qml`, documentation, and installed bar references.

## Release checks

From the repository root on a compatible Omarchy session:

```sh
omarchy plugin validate "$PWD"
omarchy-shell shell summon local.lockscreen-config '{}'
```

Run the ownership regression suite with QtTest available:

```sh
/usr/lib/qt6/bin/qmltestrunner -platform offscreen -input tests
```

Exercise Default, 5 min, and 10 min through the popup. Compare:

```sh
omarchy-shell idle status
omarchy-shell shell listShellConfig
```

With 10 min selected, `shell.json` `idle.lock` is 600 for the session. The previous lock is recorded in `~/.local/state/omarchy/local.lockscreen-config.json` and restored on Default, disable, or reload. Do not expect `shell.json` to keep the configured lock while an override is active. Finish enabled at Default so the configured lock is restored. An armed idle cycle keeps its deadline, and the new timeout applies on the next cycle, except when restore writes a configured `idle.lock` of 0: that suppresses the pending lock because the stock timer checks live `lockEnabled`. Do not claim every restore keeps an armed deadline. The README records the verification limits; do not claim a timed lock or additional-monitor result unless observed.

Keep exactly one root `manifest.json`, its declared `Service.qml` and `Widget.qml`, `LockTimeout.js`, root README/LICENSE, this guide, and the preview. Keep the ownership regression suite under `tests/`; it is not a runtime entry point. Do not commit credentials, personal desktop screenshots, configuration backups, generated smoke drivers, or symlinks. Do not add installer hooks: the standard Omarchy commands already manage installation and removal.

## Host the repository

The marketplace accepts one plugin per **public GitHub repository** with the manifest at its root. A local checkout alone cannot be submitted. Review the files and commit them before creating/pushing the repository. If no remote exists, this command creates a public repository under the authenticated GitHub account and pushes existing commits:

```sh
gh repo create lockscreen-config-widget --public --source=. --remote=origin --push
```

Run it only when you intend to make the code public. If a remote already exists, use that repository rather than creating a duplicate. Confirm the public root URL and the exact pushed commit:

```sh
gh repo view --json url,visibility
git rev-parse HEAD
```

The repository URL must be the root URL, without `/tree/main`, a trailing slash, or a file path. Once hosted, a checked-out copy can derive the real install URL without hardcoding an owner:

```sh
repo_url="$(gh repo view --json url --jq .url)"
omarchy plugin add "$repo_url" --enable
```

`gh` is only a publishing helper, not a plugin runtime dependency. Omarchy install/update commands obtain mutable upstream code; marketplace snapshot verification does not cover a different installed commit.

## Submit for review

Open the official [plugin submission form](https://github.com/omacom/omarchy-plugin-marketplace/issues/new?template=submit-plugin.yml). Enter the actual public root URL and the category/tags above. Suggested maintainer notes:

> Temporarily selects the automatic lock timeout from the bar by writing `idle.lock` in the existing user shell.json for the session and restoring it on Default, disable, remove, reload, restart, and the next start after a crash. Choices are configured Default, 5 min, and 10 min. Screensaver timing is preserved. An armed idle cycle keeps its deadline, except that restoring a configured idle.lock of 0 suppresses a pending lock because the stock timer checks lockEnabled when it fires. Targets Omarchy 4.5. No additional runtime dependencies, network access, command execution, or bundled executable binaries. Preview shows only the actual plugin popup.

Before submitting, the owner must confirm every official checklist statement, including permission to publish the code and preview assets. Do not auto-check ownership or submit on the owner's behalf without explicit approval. There is no submission issue or marketplace approval implied by this package.

Automated compatibility/security-baseline checks bind to an exact commit. A maintainer must apply `approved-and-verified` after reviewing fresh matching results before initial publication. Keep the branch unchanged while that review is pending; follow bot feedback on the existing issue rather than creating duplicates. These checks are not a security audit, certification, warranty, or endorsement.
