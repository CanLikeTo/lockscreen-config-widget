import QtQuick
import QtTest
import "../LockTimeout.js" as LockTimeout

TestCase {
  id: test
  name: "LockTimeoutOwnership"

  function shellText(config) {
    return JSON.stringify(config, null, 2) + "\n"
  }

  function baseConfig(lock) {
    var idle = { screensaver: 150 }
    if (lock !== undefined) idle.lock = lock
    return {
      version: 1,
      custom: "keep",
      flag: false,
      count: 0,
      idle: idle,
      bar: {
        position: "top",
        background: "opaque",
        layout: {
          left: [{ id: "omarchy.menu" }],
          right: [{ id: "omarchy.power", settings: { a: 1 } }, { id: "local.lockscreen-config" }]
        }
      },
      dock: { pinned: ["foot", "chromium"] },
      plugins: [{ id: "local.lockscreen-config" }]
    }
  }

  function action(result, type) {
    var actions = result.actions || []
    for (var i = 0; i < actions.length; i++) {
      if (actions[i].type === type) return actions[i]
    }
    return null
  }

  function shellWrite(result) {
    var found = action(result, "writeShell")
    return found ? found.text : ""
  }

  function apply(shell, state, result) {
    var nextShell = shell
    var nextState = state
    var actions = result.actions || []
    for (var i = 0; i < actions.length; i++) {
      if (actions[i].type === "writeShell") nextShell = actions[i].text
      else if (actions[i].type === "writeState") nextState = actions[i].text
      else if (actions[i].type === "clearState") nextState = ""
    }
    return { shell: nextShell, state: nextState }
  }

  function assertNoShellWrite(result) {
    verify(action(result, "writeShell") === null)
  }

  function assertPreserved(beforeText, afterText, expectedLock, lockPresent) {
    verify(afterText !== "")
    compare(afterText, JSON.stringify(JSON.parse(afterText), null, 2) + "\n")
    var before = JSON.parse(beforeText)
    var after = JSON.parse(afterText)
    compare(after.version, 1)
    compare(after.custom, before.custom)
    compare(after.flag, false)
    compare(after.count, 0)
    compare(after.bar.position, before.bar.position)
    compare(after.bar.background, before.bar.background)
    compare(after.bar.layout.left[0].id, "omarchy.menu")
    compare(after.bar.layout.right[0].id, "omarchy.power")
    compare(after.bar.layout.right[0].settings.a, 1)
    compare(after.bar.layout.right[1].id, "local.lockscreen-config")
    compare(after.dock.pinned[0], "foot")
    compare(after.dock.pinned[1], "chromium")
    compare(after.plugins[0].id, "local.lockscreen-config")
    compare(after.idle.screensaver, before.idle.screensaver)
    if (lockPresent) compare(after.idle.lock, expectedLock)
    else verify(!Object.prototype.hasOwnProperty.call(after.idle, "lock"))
  }

  function test_secondsFromConfigMatchesStockParser() {
    compare(LockTimeout.secondsFromConfig(undefined, 300), 300)
    compare(LockTimeout.secondsFromConfig(null, 300), 0)
    compare(LockTimeout.secondsFromConfig(-1, 300), 300)
    compare(LockTimeout.secondsFromConfig(0, 300), 0)
    compare(LockTimeout.secondsFromConfig(1.9, 300), 1)
    compare(LockTimeout.secondsFromConfig("600", 300), 600)
    compare(LockTimeout.secondsFromConfig("nope", 300), 300)
    compare(LockTimeout.secondsFromConfig(Infinity, 300), 300)
  }

  function test_version1ObjectRequired() {
    verify(LockTimeout.parseShell('{"version":1}') !== null)
    verify(LockTimeout.parseShell('{"version":1.0}') !== null)
    verify(LockTimeout.parseShell("") === null)
    verify(LockTimeout.parseShell("   ") === null)
    verify(LockTimeout.parseShell("{") === null)
    verify(LockTimeout.parseShell("[]") === null)
    verify(LockTimeout.parseShell("null") === null)
    verify(LockTimeout.parseShell('{"version":"1"}') === null)
    verify(LockTimeout.parseShell('{"version":2}') === null)
    verify(LockTimeout.parseShell("{}") === null)
    verify(LockTimeout.parseShell('{"version":1,"idle":[]}') === null)
  }

  function test_explicit300StaysDistinctFromDefault() {
    var shell = shellText(baseConfig(300))
    var selected = LockTimeout.select(shell, null, "300")
    verify(selected.ok)
    compare(selected.choice, "300")
    verify(selected.choice !== "default")
    verify(selected.memory.owned)
    compare(selected.memory.choice, "300")
    compare(selected.configuredLockSeconds, 300)
    compare(selected.effectiveLockSeconds, 300)
    compare(selected.actions[0].type, "writeState")
    compare(selected.actions[1].type, "writeShell")

    var stayed = LockTimeout.select(shell, null, "default")
    compare(stayed.choice, "default")
    compare(stayed.actions.length, 0)
    compare(stayed.effectiveLockSeconds, 300)
  }

  function test_selectPreservesOtherKeysAndScreensaver() {
    var shell = shellText(baseConfig(60))
    var selected = LockTimeout.select(shell, null, "600")
    verify(selected.ok)
    compare(selected.choice, "600")
    compare(selected.configuredLockSeconds, 60)
    compare(selected.effectiveLockSeconds, 600)
    compare(selected.actions[0].type, "writeState")
    compare(selected.actions[1].type, "writeShell")
    assertPreserved(shell, shellWrite(selected), 600, true)
    compare(JSON.parse(shellWrite(selected)).idle.lock, 600)
    verify(typeof JSON.parse(shellWrite(selected)).idle.lock === "number")

    var state = JSON.parse(selected.actions[0].text)
    compare(state.owned, true)
    compare(state.choice, "600")
    compare(state.lockExisted, true)
    compare(state.idleExisted, true)
    compare(state.originalSeconds, 60)
  }

  function test_switchChoiceKeepsOriginalSnapshot() {
    var shell = shellText(baseConfig(60))
    var first = LockTimeout.select(shell, null, "600")
    var applied = apply(shell, "", first)
    var second = LockTimeout.select(applied.shell, first.memory, "300")
    verify(second.ok)
    compare(second.choice, "300")
    compare(second.memory.originalSeconds, 60)
    compare(second.configuredLockSeconds, 60)
    compare(second.effectiveLockSeconds, 300)
    compare(JSON.parse(shellWrite(second)).idle.lock, 300)
    compare(JSON.parse(shellWrite(second)).idle.screensaver, 150)
  }

  function test_defaultRestoresPreviousLock() {
    var shell = shellText(baseConfig(60))
    var selected = LockTimeout.select(shell, null, "600")
    var applied = apply(shell, "", selected)
    var restored = LockTimeout.select(applied.shell, selected.memory, "default")
    verify(restored.ok)
    compare(restored.choice, "default")
    compare(restored.actions[0].type, "writeShell")
    compare(restored.actions[1].type, "clearState")
    assertPreserved(shell, shellWrite(restored), 60, true)
    compare(restored.configuredLockSeconds, 60)
    compare(restored.effectiveLockSeconds, 60)
  }

  function test_absentLockIsRemovedAndCreatedIdleIsDeleted() {
    var created = shellText({
      version: 1,
      custom: "keep",
      bar: { position: "bottom", layout: { right: [{ id: "omarchy.power" }] } }
    })
    var selected = LockTimeout.select(created, null, "600")
    compare(selected.memory.lockExisted, false)
    compare(selected.memory.idleExisted, false)
    compare(selected.memory.originalSeconds, 300)
    var applied = apply(created, "", selected)
    compare(JSON.parse(applied.shell).idle.lock, 600)

    var restored = LockTimeout.recover(applied.shell, applied.state)
    compare(restored.actions[0].type, "writeShell")
    compare(restored.actions[1].type, "clearState")
    var parsed = JSON.parse(shellWrite(restored))
    verify(!Object.prototype.hasOwnProperty.call(parsed, "idle"))
    compare(parsed.custom, "keep")
    compare(parsed.bar.position, "bottom")
    compare(parsed.bar.layout.right[0].id, "omarchy.power")
  }

  function test_absentLockKeepsPreexistingIdleFields() {
    var shell = shellText(baseConfig(undefined))
    var selected = LockTimeout.select(shell, null, "600")
    compare(selected.memory.lockExisted, false)
    compare(selected.memory.idleExisted, true)
    var applied = apply(shell, "", selected)
    var restored = LockTimeout.recover(applied.shell, applied.state)
    var parsed = JSON.parse(shellWrite(restored))
    verify(!Object.prototype.hasOwnProperty.call(parsed.idle, "lock"))
    compare(parsed.idle.screensaver, 150)
    compare(parsed.bar.layout.right[1].id, "local.lockscreen-config")
  }

  function test_userAddedIdleFieldSurvivesRestoreOfCreatedIdle() {
    var created = shellText({ version: 1, custom: "keep" })
    var selected = LockTimeout.select(created, null, "300")
    var applied = apply(created, "", selected)
    var during = JSON.parse(applied.shell)
    during.idle.screensaver = 90
    var restored = LockTimeout.recover(shellText(during), applied.state)
    var parsed = JSON.parse(shellWrite(restored))
    verify(!Object.prototype.hasOwnProperty.call(parsed.idle, "lock"))
    compare(parsed.idle.screensaver, 90)
    compare(parsed.custom, "keep")
  }

  function test_zeroLockIsRestoredNotDeleted() {
    var shell = shellText(baseConfig(0))
    var selected = LockTimeout.select(shell, null, "600")
    compare(selected.configuredLockSeconds, 0)
    compare(selected.memory.originalSeconds, 0)
    compare(selected.memory.lockExisted, true)
    var applied = apply(shell, "", selected)
    var restored = LockTimeout.select(applied.shell, selected.memory, "default")
    compare(JSON.parse(shellWrite(restored)).idle.lock, 0)
    compare(JSON.parse(shellWrite(restored)).idle.screensaver, 150)
  }

  function test_foreignLockIsNotOverwrittenOnRestore() {
    var memory = {
      owned: true,
      choice: "600",
      lockExisted: true,
      idleExisted: true,
      originalSeconds: 60
    }
    var foreign = shellText(baseConfig(120))
    var recovered = LockTimeout.recover(foreign, LockTimeout.serializeState(memory))
    assertNoShellWrite(recovered)
    verify(action(recovered, "clearState") !== null)
    compare(recovered.choice, "default")
    compare(recovered.configuredLockSeconds, 120)

    var dropped = LockTimeout.select(foreign, memory, "default")
    assertNoShellWrite(dropped)
    verify(action(dropped, "clearState") !== null)
    compare(dropped.configuredLockSeconds, 120)
  }

  function test_newChoiceAfterForeignEditSnapshotsForeignLock() {
    var memory = {
      owned: true,
      choice: "600",
      lockExisted: true,
      idleExisted: true,
      originalSeconds: 60
    }
    var foreign = shellText(baseConfig(120))
    var selected = LockTimeout.select(foreign, memory, "300")
    verify(selected.ok)
    compare(selected.memory.originalSeconds, 120)
    compare(JSON.parse(shellWrite(selected)).idle.lock, 300)
    compare(JSON.parse(shellWrite(selected)).idle.screensaver, 150)
    var applied = apply(foreign, "", selected)
    var restored = LockTimeout.select(applied.shell, selected.memory, "default")
    compare(JSON.parse(shellWrite(restored)).idle.lock, 120)
  }

  function test_missingOrInvalidFileIsNotWritten() {
    var samples = ["", "   ", "{", "[]", "null", '{"version":2}', '{"version":"1"}', "{}", '{"version":1,"idle":[]}']
    for (var i = 0; i < samples.length; i++) {
      var selected = LockTimeout.select(samples[i], null, "600")
      verify(!selected.ok)
      assertNoShellWrite(selected)
      verify(action(selected, "writeState") === null)
      compare(selected.statusText, "Shell configuration unavailable.")
      verify(!selected.canSelect)

      var memory = {
        owned: true,
        choice: "600",
        lockExisted: true,
        idleExisted: true,
        originalSeconds: 60
      }
      var recovered = LockTimeout.recover(samples[i], LockTimeout.serializeState(memory))
      assertNoShellWrite(recovered)
    }
  }

  function test_ownWriteAndBarMoveDoNotLookForeign() {
    var shell = shellText(baseConfig(60))
    var selected = LockTimeout.select(shell, null, "600")
    var applied = apply(shell, "", selected)
    var echo = LockTimeout.reconcile(applied.shell, selected.memory)
    compare(echo.choice, "600")
    compare(echo.actions.length, 0)
    compare(echo.configuredLockSeconds, 60)
    compare(echo.effectiveLockSeconds, 600)

    var moved = JSON.parse(applied.shell)
    moved.bar.position = "bottom"
    moved.bar.layout.right.push({ id: "omarchy.audio" })
    moved.plugins.push({ id: "other.plugin" })
    var reconciled = LockTimeout.reconcile(shellText(moved), selected.memory)
    compare(reconciled.choice, "600")
    compare(reconciled.actions.length, 0)
    compare(reconciled.memory.originalSeconds, 60)
  }

  function test_stringLockIsForeignEvenWhenParsedSecondsMatch() {
    var memory = {
      owned: true,
      choice: "600",
      lockExisted: true,
      idleExisted: true,
      originalSeconds: 60
    }
    var shell = shellText(baseConfig("600"))
    var reconciled = LockTimeout.reconcile(shell, memory)
    compare(reconciled.choice, "default")
    assertNoShellWrite(reconciled)
    verify(action(reconciled, "clearState") !== null)
  }

  function test_deletedLockIsForeignWhenFallbackEqualsChoice() {
    var memory = {
      owned: true,
      choice: "300",
      lockExisted: true,
      idleExisted: true,
      originalSeconds: 60
    }
    var shell = shellText(baseConfig(undefined))
    var reconciled = LockTimeout.reconcile(shell, memory)
    compare(reconciled.choice, "default")
    assertNoShellWrite(reconciled)
    compare(reconciled.configuredLockSeconds, 300)
  }

  function test_crashBetweenStateAndShellDoesNotRestore() {
    var shell = shellText(baseConfig(60))
    var selected = LockTimeout.select(shell, null, "600")
    compare(selected.actions[0].type, "writeState")
    compare(selected.actions[1].type, "writeShell")
    var crashed = { shell: shell, state: selected.actions[0].text }
    var recovered = LockTimeout.recover(crashed.shell, crashed.state)
    assertNoShellWrite(recovered)
    verify(action(recovered, "clearState") !== null)
    compare(JSON.parse(crashed.shell).idle.lock, 60)
  }

  function test_startupAndDestructionRestoreAreIdempotent() {
    var shell = shellText(baseConfig(60))
    var selected = LockTimeout.select(shell, null, "600")
    var applied = apply(shell, "", selected)
    var first = LockTimeout.recover(applied.shell, applied.state)
    var once = apply(applied.shell, applied.state, first)
    compare(JSON.parse(once.shell).idle.lock, 60)
    compare(once.state, "")
    var second = LockTimeout.recover(once.shell, once.state)
    compare(second.actions.length, 0)
    assertNoShellWrite(second)
    compare(second.choice, "default")

    var again = LockTimeout.recover(once.shell, LockTimeout.serializeState(null))
    compare(again.actions.length, 0)
  }

  function test_fieldBoundaryPreservesAbsentAndZeroLock() {
    var shell = shellText(baseConfig(undefined))
    var selected = LockTimeout.selectFields(shell, false, "default", false, false, 0, "600")
    compare(selected.memory.lockExisted, false)
    compare(selected.memory.idleExisted, true)
    compare(selected.memory.originalSeconds, 300)
    var applied = apply(shell, "", selected)
    var restored = LockTimeout.recoverFields(applied.shell, true, "600", false, true, 300)
    var parsed = JSON.parse(shellWrite(restored))
    verify(!Object.prototype.hasOwnProperty.call(parsed.idle, "lock"))
    compare(parsed.idle.screensaver, 150)

    var zeroShell = shellText(baseConfig(0))
    var zeroSelected = LockTimeout.selectFields(zeroShell, false, "default", false, false, 0, "300")
    compare(zeroSelected.memory.lockExisted, true)
    compare(zeroSelected.memory.originalSeconds, 0)
    var zeroApplied = apply(zeroShell, "", zeroSelected)
    var zeroRestored = LockTimeout.recoverFields(zeroApplied.shell, true, "300", true, true, 0)
    compare(JSON.parse(shellWrite(zeroRestored)).idle.lock, 0)
    compare(JSON.parse(shellWrite(zeroRestored)).idle.screensaver, 150)
  }

  function test_unreadableRecoverDoesNotCreateShellJson() {
    var state = LockTimeout.serializeState({
      owned: true,
      choice: "600",
      lockExisted: false,
      idleExisted: false,
      originalSeconds: 300
    })
    var recovered = LockTimeout.recover("", state)
    assertNoShellWrite(recovered)
    verify(action(recovered, "clearState") === null)
    verify(action(recovered, "writeState") === null)
    compare(recovered.statusText, "Shell configuration unavailable.")
  }

  function test_invalidChoiceDoesNotWrite() {
    var shell = shellText(baseConfig(60))
    var result = LockTimeout.select(shell, null, "900")
    verify(!result.ok)
    compare(result.actions.length, 0)
    compare(result.choice, "default")
    verify(result.canSelect)
    compare(result.statusText, "")
  }

  function assertRawLock(text, raw) {
    var written = JSON.parse(text).idle.lock
    if (raw === null) {
      verify(written === null)
      verify(text.indexOf('"lock": null') !== -1)
      verify(written !== 0)
      return
    }
    compare(written, raw)
    compare(typeof written, typeof raw)
    if (typeof raw === "string") verify(text.indexOf('"lock": "60"') !== -1)
    if (raw === 60.9) {
      verify(text.indexOf("60.9") !== -1)
      verify(written !== 60)
    }
  }

  function test_switchJournalAppliedAloneRestoresEitherSide() {
    var shell = shellText(baseConfig(60))
    var first = LockTimeout.select(shell, null, "600")
    var applied = apply(shell, "", first)
    var second = LockTimeout.select(applied.shell, first.memory, "300")
    compare(second.actions[0].type, "writeState")
    var journal = second.actions[0].text
    var recorded = JSON.parse(journal)
    compare(recorded.choice, "300")
    compare(recorded.pendingChoice, "300")
    compare(recorded.appliedChoice, "600")
    compare(recorded.originalSeconds, 60)

    var recovered = LockTimeout.recover(applied.shell, journal)
    compare(JSON.parse(shellWrite(recovered)).idle.lock, 60)
    verify(action(recovered, "clearState") !== null)

    var foreign = LockTimeout.recover(shellText(baseConfig(120)), journal)
    assertNoShellWrite(foreign)
    verify(action(foreign, "clearState") !== null)

    var originalDisk = LockTimeout.recover(shell, journal)
    assertNoShellWrite(originalDisk)

    var completed = apply(applied.shell, "", second)
    var later = LockTimeout.recover(completed.shell, completed.state)
    compare(JSON.parse(shellWrite(later)).idle.lock, 60)
  }

  function test_pendingJournalResolvesBeforeSelection() {
    var shell = shellText(baseConfig(60))
    var selected = LockTimeout.select(shell, null, "600")
    var applied = apply(shell, "", selected)
    var journal = applied.state
    var pending = LockTimeout.recover("{", journal)
    verify(pending.recoveryPending)
    verify(!pending.canSelect)
    verify(action(pending, "clearState") === null)
    assertNoShellWrite(pending)

    var readable = shellText(baseConfig(600))
    var resolved = LockTimeout.shellChanged(
      readable, false, "default", true, true, 600, 600, true, pending.recoveryPending, journal)
    verify(action(resolved, "writeShell") !== null)
    compare(JSON.parse(shellWrite(resolved)).idle.lock, 60)
    compare(resolved.configuredLockSeconds, 60)
    verify(!(resolved.canSelect && resolved.configuredLockSeconds === 600))
    verify(!resolved.recoveryPending)

    var after = apply(readable, journal, resolved)
    var next = LockTimeout.select(after.shell, resolved.memory, "300")
    compare(next.memory.originalSeconds, 60)
    compare(next.configuredLockSeconds, 60)

    var still = LockTimeout.shellChanged(
      "{", false, "default", false, false, 600, null, false, true, journal)
    verify(!still.canSelect)
    verify(still.recoveryPending)
    verify(action(still, "clearState") === null)
    assertNoShellWrite(still)
  }

  function test_shellChangedWithoutPendingKeepsAppliedChoice() {
    var shell = shellText(baseConfig(60))
    var selected = LockTimeout.select(shell, null, "600")
    var applied = apply(shell, "", selected)
    var echoed = LockTimeout.shellChanged(
      applied.shell, true, "600", true, true, 60, 60, true, false, applied.state)
    compare(echoed.choice, "600")
    compare(echoed.actions.length, 0)
    verify(echoed.canSelect)
    verify(!echoed.recoveryPending)
  }

  function test_restoreWritesRawLockValue() {
    var samples = [60.9, "60", null]
    for (var i = 0; i < samples.length; i++) {
      var raw = samples[i]
      var shell = shellText(baseConfig(raw))
      var selected = LockTimeout.select(shell, null, "600")
      compare(selected.configuredLockSeconds, LockTimeout.secondsFromConfig(raw, 300))
      var recorded = JSON.parse(selected.actions[0].text).originalLock
      if (raw === null) verify(recorded === null)
      else {
        compare(recorded, raw)
        compare(typeof recorded, typeof raw)
      }
      compare(JSON.parse(shellWrite(selected)).idle.lock, 600)
      verify(typeof JSON.parse(shellWrite(selected)).idle.lock === "number")

      var applied = apply(shell, "", selected)
      assertRawLock(shellWrite(LockTimeout.recover(applied.shell, applied.state)), raw)
      assertRawLock(shellWrite(LockTimeout.recoverFields(
        applied.shell, true, "600", true, true, selected.memory.originalSeconds, raw, true)), raw)
      assertRawLock(shellWrite(LockTimeout.select(applied.shell, selected.memory, "default")), raw)
    }
  }
}
