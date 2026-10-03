import QtQuick
import QtTest
import ".." as Plugin

TestCase {
  id: test
  name: "IdleInputOwnership"

  property QtObject host: null
  property QtObject foreign: null
  property QtObject idle: null
  property QtObject controller: null

  Component {
    id: hostComponent
    QtObject {
      property bool pluginReloading: false
      property var shellConfig: ({idle: {lock: 60, screensaver: 150}})
      property QtObject currentIdle: null
      function serviceFor(pluginId) { return currentIdle }
    }
  }

  Component {
    id: idleComponent
    QtObject {
      property var shell: null
      property int defaultLockSeconds: 300
      property bool idledThisCycle: false
      readonly property int lockTimeoutSeconds: shell ? shell.shellConfig.idle.lock : defaultLockSeconds
      // These tests exercise ownership, not the stock configuration parser.
      function secondsFromConfig(value, fallback) { return value === undefined ? fallback : value }
    }
  }

  Component { id: controllerComponent; Plugin.Service {} }

  function init() {
    host = createTemporaryObject(hostComponent, test)
    foreign = createTemporaryObject(hostComponent, test, {
      shellConfig: {idle: {lock: 120, screensaver: 150}}
    })
    idle = createTemporaryObject(idleComponent, test, {shell: host})
    host.currentIdle = idle
    controller = createTemporaryObject(controllerComponent, test)
    controller.shell = host
    tryVerify(function() { return controller.canSelect })
  }

  function test_foreignTakeoverAndHostRestoration() {
    verify(controller.selectChoice("600"))
    idle.shell = foreign
    compare(controller.choice, "default")
    verify(!controller.canSelect)
    verify(!controller.selectChoice("300"))
    compare(idle.shell, foreign)

    idle.shell = host
    compare(controller.choice, "default")
    verify(controller.canSelect)
    compare(controller.effectiveLockSeconds, 60)
  }

  function test_directCanonicalReplacement() {
    verify(controller.selectChoice("600"))
    idle.shell = host
    compare(controller.choice, "default")
    verify(controller.canSelect)
    compare(controller.effectiveLockSeconds, 60)
  }

  function test_explicitChoicesRemainSelectedWhileOwned() {
    verify(controller.selectChoice("600"))
    compare(controller.choice, "600")
    verify(controller.selectChoice("300"))
    compare(controller.choice, "300")
    verify(controller.selectChoice("default"))
    compare(controller.choice, "default")
    compare(idle.shell, host)
  }

  function test_destructionAfterTakeoverPreservesForeignInput() {
    verify(controller.selectChoice("600"))
    idle.shell = foreign
    controller.destroy()
    tryCompare(test, "controller", null)
    compare(idle.shell, foreign)
  }

  function test_destructionWhileOwnedRestoresCanonicalInput() {
    verify(controller.selectChoice("600"))
    controller.destroy()
    tryCompare(test, "controller", null)
    compare(idle.shell, host)
  }
}
