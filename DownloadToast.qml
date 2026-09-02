import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "Model.js" as Model

Item {
  id: root

  property var shell: null
  property var service: null
  property var job: null
  property bool showToast: true

  signal dismissRequested()

  readonly property var row: job && job.key ? job : null
  readonly property var jobs: row && row.jobs && row.jobs.length ? row.jobs : (row ? [row] : [])
  readonly property bool multi: jobs.length > 1
  readonly property int jobCount: row && row.count > 0 ? row.count : jobs.length
  readonly property int maxStackJobs: 6
  readonly property int stackCount: Math.min(jobs.length, maxStackJobs)
  readonly property int extraCount: Math.max(0, jobCount - maxStackJobs)
  readonly property bool opened: showToast && row
  readonly property string barPosition: shell && shell.barConfig ? String(shell.barConfig.position || "top") : "top"
  readonly property bool barVertical: barPosition === "left" || barPosition === "right"
  readonly property int defaultBarSize: barVertical ? Style.bar.sizeVertical : Style.bar.sizeHorizontal
  readonly property int liveBarSize: shell && shell.bar && !shell.bar.barHidden ? Math.max(0, shell.bar.barSize) : defaultBarSize
  readonly property int barClearance: liveBarSize + Style.gapsOut
  readonly property int topMargin: barPosition === "top" ? barClearance : Style.gapsOut
  readonly property int rightMargin: barPosition === "right" ? barClearance : Style.gapsOut
  readonly property string posterPath: {
    if (!service || !row || !row.posterId || !row.posterServiceId) return ""
    return service.posterPath(row.posterServiceId, row.posterId)
  }
  readonly property string posterUrl: {
    if (!posterPath) return ""
    var rev = service && service.artRev ? service.artRev[posterPath] : 0
    return Model.fileUrl(posterPath, rev || 0)
  }
  readonly property bool posterReady: posterImage.status === Image.Ready
  readonly property string metaLine: root.jobMeta(row)

  function jobMeta(item) {
    if (!item) return ""
    var parts = []
    if (item.serviceName) parts.push(item.serviceName)
    parts.push(Model.formatProgress(item.progress))
    if (item.speed > 0) parts.push(Model.formatSpeed(item.speed))
    var eta = Model.formatTimeLeft(item.timeleft)
    if (eta) parts.push(eta)
    return parts.join(" · ")
  }

  function jobAt(index) {
    var list = root.jobs
    if (!list || index < 0 || index >= list.length) return null
    return list[index]
  }

  function jobPosterUrl(item) {
    if (!service || !item || !item.posterId || !item.posterServiceId) return ""
    var path = service.posterPath(item.posterServiceId, item.posterId)
    var rev = service.artRev ? service.artRev[path] : 0
    return Model.fileUrl(path, rev || 0)
  }

  function summonPanel() {
    summonProc.command = ["omarchy-shell", "shell", "summon", Model.PLUGIN_ID, "{}"]
    summonProc.running = true
  }

  Process {
    id: summonProc
    running: false
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-omarr-progress"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    mask: Region { item: card }

    BorderSurface {
      id: card
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.topMargin: root.topMargin
      anchors.rightMargin: root.rightMargin
      implicitWidth: Style.space(380)
      implicitHeight: slot.height + borderTop + borderBottom
      radius: Style.cornerRadius
      color: Color.notifications.background
      borderSpec: Border.surfaceSpec("notifications", "border", Color.notifications.border, Math.max(1, Style.space(2)))
      clip: true

      Behavior on implicitHeight {
        NumberAnimation { duration: 280; easing.type: Easing.OutCubic }
      }

      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: function(mouse) {
          if (mouse.button === Qt.RightButton) root.dismissRequested()
          else root.summonPanel()
        }
      }

      Item {
        id: slot
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: card.borderTop
        anchors.leftMargin: card.borderLeft
        anchors.rightMargin: card.borderRight
        height: root.multi ? stack.implicitHeight : body.implicitHeight
        clip: true

        Behavior on height {
          NumberAnimation { duration: 280; easing.type: Easing.OutCubic }
        }

        RowLayout {
          id: body
          anchors.top: parent.top
          anchors.left: parent.left
          anchors.right: parent.right
          spacing: Style.space(12)
          opacity: root.multi ? 0 : 1
          visible: opacity > 0.01
          enabled: !root.multi

          Behavior on opacity {
            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
          }

          Item {
            Layout.preferredWidth: Style.space(56)
            Layout.preferredHeight: Style.space(56)
            Layout.leftMargin: Style.space(12)
            Layout.topMargin: Style.space(10)
            Layout.bottomMargin: Style.space(10)
            Layout.alignment: Qt.AlignTop

            Rectangle {
              anchors.fill: parent
              radius: Style.space(6)
              color: Qt.rgba(1, 1, 1, 0.08)
              clip: true

              Image {
                id: posterImage
                anchors.fill: parent
                visible: status === Image.Ready
                source: root.posterUrl
                sourceSize.width: Math.round(width * (Screen.devicePixelRatio || 1))
                sourceSize.height: Math.round(height * (Screen.devicePixelRatio || 1))
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                smooth: true
              }

              ServiceIcon {
                visible: !root.posterReady
                anchors.centerIn: parent
                iconSize: Style.space(28)
                service: root.row ? { kind: root.row.kind, name: root.row.serviceName } : ({})
              }
            }

            ServiceIcon {
              visible: root.posterReady
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              anchors.margins: Style.space(-2)
              iconSize: Style.space(16)
              service: root.row ? { kind: root.row.kind, name: root.row.serviceName } : ({})
            }
          }

          ColumnLayout {
            Layout.fillWidth: true
            Layout.rightMargin: Style.space(12)
            Layout.topMargin: Style.space(10)
            Layout.bottomMargin: Style.space(10)
            spacing: Style.space(4)

            RowLayout {
              Layout.fillWidth: true
              spacing: Style.space(8)

              Text {
                Layout.fillWidth: true
                text: root.row ? root.row.title : ""
                color: Color.notifications.text
                font.family: "Liberation Sans"
                font.pixelSize: Style.font.title
                font.bold: true
                elide: Text.ElideRight
                maximumLineCount: 2
                wrapMode: Text.WordWrap
                textFormat: Text.PlainText
              }

              Text {
                text: "󰅖"
                color: Qt.darker(Color.notifications.text, 1.4)
                font.pixelSize: Style.font.icon
                MouseArea {
                  anchors.fill: parent
                  anchors.margins: Style.space(-6)
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.dismissRequested()
                }
              }
            }

            Text {
              Layout.fillWidth: true
              visible: root.metaLine !== ""
              text: root.metaLine
              color: Qt.darker(Color.notifications.text, 1.4)
              font.family: "Liberation Sans"
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
              textFormat: Text.PlainText
            }

            Rectangle {
              Layout.fillWidth: true
              Layout.topMargin: Style.space(4)
              height: Style.space(4)
              radius: 2
              color: Qt.rgba(1, 1, 1, 0.12)

              Rectangle {
                width: parent.width * Math.max(0, Math.min(1, root.row ? root.row.progress : 0))
                height: parent.height
                radius: parent.radius
                color: Color.notifications.text
              }
            }
          }
        }

        Column {
          id: stack
          anchors.top: parent.top
          anchors.left: parent.left
          anchors.right: parent.right
          opacity: root.multi ? 1 : 0
          visible: opacity > 0.01
          enabled: root.multi
          spacing: Style.space(6)
          topPadding: Style.space(10)
          bottomPadding: Style.space(10)
          leftPadding: Style.space(12)
          rightPadding: Style.space(12)

          Behavior on opacity {
            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
          }

          Row {
            width: parent.width - parent.leftPadding - parent.rightPadding
            spacing: Style.space(8)

            Text {
              width: parent.width - closeGlyph.implicitWidth - parent.spacing
              text: root.jobCount === 1 ? "1 download" : (root.jobCount + " downloads")
              color: Color.notifications.text
              font.family: "Liberation Sans"
              font.pixelSize: Style.font.title
              font.bold: true
              elide: Text.ElideRight
              textFormat: Text.PlainText
            }

            Text {
              id: closeGlyph
              text: "󰅖"
              color: Qt.darker(Color.notifications.text, 1.4)
              font.pixelSize: Style.font.icon
              MouseArea {
                anchors.fill: parent
                anchors.margins: Style.space(-6)
                cursorShape: Qt.PointingHandCursor
                onClicked: root.dismissRequested()
              }
            }
          }

          Repeater {
            model: root.stackCount

            Item {
              id: jobRow
              required property int index
              readonly property var item: root.jobAt(index)
              width: stack.width - stack.leftPadding - stack.rightPadding
              height: Style.space(40)

              Row {
                anchors.fill: parent
                spacing: Style.space(8)

                Item {
                  width: Style.space(28)
                  height: Style.space(28)
                  anchors.verticalCenter: parent.verticalCenter

                  Rectangle {
                    anchors.fill: parent
                    radius: Style.space(4)
                    color: Qt.rgba(1, 1, 1, 0.08)
                    clip: true

                    Image {
                      id: rowPoster
                      anchors.fill: parent
                      visible: status === Image.Ready
                      source: root.jobPosterUrl(jobRow.item)
                      sourceSize.width: Math.round(width * (Screen.devicePixelRatio || 1))
                      sourceSize.height: Math.round(height * (Screen.devicePixelRatio || 1))
                      fillMode: Image.PreserveAspectCrop
                      asynchronous: true
                      smooth: true
                    }

                    ServiceIcon {
                      visible: rowPoster.status !== Image.Ready
                      anchors.centerIn: parent
                      iconSize: Style.space(16)
                      service: jobRow.item ? { kind: jobRow.item.kind, name: jobRow.item.serviceName } : ({})
                    }
                  }
                }

                Column {
                  width: parent.width - Style.space(28) - parent.spacing
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(3)

                  Text {
                    width: parent.width
                    text: jobRow.item ? jobRow.item.title : ""
                    color: Color.notifications.text
                    font.family: "Liberation Sans"
                    font.pixelSize: Style.font.bodySmall
                    font.bold: true
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                  }

                  Row {
                    width: parent.width
                    spacing: Style.space(8)

                    Rectangle {
                      width: parent.width - pct.implicitWidth - parent.spacing
                      height: Style.space(3)
                      anchors.verticalCenter: parent.verticalCenter
                      radius: 2
                      color: Qt.rgba(1, 1, 1, 0.12)

                      Rectangle {
                        width: parent.width * Math.max(0, Math.min(1, jobRow.item ? jobRow.item.progress : 0))
                        height: parent.height
                        radius: parent.radius
                        color: Color.notifications.text
                      }
                    }

                    Text {
                      id: pct
                      text: jobRow.item ? ((jobRow.item.serviceName ? jobRow.item.serviceName + " · " : "") + Model.formatProgress(jobRow.item.progress)) : ""
                      color: Qt.darker(Color.notifications.text, 1.4)
                      font.family: "Liberation Sans"
                      font.pixelSize: Style.font.caption
                      textFormat: Text.PlainText
                    }
                  }
                }
              }
            }
          }

          Text {
            visible: root.multi && root.extraCount > 0
            width: parent.width - parent.leftPadding - parent.rightPadding
            text: "+" + root.extraCount + " more"
            color: Qt.darker(Color.notifications.text, 1.4)
            font.family: "Liberation Sans"
            font.pixelSize: Style.font.caption
            textFormat: Text.PlainText
          }
        }
      }
    }
  }
}
