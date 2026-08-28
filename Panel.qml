import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "io.github.luccast.omarr"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var service: null
  property bool showSettings: false
  property string pendingSettings: ""
  property int selectedIndex: -1
  property string detailId: ""
  property string homeTab: "ondeck"
  property bool enterConsumed: false

  readonly property var barIdentity: hostWidget || root
  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color dim: Qt.darker(contentForeground, 1.4)
  readonly property color urgent: bar && bar.urgent ? bar.urgent : Color.urgent
  readonly property var snapshots: service && service.snapshots ? service.snapshots : []
  readonly property string fleetKey: Model.fleetOrderKey(root.snapshots)
  readonly property var nowFeed: service && service.nowFeed ? service.nowFeed : ({ downloads: [], calendar: [], warnings: [], sessions: [], onDeck: [], recent: [], downloadingCount: 0, downCount: 0, showQueue: false, showCalendar: false })
  readonly property var calendarGroups: Model.groupedCalendar(service && service.calendarFeed ? service.calendarFeed : [])
  readonly property var homeTabModel: {
    var tabs = [
      { id: "ondeck", label: "ON DECK" },
      { id: "recent", label: "RECENTLY ADDED" }
    ]
    if (root.nowFeed.showCalendar)
      tabs.push({ id: "calendar", label: "CALENDAR" })
    return tabs
  }
  readonly property string shownHomeTab: {
    var tabs = root.homeTabModel
    for (var i = 0; i < tabs.length; i++) {
      if (tabs[i].id === root.homeTab) return root.homeTab
    }
    return tabs.length ? tabs[0].id : "ondeck"
  }
  readonly property bool compact: service && service.density === "compact"
  readonly property int rowPad: compact ? Style.space(4) : Style.space(8)
  readonly property int fleetWidth: Style.space(152)
  readonly property var selectedSnap: selectedIndex >= 0 && selectedIndex < snapshots.length ? snapshots[selectedIndex] : null
  readonly property var detailSnap: Model.snapshotById(snapshots, detailId)
  readonly property bool settingsBlocked: settingsLoader.item ? settingsLoader.item.editorOpen === true : false
  readonly property int detailQueuePage: {
    if (root.detailSnap && root.service && root.service.detailQueueId === root.detailSnap.id)
      return root.service.detailQueuePage
    return 1
  }
  readonly property var detailQueueModel: {
    if (root.detailSnap && root.service && root.service.detailQueueId === root.detailSnap.id && root.service.detailQueuePage > 1)
      return root.service.detailQueue
    return root.detailSnap && root.detailSnap.queue ? root.detailSnap.queue : []
  }
  readonly property var detailPager: {
    var total = 0
    if (root.detailSnap && root.service && root.service.detailQueueId === root.detailSnap.id && root.service.detailQueuePage > 1)
      total = root.service.detailQueueTotal
    else if (root.detailSnap)
      total = root.detailSnap.queueTotal || 0
    return Model.listPager(root.detailQueuePage, root.detailQueueModel, total, root.service ? root.service.pageSize : 0)
  }

  onDetailIdChanged: {
    if (root.service) root.service.clearDetailQueue()
    if (contentFlick) contentFlick.contentY = 0
  }

  onHomeTabChanged: if (contentFlick) contentFlick.contentY = 0

  function open() {
    if (root.service) {
      root.service.panelOpen = true
      root.service.clearUnread()
    }
    root.controller.show()
    Qt.callLater(function() {
      if (root.opened) setCenterHoverRevealSuppressed(true)
    })
  }

  function close() {
    setCenterHoverRevealSuppressed(false)
    if (root.service) root.service.panelOpen = false
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function setCenterHoverRevealSuppressed(value) {
    if (root.bar && "centerHoverRevealSuppressed" in root.bar)
      root.bar.centerHoverRevealSuppressed = value
  }

  function clampSelection() {
    if (root.snapshots.length === 0) {
      root.selectedIndex = -1
      return
    }
    if (root.selectedIndex < -1) root.selectedIndex = -1
    if (root.selectedIndex >= root.snapshots.length)
      root.selectedIndex = root.snapshots.length - 1
  }

  function goOverview() {
    root.detailId = ""
    root.selectedIndex = -1
  }

  function openAddService() {
    root.pendingSettings = "add"
    root.showSettings = true
    if (settingsLoader.item) {
      settingsLoader.item.startAdd()
      root.pendingSettings = ""
    }
  }

  function openFleetSettings() {
    root.pendingSettings = "fleet"
    root.showSettings = true
    if (settingsLoader.item) {
      settingsLoader.item.showFleet()
      root.pendingSettings = ""
    }
  }

  function moveCursor(dx, dy) {
    if (root.showSettings) return
    if (dx > 0 && root.selectedSnap) {
      root.detailId = root.selectedSnap.id
      return
    }
    if (dx < 0) {
      root.goOverview()
      return
    }
    root.selectedIndex += dy
    root.clampSelection()
  }

  function activateCursor() {
    if (root.enterConsumed) {
      root.enterConsumed = false
      return
    }
    if (root.showSettings) return
    if (root.snapshots.length === 0) {
      root.showSettings = true
      return
    }
    if (root.selectedIndex < 0) {
      root.goOverview()
      return
    }
    if (!root.selectedSnap) return
    if (root.detailId === root.selectedSnap.id) root.goOverview()
    else root.detailId = root.selectedSnap.id
  }

  function openSelected() {
    root.enterConsumed = true
    if (root.selectedSnap && root.service) root.service.openService(root.selectedSnap.id)
  }

  function healthColor(health) {
    if (health === "down") return root.urgent
    if (health === "up") return root.contentForeground
    return root.dim
  }

  function posterSource(serviceId, posterId) {
    if (!root.service || !posterId) return ""
    var path = root.service.posterPath(serviceId, posterId)
    var rev = root.service.artRev
    return Model.fileUrl(path, rev && rev[path])
  }

  function fanartSource(serviceId, posterId) {
    if (!root.service || !posterId) return ""
    var path = root.service.fanartPath(serviceId, posterId)
    var rev = root.service.artRev
    return Model.fileUrl(path, rev && rev[path])
  }

  function mediaSource(serviceId, itemId) {
    if (!root.service || !itemId) return ""
    var path = root.service.mediaPath(serviceId, itemId)
    var rev = root.service.artRev
    return Model.fileUrl(path, rev && rev[path])
  }

  function wheelDelta(event) {
    if (!event) return 0
    if (event.angleDelta && event.angleDelta.y)
      return event.angleDelta.y / 100 * Style.space(120)
    if (event.pixelDelta && event.pixelDelta.y)
      return event.pixelDelta.y * 4
    return 0
  }

  function scrollFlick(flick, dy) {
    if (!flick || !(flick.contentHeight > flick.height) || !dy) return
    var maxY = Math.max(0, flick.contentHeight - flick.height)
    flick.contentY = Math.max(0, Math.min(maxY, flick.contentY - dy))
  }

  onSnapshotsChanged: root.clampSelection()

  Component {
    id: settingsComp
    SettingsView {
      width: body.width
      service: root.service
      foreground: root.contentForeground
      fontFamily: root.contentFontFamily
      compact: root.compact
      onCloseSettings: root.showSettings = false
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(500))
    contentHeight: panel.cappedContentHeight(Style.space(640))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.settingsBlocked
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onMoveRequested: function(dx, dy) { root.moveCursor(dx, dy) }
      onActivateRequested: root.activateCursor()
      onReturnRequested: root.openSelected()
      onTextKey: function(t) {
        if (t === "s" || t === "S") root.showSettings = !root.showSettings
        else if (t === "o" || t === "O") root.openSelected()
      }

      Column {
        id: shell
        anchors.fill: parent
        spacing: root.rowPad

        Column {
          id: headerBar
          width: parent.width
          spacing: Style.space(6)

          Item {
            width: parent.width
            height: Math.max(hero.implicitHeight, headerActions.implicitHeight)

            Item {
              id: hero
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              implicitWidth: headerIcon.width + Style.space(6) + heroTitle.implicitWidth
              width: implicitWidth
              implicitHeight: Math.max(headerIcon.implicitHeight, heroTitle.implicitHeight)
              height: implicitHeight

              OmarrIcon {
                id: headerIcon
                iconSize: Style.font.heading
                color: root.contentForeground
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                id: heroTitle
                anchors.left: headerIcon.right
                anchors.leftMargin: Style.space(6)
                anchors.verticalCenter: parent.verticalCenter
                text: "omARR"
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.title
                font.bold: true
                textFormat: Text.PlainText
              }
            }

            Text {
              id: heroMeta
              anchors.left: hero.right
              anchors.right: headerActions.left
              anchors.leftMargin: Style.space(8)
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              text: root.service ? String(root.service.statusText || "").toUpperCase() : ""
              visible: text !== ""
              color: root.dim
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
              horizontalAlignment: Text.AlignHCenter
              elide: Text.ElideRight
              textFormat: Text.PlainText
            }

            Row {
              id: headerActions
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              PanelActionButton {
                iconText: "󰋜"
                tooltipText: "Overview"
                foreground: !root.showSettings && root.detailId === "" ? Color.accent : root.contentForeground
                fontFamily: root.contentFontFamily
                onClicked: {
                  root.showSettings = false
                  root.goOverview()
                }
              }

              PanelActionButton {
                iconText: "󰒓"
                tooltipText: root.showSettings ? "Back" : "Settings"
                foreground: root.showSettings ? Color.accent : root.contentForeground
                fontFamily: root.contentFontFamily
                onClicked: root.showSettings = !root.showSettings
              }
            }
          }

          PanelSeparator { foreground: root.contentForeground }
        }

            Item {
            id: body
            width: parent.width
            height: Math.max(0, parent.height - headerBar.height - parent.spacing)

            Row {
              z: 2
              anchors.left: parent.left
              anchors.bottom: parent.bottom
              visible: !root.showSettings
              spacing: Style.space(2)

              PanelActionButton {
                iconText: "󰐕"
                tooltipText: "Add service"
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
                onClicked: root.openAddService()
              }

              PanelActionButton {
                iconText: "󰍜"
                tooltipText: "Fleet"
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
                onClicked: root.openFleetSettings()
              }
            }

            Flickable {
              id: settingsFlick
              anchors.fill: parent
              visible: root.showSettings
              clip: true
              contentWidth: width
              contentHeight: settingsLoader.item ? settingsLoader.item.implicitHeight : 0
              boundsBehavior: Flickable.StopAtBounds
              flickableDirection: Flickable.VerticalFlick
              interactive: contentHeight > height
              ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

              WheelHandler {
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: function(event) {
                  root.scrollFlick(settingsFlick, root.wheelDelta(event))
                  event.accepted = true
                }
              }

              Loader {
                id: settingsLoader
                width: parent.width
                active: root.showSettings
                visible: active
                sourceComponent: settingsComp
                onLoaded: {
                  if (root.pendingSettings === "add") {
                    item.startAdd()
                    root.pendingSettings = ""
                  } else if (root.pendingSettings === "fleet") {
                    item.showFleet()
                    root.pendingSettings = ""
                  }
                }
              }
            }

            Column {
              anchors.fill: parent
              visible: !root.showSettings && root.snapshots.length === 0
              spacing: root.rowPad

              Text {
                width: parent.width
                text: "Nothing on the overview yet. Open settings to add Sonarr, Radarr, SABnzbd, qBittorrent, or any local URL — or scan this machine."
                wrapMode: Text.WordWrap
                color: root.dim
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.bodySmall
                font.italic: true
              }

              Button {
                text: "Open settings"
                foreground: root.contentForeground
                onClicked: root.showSettings = true
              }
            }

            Row {
              anchors.fill: parent
              spacing: Style.space(8)
              visible: !root.showSettings && root.snapshots.length > 0

            Column {
              width: root.fleetWidth
              height: parent.height
              clip: true
              spacing: Style.space(4)

              PanelSectionHeader {
                text: "FLEET"
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
              }

              Repeater {
                model: {
                  var _ = root.fleetKey
                  return Model.groupedServices(root.snapshots)
                }

                Column {
                  required property var modelData
                  width: parent.width
                  spacing: Style.space(2)

                  Text {
                    visible: parent.modelData.group !== ""
                    width: parent.width
                    text: parent.modelData.group
                    color: root.dim
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                    textFormat: Text.PlainText
                  }

                  Repeater {
                    model: parent.modelData.services

                    CursorSurface {
                      id: fleetRow
                      required property var modelData
                      width: parent.width
                      implicitHeight: fleetCol.implicitHeight + Style.space(6)
                      hasCursor: {
                        var idx = -1
                        for (var i = 0; i < root.snapshots.length; i++) {
                          if (root.snapshots[i].id === fleetRow.modelData.id) idx = i
                        }
                        return idx === root.selectedIndex
                      }
                      current: root.detailId === fleetRow.modelData.id
                      foreground: root.contentForeground
                      accent: Color.accent
                      opacity: fleetHover.containsMouse || fleetRow.hasCursor || fleetRow.current ? 1 : 0.8

                      Behavior on opacity {
                        NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
                      }

                      MouseArea {
                        id: fleetHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                          for (var i = 0; i < root.snapshots.length; i++) {
                            if (root.snapshots[i].id === fleetRow.modelData.id) root.selectedIndex = i
                          }
                          root.detailId = fleetRow.modelData.id
                        }
                        onDoubleClicked: if (root.service) root.service.openService(fleetRow.modelData.id)
                      }

                      Row {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.margins: Style.space(4)
                        spacing: Style.space(6)

                        ServiceIcon {
                          id: fleetIcon
                          service: fleetRow.modelData
                          health: fleetRow.modelData.health || ""
                          healthColor: root.healthColor(fleetRow.modelData.health)
                          iconSize: Style.space(16)
                          anchors.verticalCenter: parent.verticalCenter
                        }

                        Column {
                          id: fleetCol
                          width: parent.width - fleetIcon.width - parent.spacing
                          spacing: Style.space(1)

                          Text {
                            width: parent.width
                            text: fleetRow.modelData.name
                            color: root.contentForeground
                            font.family: root.contentFontFamily
                            font.pixelSize: Style.font.bodySmall
                            font.bold: true
                            elide: Text.ElideRight
                            textFormat: Text.PlainText
                          }

                          Text {
                            width: parent.width
                            text: Model.fleetLine(fleetRow.modelData)
                            color: root.dim
                            font.family: root.contentFontFamily
                            font.pixelSize: Style.font.caption
                            elide: Text.ElideRight
                            textFormat: Text.PlainText
                          }
                        }
                      }
                    }
                  }
                }
              }
            }

            Flickable {
              id: contentFlick
              width: parent.width - root.fleetWidth - parent.spacing
              height: parent.height
              clip: true
              contentWidth: width
              contentHeight: pane.implicitHeight
              boundsBehavior: Flickable.StopAtBounds
              flickableDirection: Flickable.VerticalFlick
              interactive: contentHeight > height
              ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

              WheelHandler {
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: function(event) {
                  root.scrollFlick(contentFlick, root.wheelDelta(event))
                  event.accepted = true
                }
              }

              Column {
                id: pane
                width: contentFlick.width
                spacing: Style.space(12)
                topPadding: Style.space(4)
                bottomPadding: Style.space(8)

              Column {
                width: parent.width
                spacing: Style.space(20)
                visible: !root.detailSnap
                height: visible ? implicitHeight : 0

                Column {
                  width: parent.width
                  spacing: Style.space(8)
                  visible: root.nowFeed.warnings && root.nowFeed.warnings.length > 0
                  height: visible ? implicitHeight : 0

                  PanelSectionHeader {
                    text: "WARNINGS"
                    foreground: root.urgent
                    fontFamily: root.contentFontFamily
                  }

                  Repeater {
                    model: root.nowFeed.warnings || []

                    Text {
                      required property var modelData
                      width: parent.width
                      text: modelData.title + " · " + modelData.body
                      color: root.urgent
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.caption
                      elide: Text.ElideRight
                      textFormat: Text.PlainText
                      wrapMode: Text.WordWrap
                    }
                  }
                }

                Column {
                  width: parent.width
                  spacing: Style.space(8)
                  visible: root.nowFeed.showQueue && (root.nowFeed.downloads || []).length > 0
                  height: visible ? implicitHeight : 0

                  PanelSectionHeader {
                    text: "DOWNLOADING"
                    foreground: root.contentForeground
                    fontFamily: root.contentFontFamily
                  }

                  Repeater {
                    model: root.nowFeed.downloads || []

                    Column {
                      required property var modelData
                      width: parent.width
                      spacing: Style.space(2)

                    Text {
                      width: parent.width
                      text: parent.modelData.title
                      color: root.contentForeground
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.bodySmall
                      elide: Text.ElideRight
                      textFormat: Text.PlainText
                    }

                    Text {
                      width: parent.width
                      text: parent.modelData.serviceName + " · " + Model.formatProgress(parent.modelData.progress)
                        + (Model.queueLine(parent.modelData) ? " · " + Model.queueLine(parent.modelData) : "")
                      color: parent.modelData.status === "warning" || parent.modelData.status === "error" ? root.urgent : root.dim
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.caption
                      elide: Text.ElideRight
                      textFormat: Text.PlainText
                    }

                    Rectangle {
                      width: parent.width
                      height: Style.space(2)
                      color: Qt.darker(root.contentForeground, 2.2)
                      radius: 1

                      Rectangle {
                        width: parent.width * Math.max(0, Math.min(1, parent.parent.modelData.progress || 0))
                        height: parent.height
                        color: root.contentForeground
                        radius: 1
                      }
                    }
                  }
                }
                }

                Text {
                  visible: root.nowFeed.showQueue && (!root.nowFeed.downloads || root.nowFeed.downloads.length === 0)
                    && !(root.nowFeed.sessions || []).length
                  width: parent.width
                  text: "Queue is quiet."
                  color: root.dim
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption
                  font.italic: true
                }

                Column {
                  width: parent.width
                  spacing: Style.space(8)
                  visible: (root.nowFeed.sessions || []).length > 0
                  height: visible ? implicitHeight : 0

                  PanelSectionHeader {
                    text: "NOW PLAYING"
                    foreground: root.contentForeground
                    fontFamily: root.contentFontFamily
                  }

                  Repeater {
                    model: root.nowFeed.sessions || []

                  Column {
                    required property var modelData
                    width: parent.width
                    spacing: Style.space(2)

                    Text {
                      width: parent.width
                      text: parent.modelData.title
                      color: root.contentForeground
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.bodySmall
                      elide: Text.ElideRight
                      textFormat: Text.PlainText
                    }

                    Text {
                      width: parent.width
                      visible: parent.modelData.subtitle
                      height: visible ? implicitHeight : 0
                      text: parent.modelData.subtitle
                      color: root.dim
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.caption
                      elide: Text.ElideRight
                      textFormat: Text.PlainText
                    }

                    Rectangle {
                      width: parent.width
                      height: Style.space(2)
                      color: Qt.darker(root.contentForeground, 2.2)
                      radius: 1

                      Rectangle {
                        width: parent.width * Math.max(0, Math.min(1, parent.parent.modelData.progress || 0))
                        height: parent.height
                        color: root.contentForeground
                        radius: 1
                      }
                    }
                  }
                }
                }

                Column {
                  width: parent.width
                  spacing: Style.space(8)

                  Flow {
                    width: parent.width
                    spacing: Style.space(12)

                  Repeater {
                    model: root.homeTabModel

                    Item {
                      id: homeTabChip
                      required property var modelData
                      width: homeTabLabel.implicitWidth
                      height: homeTabLabel.implicitHeight + Style.space(6)

                      Text {
                        id: homeTabLabel
                        text: homeTabChip.modelData.label
                        color: root.shownHomeTab === homeTabChip.modelData.id ? root.contentForeground : root.dim
                        font.family: root.contentFontFamily
                        font.pixelSize: Style.font.caption
                        font.bold: true
                        textFormat: Text.PlainText
                      }

                      Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: 1
                        visible: root.shownHomeTab === homeTabChip.modelData.id
                        color: root.contentForeground
                      }

                      MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.homeTab = homeTabChip.modelData.id
                      }
                    }
                  }
                }

                Repeater {
                  model: root.shownHomeTab === "ondeck" ? (root.service && root.service.onDeckFeed ? root.service.onDeckFeed : []) : []

                  CalendarCard {
                    required property var modelData
                    item: modelData
                    posterUrl: root.mediaSource(modelData.serviceId, modelData.posterId)
                    fanartUrl: root.mediaSource(modelData.serviceId, modelData.posterId)
                    compact: root.compact
                    fontFamily: root.contentFontFamily
                  }
                }

                Repeater {
                  model: root.shownHomeTab === "recent" ? (root.service && root.service.recentFeed ? root.service.recentFeed : []) : []

                  CalendarCard {
                    required property var modelData
                    item: modelData
                    posterUrl: root.mediaSource(modelData.serviceId, modelData.posterId)
                    fanartUrl: root.mediaSource(modelData.serviceId, modelData.posterId)
                    compact: root.compact
                    fontFamily: root.contentFontFamily
                  }
                }

                Repeater {
                  model: root.shownHomeTab === "calendar" ? root.calendarGroups : []

                  Column {
                    required property var modelData
                    width: parent.width
                    spacing: Style.space(10)

                    Text {
                      visible: parent.modelData.heading !== ""
                      width: parent.width
                      text: parent.modelData.heading
                      color: root.dim
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.caption
                      font.bold: true
                      textFormat: Text.PlainText
                    }

                    Repeater {
                      model: parent.modelData.items

                      CalendarCard {
                        required property var modelData
                        item: modelData
                        posterUrl: root.posterSource(modelData.serviceId, modelData.posterId)
                        fanartUrl: root.fanartSource(modelData.serviceId, modelData.posterId)
                        compact: root.compact
                        fontFamily: root.contentFontFamily
                      }
                    }
                  }
                }

                Text {
                  visible: (root.shownHomeTab === "ondeck" && !(root.service && root.service.onDeckFeed && root.service.onDeckFeed.length))
                    || (root.shownHomeTab === "recent" && !(root.service && root.service.recentFeed && root.service.recentFeed.length))
                    || (root.shownHomeTab === "calendar" && !(root.service && root.service.calendarFeed && root.service.calendarFeed.length))
                  width: parent.width
                  text: root.shownHomeTab === "recent" ? "Nothing recently added."
                    : root.shownHomeTab === "calendar" ? "Calendar is empty."
                    : "Nothing on deck."
                  color: root.dim
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption
                  font.italic: true
                }
                }
              }

              Column {
                width: parent.width
                spacing: Style.space(20)
                visible: !!root.detailSnap
                height: visible ? implicitHeight : 0

                Column {
                  width: parent.width
                  spacing: Style.space(8)

                  Item {
                    width: parent.width
                    height: Math.max(detailHeader.implicitHeight, openBtn.implicitHeight, detailIcon.height)

                  ServiceIcon {
                    id: detailIcon
                    service: root.detailSnap || ({})
                    health: root.detailSnap ? (root.detailSnap.health || "") : ""
                    healthColor: root.healthColor(root.detailSnap ? root.detailSnap.health : "")
                    iconSize: Style.space(16)
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                  }

                  PanelSectionHeader {
                    id: detailHeader
                    anchors.left: detailIcon.right
                    anchors.leftMargin: Style.space(8)
                    anchors.right: detailActions.left
                    anchors.rightMargin: Style.space(8)
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.detailSnap ? String(root.detailSnap.name).toUpperCase() : ""
                    foreground: root.contentForeground
                    fontFamily: root.contentFontFamily
                  }

                  Row {
                    id: detailActions
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.space(2)

                    PanelActionButton {
                      id: openBtn
                      iconText: "󰖟"
                      tooltipText: "Open in browser"
                      foreground: root.contentForeground
                      fontFamily: root.contentFontFamily
                      onClicked: if (root.service && root.detailSnap) root.service.openUrl(root.detailSnap.url)
                    }
                  }
                }

                Text {
                  width: parent.width
                  text: root.detailSnap ? (root.detailSnap.statusText || Model.fleetLine(root.detailSnap)) : ""
                  color: root.dim
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                  wrapMode: Text.WordWrap
                  textFormat: Text.PlainText
                }
                }

                Column {
                  width: parent.width
                  spacing: Style.space(8)
                  visible: root.detailSnap && Model.isMediaKind(root.detailSnap.kind)
                    && (root.detailSnap.sessions || []).length > 0
                  height: visible ? implicitHeight : 0

                  PanelSectionHeader {
                    text: "NOW PLAYING"
                    foreground: root.contentForeground
                    fontFamily: root.contentFontFamily
                  }

                  Repeater {
                    model: root.detailSnap && Model.isMediaKind(root.detailSnap.kind)
                      ? (root.detailSnap.sessions || []) : []

                  Column {
                    required property var modelData
                    width: parent.width
                    spacing: Style.space(2)

                    Text {
                      width: parent.width
                      text: parent.modelData.title
                      color: root.contentForeground
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.bodySmall
                      elide: Text.ElideRight
                      textFormat: Text.PlainText
                    }

                    Text {
                      width: parent.width
                      visible: parent.modelData.subtitle
                      height: visible ? implicitHeight : 0
                      text: parent.modelData.subtitle
                      color: root.dim
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.caption
                      elide: Text.ElideRight
                      textFormat: Text.PlainText
                    }

                    Rectangle {
                      width: parent.width
                      height: Style.space(2)
                      color: Qt.darker(root.contentForeground, 2.2)
                      radius: 1

                      Rectangle {
                        width: parent.width * Math.max(0, Math.min(1, parent.parent.modelData.progress || 0))
                        height: parent.height
                        color: root.contentForeground
                        radius: 1
                      }
                    }
                  }
                }
                }

                Column {
                  width: parent.width
                  spacing: Style.space(8)
                  visible: root.detailSnap && Model.isMediaKind(root.detailSnap.kind)
                    && (root.detailSnap.onDeck || []).length > 0
                  height: visible ? implicitHeight : 0

                  PanelSectionHeader {
                    text: "ON DECK"
                    foreground: root.contentForeground
                    fontFamily: root.contentFontFamily
                  }

                  Repeater {
                    model: root.detailSnap && Model.isMediaKind(root.detailSnap.kind)
                      ? (root.detailSnap.onDeck || []) : []

                  CalendarCard {
                    required property var modelData
                    item: modelData
                    posterUrl: root.detailSnap ? root.mediaSource(root.detailSnap.id, modelData.id) : ""
                    fanartUrl: root.detailSnap ? root.mediaSource(root.detailSnap.id, modelData.id) : ""
                    compact: root.compact
                    fontFamily: root.contentFontFamily
                  }
                }
                }

                Column {
                  width: parent.width
                  spacing: Style.space(8)
                  visible: root.detailSnap && Model.isMediaKind(root.detailSnap.kind)
                    && (root.detailSnap.recent || []).length > 0
                  height: visible ? implicitHeight : 0

                  PanelSectionHeader {
                    text: "RECENTLY ADDED"
                    foreground: root.contentForeground
                    fontFamily: root.contentFontFamily
                  }

                  Repeater {
                    model: root.detailSnap && Model.isMediaKind(root.detailSnap.kind)
                      ? (root.detailSnap.recent || []) : []

                    CalendarCard {
                      required property var modelData
                      item: modelData
                      posterUrl: root.detailSnap ? root.mediaSource(root.detailSnap.id, modelData.id) : ""
                      fanartUrl: root.detailSnap ? root.mediaSource(root.detailSnap.id, modelData.id) : ""
                      compact: root.compact
                      fontFamily: root.contentFontFamily
                    }
                  }
                }

                Column {
                  width: parent.width
                  spacing: Style.space(8)
                  visible: root.detailSnap && !Model.isMediaKind(root.detailSnap.kind)
                    && ((root.detailQueueModel || []).length > 0 || root.detailPager.hasPrev || root.detailPager.hasNext)
                  height: visible ? implicitHeight : 0

                  Repeater {
                    model: root.detailSnap && Model.isMediaKind(root.detailSnap.kind) ? [] : root.detailQueueModel

                  CursorSurface {
                    id: qRow
                    required property var modelData
                    width: parent.width
                    implicitHeight: qCol.implicitHeight + Style.space(10)
                    hasCursor: qMouse.containsMouse
                    foreground: root.contentForeground
                    accent: Color.accent

                    MouseArea {
                      id: qMouse
                      anchors.fill: parent
                      hoverEnabled: true
                    }

                    Row {
                      anchors.fill: parent
                      anchors.margins: Style.space(6)
                      spacing: Style.space(6)

                      Column {
                        id: qCol
                        width: parent.width - Style.space(52)
                        spacing: Style.space(2)

                        Text {
                          width: parent.width
                          text: qRow.modelData.title
                          color: root.contentForeground
                          font.family: root.contentFontFamily
                          font.pixelSize: Style.font.caption
                          elide: Text.ElideRight
                          textFormat: Text.PlainText
                        }

                        Text {
                          width: parent.width
                          visible: Model.queueLine(qRow.modelData) !== ""
                          height: visible ? implicitHeight : 0
                          text: Model.queueLine(qRow.modelData)
                          color: qRow.modelData.status === "warning" || qRow.modelData.status === "error" ? root.urgent : root.dim
                          font.family: root.contentFontFamily
                          font.pixelSize: Style.font.caption
                          elide: Text.ElideRight
                          textFormat: Text.PlainText
                        }

                        Rectangle {
                          width: parent.width
                          height: Style.space(2)
                          color: Qt.darker(root.contentForeground, 2.2)

                          Rectangle {
                            width: parent.width * Math.max(0, Math.min(1, qRow.modelData.progress || 0))
                            height: parent.height
                            color: root.contentForeground
                          }
                        }
                      }

                      PanelActionButton {
                        visible: root.detailSnap && (root.detailSnap.kind === "sabnzbd" || root.detailSnap.kind === "qbittorrent")
                        iconText: "󰏤"
                        tooltipText: "Pause"
                        foreground: root.contentForeground
                        fontFamily: root.contentFontFamily
                        onClicked: if (root.service && root.detailSnap)
                          root.service.runControl(root.detailSnap.id, "pause-item", qRow.modelData.id)
                      }

                      PanelActionButton {
                        visible: root.detailSnap && (root.detailSnap.kind === "sabnzbd" || root.detailSnap.kind === "qbittorrent")
                        iconText: "󰐊"
                        tooltipText: "Resume"
                        foreground: root.contentForeground
                        fontFamily: root.contentFontFamily
                        onClicked: if (root.service && root.detailSnap)
                          root.service.runControl(root.detailSnap.id, "resume-item", qRow.modelData.id)
                      }
                    }
                  }
                }

                Row {
                  visible: root.detailSnap && !Model.isMediaKind(root.detailSnap.kind)
                    && (root.detailPager.hasPrev || root.detailPager.hasNext)
                  width: parent.width
                  spacing: Style.space(6)
                  height: visible ? implicitHeight : 0

                  PanelActionButton {
                    iconText: "󰁍"
                    tooltipText: "Previous page"
                    foreground: root.contentForeground
                    fontFamily: root.contentFontFamily
                    enabled: root.detailPager.hasPrev
                    onClicked: if (root.service && root.detailSnap)
                      root.service.turnQueuePage(root.detailSnap.id, -1)
                  }

                  Text {
                    text: root.detailPager.label
                    color: root.dim
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                    verticalAlignment: Text.AlignVCenter
                    height: parent.height
                    textFormat: Text.PlainText
                  }

                  PanelActionButton {
                    iconText: "󰁔"
                    tooltipText: "Next page"
                    foreground: root.contentForeground
                    fontFamily: root.contentFontFamily
                    enabled: root.detailPager.hasNext
                    onClicked: if (root.service && root.detailSnap)
                      root.service.turnQueuePage(root.detailSnap.id, 1)
                  }
                }
                }

                Column {
                  width: parent.width
                  spacing: Style.space(8)
                  visible: root.detailSnap && root.detailSnap.kind === "sabnzbd"
                    && (root.detailSnap.activity || []).length > 0
                  height: visible ? implicitHeight : 0

                  PanelSectionHeader {
                    text: "HISTORY"
                    foreground: root.contentForeground
                    fontFamily: root.contentFontFamily
                  }

                  Repeater {
                    model: root.detailSnap && root.detailSnap.kind === "sabnzbd"
                      ? (root.detailSnap.activity || []) : []

                  Column {
                    required property var modelData
                    width: parent.width
                    spacing: Style.space(1)

                    Text {
                      width: parent.width
                      text: parent.modelData.title
                      color: root.contentForeground
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.caption
                      elide: Text.ElideRight
                      textFormat: Text.PlainText
                    }

                    Text {
                      width: parent.width
                      text: parent.modelData.status
                      color: parent.modelData.status === "failed" ? root.urgent : root.dim
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.caption
                      elide: Text.ElideRight
                      textFormat: Text.PlainText
                    }
                  }
                }
                }

                Column {
                  width: parent.width
                  spacing: Style.space(8)
                  visible: root.detailSnap && !Model.isMediaKind(root.detailSnap.kind)
                    && root.detailSnap.calendar && root.detailSnap.calendar.length > 0
                  height: visible ? implicitHeight : 0

                  Repeater {
                    model: root.detailSnap && !Model.isMediaKind(root.detailSnap.kind) && root.detailSnap.calendar
                      ? Model.groupedCalendar(root.detailSnap.calendar) : []

                  Column {
                    required property var modelData
                    width: parent.width
                    spacing: Style.space(10)

                    Text {
                      visible: parent.modelData.heading !== ""
                      width: parent.width
                      text: parent.modelData.heading
                      color: root.dim
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.caption
                      font.bold: true
                      textFormat: Text.PlainText
                    }

                    Repeater {
                      model: parent.modelData.items

                      CalendarCard {
                        required property var modelData
                        item: modelData
                        posterUrl: root.detailSnap ? root.posterSource(root.detailSnap.id, modelData.posterId) : ""
                        fanartUrl: root.detailSnap ? root.fanartSource(root.detailSnap.id, modelData.posterId) : ""
                        compact: root.compact
                        fontFamily: root.contentFontFamily
                      }
                    }
                  }
                }
                }
              }
            }
          }
        }
      }
    }
  }
}
}
