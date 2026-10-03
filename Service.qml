import QtQuick

Item {
  id: root

  // The shell injects these after construction.
  property var shell: null
  property var manifest: null
  property string choice: "default"
  property QtObject attachedIdle: null
  property QtObject attachedShell: null

  readonly property QtObject idleService: shell && !shell.pluginReloading
    && typeof shell.serviceFor === "function" ? shell.serviceFor("omarchy.idle") : null
  readonly property bool compatible: idleService !== null
    && "shell" in idleService
    && typeof idleService.secondsFromConfig === "function"
    && typeof idleService.defaultLockSeconds === "number"
    && typeof idleService.lockTimeoutSeconds === "number"
    && typeof idleService.idledThisCycle === "boolean"
  readonly property int configuredLockSeconds: {
    if (!compatible || !shell) return 300
    var config = shell.shellConfig
    var idle = config && config.idle ? config.idle : ({})
    return idleService.secondsFromConfig(idle.lock, idleService.defaultLockSeconds)
  }
  readonly property int effectiveLockSeconds: compatible
    ? idleService.lockTimeoutSeconds : configuredLockSeconds
  readonly property bool available: compatible
    && (idleService.shell === shell || idleService.shell === facade)
  readonly property bool canSelect: available && !idleService.idledThisCycle
  readonly property string statusText: !compatible ? "Idle service unavailable."
    : !available ? "Another plugin controls the idle timeout."
    : !canSelect ? "Wait for activity before changing the timeout." : ""

  QtObject {
    id: facade
    // Only this service-local view contains the override. Canonical config stays intact.
    property var shellConfig: {
      var original = root.shell && root.shell.shellConfig ? root.shell.shellConfig : ({})
      var config = ({})
      for (var key in original) config[key] = original[key]
      var idle = ({})
      var originalIdle = original.idle || ({})
      for (var field in originalIdle) idle[field] = originalIdle[field]
      idle.lock = root.choice === "600" ? 600 : 300
      config.idle = idle
      return config
    }
  }

  function releaseOverride() {
    if (attachedIdle && attachedIdle.shell === facade)
      attachedIdle.shell = attachedShell
    attachedIdle = null
    attachedShell = null
  }

  function synchronizeService() {
    if (attachedIdle === idleService && attachedShell === shell) return
    releaseOverride()
    choice = "default"
    if (compatible && idleService.shell === shell) {
      attachedIdle = idleService
      attachedShell = shell
    }
  }

  function selectChoice(nextChoice) {
    if (nextChoice !== "default" && nextChoice !== "300" && nextChoice !== "600") return false
    synchronizeService()
    if (!canSelect) return false
    choice = nextChoice
    idleService.shell = nextChoice === "default" ? shell : facade
    return true
  }

  Connections {
    target: root.attachedIdle
    function onShellChanged() {
      // Losing the facade also loses the selection; never reclaim a foreign input.
      if (root.attachedIdle && root.attachedIdle.shell !== facade)
        root.choice = "default"
    }
  }

  onShellChanged: Qt.callLater(synchronizeService)
  onIdleServiceChanged: Qt.callLater(synchronizeService)
  Component.onDestruction: releaseOverride()
}
