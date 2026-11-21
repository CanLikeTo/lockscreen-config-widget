import QtQuick
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "local.lockscreen-config"

  readonly property QtObject timeoutController: bar && bar.shell
    ? bar.shell.serviceFor(moduleName) : null
  readonly property var choices: ["default", "300", "600"]
  readonly property string selectedChoice: timeoutController ? timeoutController.choice : "default"
  readonly property string choiceLabel: selectedChoice === "600" ? "10 min"
    : selectedChoice === "300" ? "5 min" : "Default"
  readonly property string statusText: timeoutController
    ? timeoutController.statusText : "Shell configuration unavailable."
  property int cursorIndex: 0

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function applyChoice(index) {
    if (timeoutController && timeoutController.selectChoice(choices[index])) root.close()
  }

  onOpenedChanged: if (opened) cursorIndex = Math.max(0, choices.indexOf(selectedChoice))

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "\uf023"
    active: root.selectedChoice !== "default"
    activeColor: Color.accent
    tooltipText: "Lock timeout: " + root.choiceLabel + " ("
      + (root.timeoutController ? root.timeoutController.effectiveLockSeconds : 300) + " s)"
    onPressed: function(b) { if (b === Qt.LeftButton) root.toggle() }
  }

  KeyboardPanel {
    id: popup
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: popup.fittedContentWidth(Style.space(280))
    contentHeight: popup.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (dy !== 0) root.cursorIndex = Math.max(0, Math.min(2, root.cursorIndex + dy))
      }
      onActivateRequested: root.applyChoice(root.cursorIndex)
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(10)

        Text {
          width: parent.width
          text: "Lock timeout"
          color: root.bar ? root.bar.foreground : Color.foreground
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.title
          font.bold: true
        }

        Repeater {
          model: root.choices
          Button {
            required property string modelData
            required property int index
            width: column.width
            text: modelData === "default"
              ? "Default (" + (root.timeoutController ? root.timeoutController.configuredLockSeconds : 300) + " s)"
              : modelData === "300" ? "5 min" : "10 min"
            selected: root.selectedChoice === modelData
            iconText: selected ? "\uf00c" : ""
            enabled: root.timeoutController !== null && root.timeoutController.canSelect
            leftAlign: true
            hasCursor: root.cursorIndex === index
            foreground: root.bar ? root.bar.foreground : Color.foreground
            fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
            accent: Color.accent
            onClicked: root.applyChoice(index)
            onHovered: function(h) { if (h) root.cursorIndex = index }
          }
        }

        Text {
          width: parent.width
          text: "Resets on shell restart or logout."
          wrapMode: Text.WordWrap
          color: root.bar ? root.bar.foreground : Color.foreground
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.bodySmall
        }

        Text {
          width: parent.width
          visible: text !== ""
          text: root.statusText
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          color: root.bar ? root.bar.foreground : Color.foreground
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.bodySmall
        }
      }
    }
  }
}
