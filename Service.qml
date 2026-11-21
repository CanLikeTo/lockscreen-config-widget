import QtQuick
import Quickshell
import Quickshell.Io
import "LockTimeout.js" as LockTimeout

Item {
  id: root

  // Empty paths resolve from HOME so tests can point both files at a fixture tree.
  property string shellConfigPath: ""
  property string statePath: ""

  readonly property string homeDir: {
    var home = Quickshell.env("HOME")
    return home === undefined || home === null ? "" : String(home)
  }
  readonly property string resolvedShellConfigPath: shellConfigPath !== ""
    ? shellConfigPath
    : homeDir + "/.config/omarchy/shell.json"
  readonly property string resolvedStatePath: statePath !== ""
    ? statePath
    : homeDir + "/.local/state/omarchy/local.lockscreen-config.json"

  property string choice: "default"
  property int configuredLockSeconds: 300
  property int effectiveLockSeconds: 300
  property bool canSelect: false
  property string statusText: "Shell configuration unavailable."
  property bool owned: false
  property string appliedChoice: "default"
  property bool lockExisted: false
  property bool idleExisted: false
  property int originalSeconds: 300
  // A loose object dropped flags. Keep the raw JSON lock, including null, on a var.
  property var originalLock: null
  property bool hasOriginalLock: false
  property bool recoveryPending: false
  property string pendingStateText: ""

  property bool applying: false
  property bool ready: false
  property bool released: false
  property bool writeFailed: false

  function publish(result) {
    var memory = result.memory
    root.owned = !!(memory && memory.owned)
    root.appliedChoice = root.owned ? String(memory.choice) : "default"
    root.lockExisted = !!(memory && memory.lockExisted)
    root.idleExisted = !!(memory && memory.idleExisted)
    root.originalSeconds = memory && typeof memory.originalSeconds === "number"
      ? memory.originalSeconds : root.configuredLockSeconds
    root.hasOriginalLock = !!(result && result.hasOriginalLock)
      || !!(memory && Object.prototype.hasOwnProperty.call(memory, "originalLock"))
    if (root.hasOriginalLock) {
      var raw = memory && Object.prototype.hasOwnProperty.call(memory, "originalLock")
        ? memory.originalLock : result.originalLock
      root.originalLock = raw === undefined ? null : raw
    } else {
      root.originalLock = null
    }
    root.choice = result.choice || "default"
    root.configuredLockSeconds = result.configuredLockSeconds
    root.effectiveLockSeconds = result.effectiveLockSeconds
    root.recoveryPending = !!(result && result.recoveryPending)
    root.canSelect = !!result.canSelect && !root.recoveryPending
    root.statusText = result.statusText || ""
    if (!root.recoveryPending) root.pendingStateText = ""
  }

  function readFile(file) {
    file.reload()
    return file.text() || ""
  }

  function writeFile(file, text) {
    root.writeFailed = false
    file.setText(text)
    return !root.writeFailed
  }

  // State is written before shell.json. A failed state write must not touch shell.json.
  function applyActions(actions) {
    var list = actions || []
    root.applying = true
    for (var i = 0; i < list.length; i++) {
      var action = list[i]
      var ok = true
      if (action.type === "writeState") ok = root.writeFile(stateFile, action.text)
      else if (action.type === "writeShell") ok = root.writeFile(shellFile, action.text)
      else if (action.type === "clearState") ok = root.writeFile(stateFile, "")
      if (!ok) {
        root.applying = false
        root.canSelect = false
        root.statusText = "Shell configuration unavailable."
        return false
      }
    }
    root.applying = false
    return true
  }

  function selectChoice(nextChoice) {
    if (root.released || root.recoveryPending || !root.canSelect) return false
    var result = LockTimeout.selectFields(
      root.readFile(shellFile), root.owned, root.appliedChoice,
      root.lockExisted, root.idleExisted, root.originalSeconds, String(nextChoice),
      root.originalLock, root.hasOriginalLock)
    if (!root.applyActions(result.actions)) return false
    root.publish(result)
    return !!result.ok
  }

  function handleShellChanged() {
    if (root.applying || !root.ready || root.released) return
    // Recover a pending journal before reconcile can enable choices.
    var result = LockTimeout.shellChanged(
      root.readFile(shellFile), root.owned, root.appliedChoice,
      root.lockExisted, root.idleExisted, root.originalSeconds,
      root.originalLock, root.hasOriginalLock,
      root.recoveryPending, root.pendingStateText)
    if (!root.applyActions(result.actions)) {
      root.canSelect = false
      return
    }
    root.publish(result)
  }

  function recoverFrom(stateText) {
    root.pendingStateText = stateText || ""
    var result = LockTimeout.recover(root.readFile(shellFile), stateText)
    if (!root.applyActions(result.actions)) {
      root.recoveryPending = true
      root.canSelect = false
      root.statusText = "Shell configuration unavailable."
      return
    }
    root.publish(result)
  }

  FileView {
    id: shellFile
    path: root.resolvedShellConfigPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    blockWrites: true
    preload: false
    blockAllReads: true
    onFileChanged: root.handleShellChanged()
    onSaveFailed: root.writeFailed = true
  }

  FileView {
    id: stateFile
    path: root.resolvedStatePath
    watchChanges: false
    atomicWrites: true
    printErrors: false
    blockWrites: true
    preload: false
    blockAllReads: true
    onSaveFailed: root.writeFailed = true
  }

  Component.onCompleted: {
    root.recoverFrom(root.readFile(stateFile))
    root.ready = true
    if (root.recoveryPending) root.handleShellChanged()
  }

  Component.onDestruction: {
    if (root.released) return
    root.released = true
    var result = root.recoveryPending
      ? LockTimeout.recover(root.readFile(shellFile), root.pendingStateText)
      : LockTimeout.recoverFields(
        root.readFile(shellFile), root.owned, root.appliedChoice,
        root.lockExisted, root.idleExisted, root.originalSeconds,
        root.originalLock, root.hasOriginalLock)
    root.applyActions(result.actions)
  }
}
