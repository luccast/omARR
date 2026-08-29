import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui
import "Model.js" as Model

Column {
  id: root

  property var service: null
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property bool compact: false

  readonly property color dim: Qt.darker(foreground, 1.4)
  readonly property var services: service && service.services ? service.services : []
  readonly property string fleetKey: Model.fleetOrderKey(root.services)
  readonly property var scanResults: service && service.scanResults ? service.scanResults : []
  readonly property bool scanning: service ? service.scanning === true : false
  readonly property bool editorOpen: kindBox.popupOpen || nameField.activeFocus || urlField.activeFocus
    || groupField.activeFocus || apiField.activeFocus || userField.activeFocus || passField.activeFocus

  property string mode: "list"
  property string editingId: ""
  property string formKind: "generic"
  property bool formNotifyGrab: true
  property bool formNotifyImport: true
  property bool formNotifyDownload: true
  property bool formNotifyHealth: true
  property bool formShowQueue: false
  property bool formShowCalendar: false
  property string listTab: "settings"

  readonly property bool needsKey: Model.kindNeedsApiKey(formKind)
  readonly property bool needsUser: Model.kindNeedsUserPass(formKind)
  readonly property bool needsUsername: Model.kindNeedsUsername(formKind)

  signal closeSettings()

  function setFormKind(kind) {
    formKind = Model.kindOf(kind)
    kindBox.value = formKind
  }

  function resetForm() {
    setFormKind("generic")
    nameField.text = ""
    urlField.text = Model.defaultUrlForKind("generic")
    groupField.text = ""
    apiField.text = ""
    userField.text = ""
    passField.text = ""
    formNotifyGrab = true
    formNotifyImport = true
    formNotifyDownload = true
    formNotifyHealth = true
    formShowQueue = false
    formShowCalendar = false
    editingId = ""
  }

  function fillKind(kind) {
    var previous = formKind
    setFormKind(kind)
    var prevLabel = Model.kindLabel(previous)
    if (!nameField.text || nameField.text === prevLabel)
      nameField.text = Model.uniqueServiceName(root.services, formKind, editingId)
    if (!urlField.text || urlField.text.indexOf("127.0.0.1") !== -1)
      urlField.text = Model.defaultUrlForKind(formKind)
    if (!root.editingId && (!groupField.text || groupField.text === Model.kindGroup(previous)))
      groupField.text = Model.kindGroup(formKind)
    if (!root.editingId) {
      formShowQueue = formKind === "sabnzbd" || formKind === "qbittorrent"
      formShowCalendar = formKind === "sonarr" || formKind === "radarr"
    }
  }

  function startAdd() {
    listTab = "fleet"
    resetForm()
    mode = "edit"
  }

  function showFleet() {
    resetForm()
    mode = "list"
    listTab = "fleet"
  }

  function startEdit(row) {
    if (!row) return
    listTab = "fleet"
    mode = "edit"
    editingId = row.id
    setFormKind(row.kind)
    nameField.text = row.name
    urlField.text = row.url
    groupField.text = row.group
    formNotifyGrab = row.notifyGrab !== false
    formNotifyImport = row.notifyImport !== false
    formNotifyDownload = row.notifyDownload !== false
    formNotifyHealth = row.notifyHealth !== false
    formShowQueue = row.showQueue === true
    formShowCalendar = row.showCalendar === true
    var cred = root.service ? root.service.cred(row.id) : { apiKey: "", username: "", password: "" }
    apiField.text = cred.apiKey
    userField.text = cred.username
    passField.text = cred.password
  }

  function saveForm() {
    if (!root.service) return
    var draft = {
      kind: formKind,
      name: nameField.text,
      url: urlField.text,
      group: Model.normalizeGroup(groupField.text, ""),
      notifyGrab: formNotifyGrab,
      notifyImport: formNotifyImport,
      notifyDownload: formNotifyDownload,
      notifyHealth: formNotifyHealth,
      showQueue: formShowQueue,
      showCalendar: formShowCalendar
    }
    var creds = {
      apiKey: apiField.text,
      username: userField.text,
      password: passField.text
    }
    if (editingId) root.service.updateService(editingId, draft, creds)
    else root.service.addService(draft, creds)
    resetForm()
    mode = "list"
  }

  function applyScan(hit) {
    startAdd()
    setFormKind(hit.kind)
    nameField.text = Model.uniqueServiceName(root.services, formKind)
    urlField.text = hit.url
    groupField.text = Model.kindGroup(hit.kind)
    formShowQueue = formKind === "sabnzbd" || formKind === "qbittorrent"
    formShowCalendar = formKind === "sonarr" || formKind === "radarr"
  }

  width: parent ? parent.width : implicitWidth
  spacing: root.compact ? Style.space(6) : Style.space(8)

  Item {
    width: parent.width
    height: Math.max(header.implicitHeight, listTabs.implicitHeight, headerActions.implicitHeight)

    PanelSectionHeader {
      id: header
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      visible: root.mode === "edit"
      text: root.editingId ? "EDIT SERVICE" : "ADD SERVICE"
      foreground: root.foreground
      fontFamily: root.fontFamily
    }

    Flow {
      id: listTabs
      anchors.left: parent.left
      anchors.right: headerActions.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(12)
      visible: root.mode === "list"

      Repeater {
        model: [
          { "id": "settings", "label": "SETTINGS" },
          { "id": "fleet", "label": "FLEET" }
        ]

        Item {
          id: listTabChip
          required property var modelData
          width: listTabLabel.implicitWidth
          height: listTabLabel.implicitHeight + Style.space(6)

          Text {
            id: listTabLabel
            text: listTabChip.modelData.label
            color: root.listTab === listTabChip.modelData.id ? root.foreground : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            textFormat: Text.PlainText
          }

          Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 1
            visible: root.listTab === listTabChip.modelData.id
            color: root.foreground
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.listTab = listTabChip.modelData.id
          }
        }
      }
    }

    Row {
      id: headerActions
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(2)

      PanelActionButton {
        visible: root.mode === "list" && root.listTab === "fleet"
        iconText: "󰐕"
        tooltipText: "Add service"
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: root.startAdd()
      }

      PanelActionButton {
        visible: root.mode === "list" && root.listTab === "fleet"
        iconText: "󰍉"
        tooltipText: root.scanning ? "Scanning…" : "Scan local ports"
        foreground: root.scanning ? Color.accent : root.foreground
        fontFamily: root.fontFamily
        onClicked: if (root.service) root.service.startScan()
      }

      PanelActionButton {
        iconText: "󰅖"
        tooltipText: root.mode === "edit" ? "Back" : "Close settings"
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: {
          if (root.mode === "edit") {
            root.resetForm()
            root.mode = "list"
          } else {
            root.closeSettings()
          }
        }
      }
    }
  }

  Column {
    width: parent.width
    spacing: Style.space(12)
    visible: root.mode === "list" && root.listTab === "settings"
    height: visible ? implicitHeight : 0

    Grid {
      width: parent.width
      columns: 3
      columnSpacing: Style.space(12)

      NumberField {
        width: Math.max(0, (parent.width - parent.columnSpacing * 2) / 3)
        label: "Poll interval (seconds)"
        value: root.service ? root.service.pollSeconds : 30
        from: 5
        to: 3600
        stepSize: 5
        foreground: root.foreground
        fontFamily: root.fontFamily
        onModified: function(v) { if (root.service) root.service.persistSettings({ pollSeconds: v }) }
      }

      NumberField {
        width: Math.max(0, (parent.width - parent.columnSpacing * 2) / 3)
        label: "Queue page size"
        value: root.service ? root.service.pageSize : Model.LIST_PAGE_SIZE
        from: Model.PAGE_SIZE_MIN
        to: Model.PAGE_SIZE_MAX
        stepSize: 5
        foreground: root.foreground
        fontFamily: root.fontFamily
        onModified: function(v) {
          if (!root.service) return
          root.service.persistSettings({ pageSize: v })
          root.service.clearDetailQueue()
          root.service.forcePoll()
        }
      }
    }

    Toggle {
      width: parent.width
      label: "Compact density"
      description: "Tighter fleet rows"
      checked: root.compact
      foreground: root.foreground
      fontFamily: root.fontFamily
      onClicked: if (root.service)
        root.service.persistSettings({ density: root.compact ? "comfortable" : "compact" })
    }

    Toggle {
      width: parent.width
      label: "Download progress"
      description: "Keep a card on screen while something is downloading"
      checked: root.service ? root.service.showProgressToast !== false : true
      foreground: root.foreground
      fontFamily: root.fontFamily
      onClicked: if (root.service)
        root.service.persistSettings({ showProgressToast: !root.service.showProgressToast })
    }
  }

  Column {
    width: parent.width
    spacing: Style.space(8)
    visible: root.mode === "list" && root.listTab === "fleet"
    height: visible ? implicitHeight : 0

    Text {
      visible: root.scanning
      width: parent.width
      text: "Pinging common ports on this machine…"
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.italic: true
    }

    Column {
      width: parent.width
      spacing: Style.space(4)
      visible: root.scanResults.length > 0
      height: visible ? implicitHeight : 0

      Text {
        width: parent.width
        text: "Found on localhost"
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
      }

      Repeater {
        model: root.scanResults

        CursorSurface {
          id: scanRow
          required property var modelData
          width: parent.width
          implicitHeight: scanLabel.implicitHeight + Style.space(10)
          hasCursor: scanMouse.containsMouse
          foreground: root.foreground
          accent: Color.accent

          Row {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: Style.space(6)
            spacing: Style.space(8)

            ServiceIcon {
              id: scanIcon
              service: scanRow.modelData
              iconSize: Style.space(16)
              anchors.verticalCenter: parent.verticalCenter
            }

            Text {
              id: scanLabel
              width: parent.width - scanIcon.width - parent.spacing
              text: scanRow.modelData.name + " · " + scanRow.modelData.url
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideRight
              textFormat: Text.PlainText
            }
          }

          MouseArea {
            id: scanMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.applyScan(scanRow.modelData)
          }
        }
      }
    }

    Text {
      visible: root.services.length === 0 && root.scanResults.length === 0 && !root.scanning
      width: parent.width
      text: "No services yet. Add one, or scan this machine for Sonarr, Radarr, and friends."
      wrapMode: Text.WordWrap
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      font.italic: true
    }

    Repeater {
      model: {
        var _ = root.fleetKey
        return Model.groupedServices(root.services)
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
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
          textFormat: Text.PlainText
        }

        Repeater {
          model: parent.modelData.services

          CursorSurface {
            id: svcRow
            required property var modelData
            required property int index
            width: parent.width
            implicitHeight: svcCol.implicitHeight + Style.space(10)
            hasCursor: svcMouse.containsMouse
            foreground: root.foreground
            accent: Color.accent

            MouseArea {
              id: svcMouse
              z: -1
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.startEdit(svcRow.modelData)
            }

            Row {
              anchors.fill: parent
              anchors.margins: Style.space(6)
              spacing: Style.space(6)

              ServiceIcon {
                id: svcIcon
                service: svcRow.modelData
                iconSize: Style.space(16)
                anchors.verticalCenter: parent.verticalCenter
              }

              Column {
                id: svcCol
                width: parent.width - svcIcon.width - parent.spacing - Style.space(72)
                spacing: Style.space(1)

                Text {
                  width: parent.width
                  text: svcRow.modelData.name
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                  elide: Text.ElideRight
                  textFormat: Text.PlainText
                }

                Text {
                  width: parent.width
                  text: Model.kindLabel(svcRow.modelData.kind) + " · " + (svcRow.modelData.url || "no url")
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                  textFormat: Text.PlainText
                }
              }

              PanelActionButton {
                iconText: "󰁝"
                tooltipText: "Move up"
                foreground: root.foreground
                fontFamily: root.fontFamily
                enabled: svcRow.index > 0
                onClicked: if (root.service) root.service.moveService(svcRow.modelData.id, -1)
              }

              PanelActionButton {
                iconText: "󰁅"
                tooltipText: "Move down"
                foreground: root.foreground
                fontFamily: root.fontFamily
                enabled: svcRow.index < svcRow.parent.modelData.services.length - 1
                onClicked: if (root.service) root.service.moveService(svcRow.modelData.id, 1)
              }

              PanelActionButton {
                iconText: "󰆴"
                tooltipText: "Remove"
                foreground: root.foreground
                hoverColor: Color.urgent
                fontFamily: root.fontFamily
                onClicked: if (root.service) root.service.removeService(svcRow.modelData.id)
              }
            }
          }
        }
      }
    }
  }

  Column {
    width: parent.width
    spacing: Style.space(8)
    visible: root.mode === "edit"
    height: visible ? implicitHeight : 0

    Dropdown {
      id: kindBox
      width: parent.width
      label: "Kind"
      value: root.formKind
      foreground: root.foreground
      fontFamily: root.fontFamily
      options: [
        { value: "generic", label: "Generic" },
        { value: "sonarr", label: "Sonarr" },
        { value: "radarr", label: "Radarr" },
        { value: "plex", label: "Plex" },
        { value: "jellyfin", label: "Jellyfin" },
        { value: "sabnzbd", label: "SABnzbd" },
        { value: "qbittorrent", label: "qBittorrent" }
      ]
      onChanged: function(v) { root.fillKind(v) }
    }

    TextField {
      id: nameField
      width: parent.width
      placeholderText: "Name"
      foreground: root.foreground
    }

    TextField {
      id: urlField
      width: parent.width
      placeholderText: "http://127.0.0.1:8989"
      foreground: root.foreground
    }

    TextField {
      id: groupField
      width: parent.width
      placeholderText: "Group (optional)"
      foreground: root.foreground
    }

    TextField {
      id: apiField
      width: parent.width
      visible: root.needsKey
      height: visible ? implicitHeight : 0
      password: true
      placeholderText: root.formKind === "plex" ? "Plex token"
        : root.formKind === "jellyfin" ? "Jellyfin API key" : "API key"
      foreground: root.foreground
    }

    TextField {
      id: userField
      width: parent.width
      visible: root.needsUsername
      height: visible ? implicitHeight : 0
      placeholderText: root.formKind === "jellyfin" ? "Profile name (optional)" : "Username"
      foreground: root.foreground
    }

    TextField {
      id: passField
      width: parent.width
      visible: root.needsUser
      height: visible ? implicitHeight : 0
      password: true
      placeholderText: "Password"
      foreground: root.foreground
    }

    Toggle {
      width: parent.width
      visible: root.formKind === "sonarr" || root.formKind === "radarr" || root.formKind === "sabnzbd" || root.formKind === "qbittorrent"
      height: visible ? implicitHeight : 0
      label: "Show queue on Overview"
      checked: root.formShowQueue
      foreground: root.foreground
      fontFamily: root.fontFamily
      onClicked: root.formShowQueue = !root.formShowQueue
    }

    Toggle {
      width: parent.width
      visible: root.formKind === "sonarr" || root.formKind === "radarr"
      height: visible ? implicitHeight : 0
      label: "Show calendar on Overview"
      checked: root.formShowCalendar
      foreground: root.foreground
      fontFamily: root.fontFamily
      onClicked: root.formShowCalendar = !root.formShowCalendar
    }

    Toggle {
      width: parent.width
      visible: root.formKind === "sonarr" || root.formKind === "radarr" || Model.isMediaKind(root.formKind)
      height: visible ? implicitHeight : 0
      label: Model.isMediaKind(root.formKind) ? "Notify on newly added" : "Notify on grab"
      checked: root.formNotifyGrab
      foreground: root.foreground
      fontFamily: root.fontFamily
      onClicked: root.formNotifyGrab = !root.formNotifyGrab
    }

    Toggle {
      width: parent.width
      visible: root.formKind === "sonarr" || root.formKind === "radarr"
      height: visible ? implicitHeight : 0
      label: "Notify on import"
      checked: root.formNotifyImport
      foreground: root.foreground
      fontFamily: root.fontFamily
      onClicked: root.formNotifyImport = !root.formNotifyImport
    }

    Toggle {
      width: parent.width
      visible: root.formKind === "sabnzbd" || root.formKind === "qbittorrent"
      height: visible ? implicitHeight : 0
      label: "Notify when downloads finish"
      checked: root.formNotifyDownload
      foreground: root.foreground
      fontFamily: root.fontFamily
      onClicked: root.formNotifyDownload = !root.formNotifyDownload
    }

    Toggle {
      width: parent.width
      visible: root.formKind === "sonarr" || root.formKind === "radarr"
      height: visible ? implicitHeight : 0
      label: "Notify on download fail"
      checked: root.formNotifyDownload
      foreground: root.foreground
      fontFamily: root.fontFamily
      onClicked: root.formNotifyDownload = !root.formNotifyDownload
    }

    Toggle {
      width: parent.width
      label: "Notify on health changes"
      checked: root.formNotifyHealth
      foreground: root.foreground
      fontFamily: root.fontFamily
      onClicked: root.formNotifyHealth = !root.formNotifyHealth
    }

    Button {
      text: "Save"
      foreground: root.foreground
      onClicked: root.saveForm()
    }
  }
}
