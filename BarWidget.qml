import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "io.github.luccast.omarr"

  readonly property var service: bar && bar.shell && typeof bar.shell.serviceFor === "function"
    ? bar.shell.serviceFor(moduleName) : null
  readonly property bool configured: service ? service.configured === true : false
  readonly property bool badgeUrgent: service ? service.badgeUrgent === true : false
  readonly property int badgeCount: service ? Number(service.badgeCount || 0) : 0
  readonly property int unreadCount: service ? Number(service.unreadCount || 0) : 0
  readonly property bool badgeVisible: unreadCount > 0 || badgeCount > 0
  readonly property string badgeText: unreadCount > 0 ? String(unreadCount) : String(badgeCount)
  readonly property real badgeIconSize: Style.space(12)
  readonly property real badgeGap: Style.space(3)
  readonly property color barColor: bar ? bar.barForeground : Color.foreground
  readonly property color urgentColor: bar && bar.urgent ? bar.urgent : Color.urgent
  readonly property color iconColor: !configured
    ? Qt.darker(barColor, 1.55)
    : (badgeUrgent ? urgentColor : barColor)

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
    if ("service" in target) target.service = root.service
  }

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function toggle() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()
  onServiceChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  Text {
    id: badgeMetrics
    visible: false
    text: root.badgeText
    font.family: root.bar ? root.bar.fontFamily : Style.font.family
    font.pixelSize: Style.font.caption
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    tooltipText: service ? service.statusText : "omARR"
    slotSize: root.badgeVisible
      ? Math.max(Style.bar.iconSlot,
          root.badgeIconSize + root.badgeGap
            + (vertical ? badgeMetrics.implicitHeight : badgeMetrics.implicitWidth)
            + Style.space(4))
      : Style.bar.iconSlot
    iconComponent: Component {
      Item {
        GridLayout {
          anchors.centerIn: parent
          columns: button.vertical ? 1 : 2
          columnSpacing: root.badgeGap
          rowSpacing: root.badgeGap

          OmarrIcon {
            Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
            iconSize: root.badgeIconSize
            color: root.iconColor
            live: root.badgeCount > 0 && !root.badgeUrgent

            Behavior on color {
              enabled: !root.bar || root.bar.foregroundAnimationEnabled
              ColorAnimation { duration: 160 }
            }
          }

          Text {
            Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
            visible: root.badgeVisible
            text: root.badgeText
            color: root.iconColor
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption

            Behavior on color {
              enabled: !root.bar || root.bar.foregroundAnimationEnabled
              ColorAnimation { duration: 160 }
            }
          }
        }
      }
    }
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.LeftButton) root.toggle()
    }
  }
}
