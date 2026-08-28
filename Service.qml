import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

Item {
  id: root

  property var shell: null
  property bool panelOpen: false
  property bool scanning: false
  property var scanResults: []
  property var credentials: ({})
  property var seenIds: []
  property var snapshots: []
  property var nowFeed: ({ downloads: [], calendar: [], warnings: [], sessions: [], onDeck: [], recent: [], downloadingCount: 0, downCount: 0 })
  property var qbitReady: ({})
  property var detailQueue: []
  property int detailQueuePage: 1
  property int detailQueueTotal: 0
  property string detailQueueId: ""
  property string statusText: "omARR"
  property int unreadCount: 0
  property var artReady: ({})
  property var artPending: ({})
  property var artRev: ({})
  property var onDeckFeed: []
  property var recentFeed: []
  property var calendarFeed: []
  property int badgeCount: 0
  property bool badgeUrgent: false
  property bool seeding: true
  property bool dirsReady: false
  property var toastQueue: []
  property string progressDismissedKey: ""
  property var progressJob: null

  readonly property string home: Quickshell.env("HOME")
  readonly property string stateDir: home + "/.local/state/omarchy/omarr"
  readonly property string cacheDir: home + "/.cache/omarchy/omarr"
  readonly property string credsPath: stateDir + "/credentials.json"
  readonly property string seenPath: stateDir + "/seen.json"
  readonly property string headerPath: cacheDir + "/header.txt"
  readonly property string bodyPath: cacheDir + "/body.txt"
  property var pluginSettings: Model.pluginSettings(null, Model.PLUGIN_ID)
  readonly property var services: pluginSettings.services
  readonly property int pollSeconds: pluginSettings.pollSeconds
  readonly property int pageSize: pluginSettings.pageSize
  readonly property string density: pluginSettings.density
  readonly property bool showProgressToast: pluginSettings.showProgressToast !== false
  readonly property bool configured: services.length > 0

  property var reqQueue: []
  property var currentReq: null
  property bool writingFiles: false
  property var snapshotMap: ({})
  property var healthMisses: ({})

  function cookiePath(id) {
    return cacheDir + "/qbit-" + String(id || "").replace(/[^A-Za-z0-9._-]/g, "_") + ".cookies"
  }

  function serviceById(id) {
    var key = String(id || "")
    for (var i = 0; i < root.services.length; i++) {
      if (root.services[i].id === key) return root.services[i]
    }
    return null
  }

  function persistSettings(values) {
    var current = Model.normalizeSettings(root.pluginSettings)
    var extra = values && typeof values === "object" ? values : {}
    for (var key in extra) current[key] = extra[key]
    current = Model.normalizeSettings(current)
    var payload = Model.settingsPayload(current)
    if (root.shell && typeof root.shell.updateEntryInline === "function")
      root.shell.updateEntryInline(Model.PLUGIN_ID, payload)
    root.pluginSettings = current
  }

  function persistCredentials() {
    credsFile.setText(Model.serializeCredentials(root.credentials))
    chmodStateProc.command = ["chmod", "600", credsPath]
    chmodStateProc.running = true
  }

  function persistSeen() {
    seenFile.setText(Model.serializeSeenFile(root.seenIds))
  }

  function persistCredential(id, patch) {
    root.credentials = Model.setCredential(root.credentials, id, patch)
    persistCredentials()
  }

  function addService(draft, creds) {
    var next = Model.addService(root.pluginSettings, draft)
    persistSettings(next)
    if (creds && next.services.length) {
      var added = next.services[next.services.length - 1]
      persistCredential(added.id, creds)
    }
    Qt.callLater(root.forcePoll)
  }

  function updateService(id, patch, creds) {
    persistSettings(Model.updateService(root.pluginSettings, id, patch))
    if (creds) persistCredential(id, creds)
    Qt.callLater(root.forcePoll)
  }

  function removeService(id) {
    persistSettings(Model.removeService(root.pluginSettings, id))
    var creds = {}
    for (var key in root.credentials) {
      if (key === String(id)) continue
      creds[key] = root.credentials[key]
    }
    root.credentials = creds
    persistCredentials()
    Qt.callLater(root.rebuildSnapshots)
  }

  function moveService(id, delta) {
    persistSettings(Model.moveService(root.pluginSettings, id, delta))
  }

  function openUrl(url) {
    if (!Model.isHttpUrl(url)) return
    openProc.command = ["omarchy", "launch", "browser", url]
    openProc.running = true
  }

  function openService(id) {
    var snap = Model.snapshotById(root.snapshots, id)
    if (snap && snap.url) root.openUrl(snap.url)
  }

  function cred(id) {
    return Model.credentialFor(root.credentials, id)
  }

  function enqueue(req) {
    root.reqQueue = root.reqQueue.concat([req])
    root.pump()
  }

  function pump() {
    if (!root.dirsReady || apiProc.running || root.writingFiles) return
    if (!root.reqQueue.length) {
      root.refreshDerived()
      return
    }
    var next = root.reqQueue[0]
    root.reqQueue = root.reqQueue.slice(1)
    root.startReq(next)
  }

  function startReq(req) {
    root.currentReq = req
    if (req.headerText) {
      req.useCurlConfig = Model.headerIsConfig(req.headerText)
      headerFile.setText(req.useCurlConfig ? Model.curlHeaderConfig(req.headerText) : req.headerText)
      headerFile.waitForJob()
    }
    if (req.bodyText) {
      bodyFile.setText(req.bodyText)
      bodyFile.waitForJob()
    }
    var chmod = ["chmod", "600"]
    if (req.headerText) chmod.push(root.headerPath)
    if (req.bodyText) chmod.push(root.bodyPath)
    if (chmod.length > 2) {
      root.writingFiles = true
      chmodProc.command = chmod
      chmodProc.running = true
      return
    }
    root.runCurl(req)
  }

  function setHealthMisses(id, n) {
    var next = {}
    for (var key in root.healthMisses) next[key] = root.healthMisses[key]
    next[String(id)] = n
    root.healthMisses = next
  }

  function commitHealth(service, snap, statusCode) {
    var decision = Model.decideHealth(
      root.snapshotFor(service).health,
      statusCode,
      root.healthMisses[service.id] || 0
    )
    root.setHealthMisses(service.id, decision.misses)
    if (!decision.commit) return false
    root.commitSnapshot(Model.applyHttpHealth(snap, statusCode), service)
    return true
  }

  function commitIdentity(service, snap, statusCode, info) {
    var decision = Model.decideHealth(
      root.snapshotFor(service).health,
      statusCode,
      root.healthMisses[service.id] || 0
    )
    root.setHealthMisses(service.id, decision.misses)
    if (!decision.commit) return
    if (statusCode < 200 || statusCode >= 400) {
      root.commitSnapshot(Model.applyHttpHealth(snap, statusCode), service)
      return
    }
    var next = Model.applyHttpHealth(snap, statusCode)
    var row = info && typeof info === "object" ? info : {}
    next.version = String(row.version || "")
    next.statusText = String(row.statusText || next.version || "Reachable")
    root.commitSnapshot(next, service)
  }

  function runCurl(req) {
    if (!req || !Model.isHttpUrl(req.url)) {
      Qt.callLater(root.pump)
      return
    }
    var max = req.image ? Model.IMAGE_MAX_BYTES : Model.API_MAX_BYTES
    var cmd = ["curl", "-sS", "-w", "\n%{http_code}", "--proto", "=http,https"]
    cmd = cmd.concat(req.scan ? Model.scanCurlBounds() : Model.curlBounds(max))
    if (req.method === "POST") cmd.push("-X", "POST")
    if (req.headerText) {
      if (req.useCurlConfig) cmd.push("--config", root.headerPath)
      else cmd.push("-H", "@" + root.headerPath)
    }
    if (req.bodyText) {
      cmd.push("-H", "Content-Type: application/x-www-form-urlencoded")
      cmd.push("--data-binary", "@" + root.bodyPath)
    }
    if (req.cookieRead) cmd.push("-b", req.cookieRead)
    if (req.cookieWrite) cmd.push("-c", req.cookieWrite)
    if (req.outputPath) cmd.push("-o", req.outputPath)
    cmd.push("--", req.url)
    apiProc.command = cmd
    apiProc.running = true
  }

  function snapshotFor(service) {
    var existing = root.snapshotMap[service.id]
    return existing ? existing : Model.emptySnapshot(service)
  }

  function cloneSnap(snap) {
    var next = Model.emptySnapshot(snap)
    var keys = ["health", "statusText", "version", "paused", "speed", "queue", "queuePage", "queueTotal", "calendar", "activity", "wanted", "sessions", "onDeck", "recent"]
    for (var i = 0; i < keys.length; i++) next[keys[i]] = snap[keys[i]]
    return next
  }

  function setDetailQueue(id, page, items, total) {
    root.detailQueueId = String(id || "")
    root.detailQueuePage = Model.listPage(page)
    root.detailQueue = items || []
    root.detailQueueTotal = parseInt(total, 10) || 0
  }

  function clearDetailQueue() {
    root.detailQueueId = ""
    root.detailQueuePage = 1
    root.detailQueue = []
    root.detailQueueTotal = 0
  }

  function turnQueuePage(serviceId, delta) {
    var service = root.serviceById(serviceId)
    if (!service) return
    var current = root.detailQueueId === serviceId ? root.detailQueuePage : 1
    var page = Model.listPage(current + (parseInt(delta, 10) || 0))
    if (page <= 1) {
      root.clearDetailQueue()
      return
    }
    var auth = root.cred(service.id)
    if (service.kind === "sonarr" || service.kind === "radarr") {
      root.enqueue({
        kind: "arr-queue",
        serviceId: service.id,
        url: Model.arrQueueUrl(service.url, page, root.pageSize),
        headerText: auth.apiKey ? Model.headerApiKey(auth.apiKey) : "",
        page: page
      })
    } else if (service.kind === "sabnzbd") {
      root.enqueue({
        kind: "sab-queue",
        serviceId: service.id,
        url: Model.sabApiUrl(service.url),
        method: "POST",
        bodyText: Model.sabBody(auth.apiKey, "queue", { start: String(Model.listOffset(page, root.pageSize)) }, root.pageSize),
        page: page
      })
    } else if (service.kind === "qbittorrent") {
      var ready = root.qbitReady[service.id] === true
      root.enqueue({
        kind: "qbit-torrents",
        serviceId: service.id,
        url: Model.qbitTorrentsUrl(service.url, page, root.pageSize),
        cookieRead: ready ? root.cookiePath(service.id) : "",
        page: page
      })
    } else {
      return
    }
    root.pump()
  }

  function commitSnapshot(next, service, seedEvents) {
    var prev = root.snapshotMap[next.id] || Model.emptySnapshot(service)
    var events = Model.eventsFromPoll(prev, next, service)
    var ids = []
    for (var i = 0; i < events.length; i++) ids.push(events[i].id)
    if (root.seeding || seedEvents) {
      root.seenIds = Model.rememberIds(root.seenIds, ids)
    } else {
      for (var e = 0; e < events.length; e++) {
        if (!Model.shouldNotify(events[e], service, root.seenIds)) continue
        root.sendToast(events[e])
        root.seenIds = Model.rememberIds(root.seenIds, [events[e].id])
      }
    }
    var map = {}
    for (var key in root.snapshotMap) map[key] = root.snapshotMap[key]
    map[next.id] = next
    root.snapshotMap = map
    root.rebuildSnapshotList()
  }

  function rebuildSnapshotList() {
    var list = []
    for (var i = 0; i < root.services.length; i++) {
      var svc = root.services[i]
      list.push(Model.applyServiceMeta(root.snapshotMap[svc.id] || Model.emptySnapshot(svc), svc))
    }
    root.snapshots = list
    root.refreshDerived()
  }

  function rebuildSnapshots() {
    var map = {}
    for (var i = 0; i < root.services.length; i++) {
      var svc = root.services[i]
      map[svc.id] = Model.applyServiceMeta(root.snapshotMap[svc.id] || Model.emptySnapshot(svc), svc)
    }
    root.snapshotMap = map
    root.rebuildSnapshotList()
  }

  function refreshDerived() {
    var next = Model.mergeNow(root.snapshots)
    var deck = Model.reuseFeedList(root.onDeckFeed, next.onDeck)
    var recent = Model.reuseFeedList(root.recentFeed, next.recent)
    var calendar = Model.reuseFeedList(root.calendarFeed, next.calendar)
    if (deck !== root.onDeckFeed) root.onDeckFeed = deck
    if (recent !== root.recentFeed) root.recentFeed = recent
    if (calendar !== root.calendarFeed) root.calendarFeed = calendar
    next.onDeck = root.onDeckFeed
    next.recent = root.recentFeed
    next.calendar = root.calendarFeed
    root.nowFeed = next
    root.statusText = root.configured ? Model.barStatusText(root.snapshots) : "Add a service"
    var badge = Model.barBadge(root.snapshots)
    root.badgeCount = badge.count
    root.badgeUrgent = badge.urgent === true
    if (Model.progressToastStale(root.progressDismissedKey, root.snapshots))
      root.progressDismissedKey = ""
    root.progressJob = Model.progressToast(root.snapshots, root.progressDismissedKey)
    root.ensureProgressArt(root.progressJob)
  }

  function dismissProgressToast() {
    if (root.progressJob && root.progressJob.key)
      root.progressDismissedKey = root.progressJob.key
    root.progressJob = Model.progressToast(root.snapshots, root.progressDismissedKey)
  }

  function ensureProgressArt(job) {
    if (!job || !job.posterId || !job.posterServiceId) return
    var service = root.serviceById(job.posterServiceId)
    if (!service || (service.kind !== "sonarr" && service.kind !== "radarr")) return
    var auth = root.cred(service.id)
    var header = auth.apiKey ? Model.headerApiKey(auth.apiKey) : ""
    root.enqueueArt({
      kind: "poster",
      serviceId: service.id,
      url: Model.arrPosterUrl(service.url, service.kind, job.posterId),
      headerText: header,
      outputPath: Model.posterCachePath(root.cacheDir, service.id, job.posterId),
      image: true
    })
  }

  function sendToast(event) {
    root.toastQueue = root.toastQueue.concat([Model.toastCommand(event)])
    root.unreadCount += 1
    root.pumpToasts()
  }

  function pumpToasts() {
    if (toastProc.running || !root.toastQueue.length) return
    var next = root.toastQueue.slice()
    toastProc.command = next.shift()
    root.toastQueue = next
    toastProc.running = true
  }

  function clearUnread() {
    root.unreadCount = 0
  }

  function handleSuccess(text) {
    var req = root.currentReq
    if (!req) return
    var parsed = Model.splitHttp(text)
    if (req.kind === "scan") {
      root.handleScan(req, parsed.status)
      return
    }
    var service = root.serviceById(req.serviceId)
    if (!service) return
    if (req.kind === "poster") {
      root.finishArt(req.outputPath, parsed.status >= 200 && parsed.status < 400)
      return
    }
    var snap = Model.applyServiceMeta(root.cloneSnap(root.snapshotFor(service)), service)
    if (req.kind === "generic") {
      root.commitHealth(service, snap, parsed.status)
      return
    }
    if (req.kind === "arr-status") {
      var status = Model.parseArrStatus(parsed.body)
      root.commitIdentity(service, snap, parsed.status, {
        version: status.version,
        statusText: status.appName ? status.appName + " " + status.version : status.version
      })
      return
    }
    if (req.kind === "arr-queue") {
      if (parsed.status >= 200 && parsed.status < 400) {
        var arrItems = Model.parseArrQueue(parsed.body, service.kind, root.pageSize)
        var arrTotal = Model.arrTotalRecords(parsed.body)
        if (req.page > 1) {
          root.setDetailQueue(service.id, req.page, arrItems, arrTotal)
          return
        }
        snap.queue = arrItems
        snap.queueTotal = arrTotal
        snap.queuePage = 1
        root.commitSnapshot(snap, service)
        if (root.panelOpen) root.enqueuePosters(service, snap)
      }
      return
    }
    if (req.kind === "arr-calendar") {
      if (parsed.status >= 200 && parsed.status < 400) {
        snap.calendar = Model.parseArrCalendar(parsed.body, service.kind, root.pageSize)
        root.commitSnapshot(snap, service)
        if (root.panelOpen) root.enqueuePosters(service, snap)
      }
      return
    }
    if (req.kind === "arr-wanted") {
      if (parsed.status >= 200 && parsed.status < 400) {
        snap.wanted = Model.parseArrWanted(parsed.body, service.kind)
        root.commitSnapshot(snap, service)
      }
      return
    }
    if (req.kind === "arr-history") {
      if (parsed.status >= 200 && parsed.status < 400) {
        snap.activity = Model.parseArrHistory(parsed.body, service.kind)
        root.commitSnapshot(snap, service)
      }
      return
    }
    if (req.kind === "sab-queue") {
      if (parsed.status < 200 || parsed.status >= 400) {
        if (!(req.page > 1)) root.commitHealth(service, snap, parsed.status)
        return
      }
      var sab = Model.parseSabQueue(parsed.body, root.pageSize)
      if (req.page > 1) {
        root.setDetailQueue(service.id, req.page, sab.queue, sab.total)
        return
      }
      root.setHealthMisses(service.id, 0)
      snap = Model.applyHttpHealth(snap, parsed.status)
      snap.paused = sab.paused
      snap.speed = sab.speed
      snap.queue = sab.queue
      snap.queueTotal = sab.total
      snap.queuePage = 1
      snap.statusText = sab.paused ? "Paused" : (sab.speed ? Model.formatSpeed(sab.speed) : "Idle")
      root.commitSnapshot(snap, service)
      return
    }
    if (req.kind === "sab-history") {
      if (parsed.status >= 200 && parsed.status < 400) {
        snap.activity = Model.parseSabHistory(parsed.body)
        root.commitSnapshot(snap, service)
      }
      return
    }
    if (req.kind === "qbit-login") {
      var ready = {}
      for (var rk in root.qbitReady) ready[rk] = root.qbitReady[rk]
      ready[service.id] = parsed.status >= 200 && parsed.status < 400 && String(parsed.body).indexOf("Fails") === -1
      root.qbitReady = ready
      if (ready[service.id]) {
        root.enqueueQbit(service, true)
      } else {
        root.commitHealth(service, snap, parsed.status || 401)
      }
      return
    }
    if (req.kind === "qbit-torrents") {
      if (parsed.status === 403 || parsed.status === 401) {
        var reset = {}
        for (var qk in root.qbitReady) reset[qk] = root.qbitReady[qk]
        reset[service.id] = false
        root.qbitReady = reset
        root.enqueueQbitLogin(service)
        return
      }
      if (parsed.status < 200 || parsed.status >= 400) {
        if (!(req.page > 1)) root.commitHealth(service, snap, parsed.status)
        return
      }
      var qbitItems = Model.parseQbitTorrents(parsed.body, root.pageSize)
      if (req.page > 1) {
        root.setDetailQueue(service.id, req.page, qbitItems, 0)
        return
      }
      root.setHealthMisses(service.id, 0)
      snap = Model.applyHttpHealth(snap, parsed.status)
      snap.queue = qbitItems
      snap.queueTotal = 0
      snap.queuePage = 1
      root.commitSnapshot(snap, service)
      return
    }
    if (req.kind === "qbit-transfer") {
      if (parsed.status >= 200 && parsed.status < 400) {
        var xfer = Model.parseQbitTransfer(parsed.body)
        snap.speed = xfer.speed
        if (snap.health === "up")
          snap.statusText = xfer.speed ? Model.formatSpeed(xfer.speed) : "Idle"
        root.commitSnapshot(snap, service)
      }
      return
    }
    if (req.kind === "plex-identity") {
      var ident = Model.parsePlexIdentity(parsed.body)
      root.commitIdentity(service, snap, parsed.status, {
        version: ident.version,
        statusText: ident.version || "Reachable"
      })
      return
    }
    if (req.kind === "plex-sessions") {
      if (parsed.status >= 200 && parsed.status < 400) {
        snap.sessions = Model.parsePlexSessions(parsed.body, root.pageSize)
        root.commitSnapshot(snap, service)
        if (root.panelOpen) root.enqueuePlexArt(service, snap)
      }
      return
    }
    if (req.kind === "plex-ondeck") {
      if (parsed.status >= 200 && parsed.status < 400) {
        snap.onDeck = Model.parsePlexLibrary(parsed.body, root.pageSize)
        root.commitSnapshot(snap, service)
        if (root.panelOpen) root.enqueuePlexArt(service, snap)
      }
      return
    }
    if (req.kind === "plex-recent") {
      if (parsed.status >= 200 && parsed.status < 400) {
        snap.recent = Model.parsePlexLibrary(parsed.body, root.pageSize)
        root.commitSnapshot(snap, service)
        if (root.panelOpen) root.enqueuePlexArt(service, snap)
      }
      return
    }
    if (req.kind === "jellyfin-identity") {
      var jellyfin = Model.parseJellyfinIdentity(parsed.body)
      root.commitIdentity(service, snap, parsed.status, {
        version: jellyfin.version,
        statusText: jellyfin.name
          ? jellyfin.name + (jellyfin.version ? " " + jellyfin.version : "")
          : jellyfin.version
      })
      return
    }
    if (req.kind === "jellyfin-sessions") {
      if (parsed.status >= 200 && parsed.status < 400) {
        snap.sessions = Model.parseJellyfinSessions(parsed.body, root.pageSize)
        root.commitSnapshot(snap, service)
        if (root.panelOpen) root.enqueueJellyfinArt(service, snap)
      }
      return
    }
    if (req.kind === "jellyfin-users") {
      if (parsed.status >= 200 && parsed.status < 400) {
        var jfAuth = root.cred(service.id)
        var profile = Model.pickJellyfinUser(parsed.body, jfAuth.username)
        if (!profile.id) {
          snap.statusText = jfAuth.username ? "Profile not found: " + jfAuth.username : "No enabled profile"
          root.commitSnapshot(snap, service)
          return
        }
        snap.profileName = profile.name
        root.commitSnapshot(snap, service)
        root.enqueueJellyfinLibrary(service, profile.id)
      }
      return
    }
    if (req.kind === "jellyfin-ondeck") {
      if (parsed.status >= 200 && parsed.status < 400) {
        snap.onDeck = Model.parseJellyfinLibrary(parsed.body, root.pageSize)
        root.commitSnapshot(snap, service)
        if (root.panelOpen) root.enqueueJellyfinArt(service, snap)
      }
      return
    }
    if (req.kind === "jellyfin-recent") {
      if (parsed.status >= 200 && parsed.status < 400) {
        snap.recent = Model.parseJellyfinLibrary(parsed.body, root.pageSize)
        root.commitSnapshot(snap, service)
        if (root.panelOpen) root.enqueueJellyfinArt(service, snap)
      }
      return
    }
  }

  function handleFailure() {
    var req = root.currentReq
    if (req && req.kind === "poster") {
      root.finishArt(req.outputPath, false)
      return
    }
    if (!req || !Model.isHealthKind(req.kind) || req.page > 1) return
    var service = root.serviceById(req.serviceId)
    if (!service) return
    root.commitHealth(service, root.cloneSnap(root.snapshotFor(service)), 0)
  }

  function handleScan(req, status) {
    if (!(status >= 200 && status < 400)) return
    var found = Model.scanHitsForPort(req.port)
    var hits = []
    if (!found.length) {
      hits.push({ kind: "generic", name: req.name, url: req.url, port: req.port })
    } else {
      for (var h = 0; h < found.length; h++) {
        hits.push({ kind: found[h].kind, name: found[h].name, url: req.url, port: req.port })
      }
    }
    var existing = root.scanResults.slice()
    for (var i = 0; i < hits.length; i++) {
      var dupe = false
      for (var j = 0; j < existing.length; j++) {
        if (existing[j].kind === hits[i].kind && existing[j].url === hits[i].url) dupe = true
      }
      if (!dupe) existing.push(hits[i])
    }
    root.scanResults = existing
  }

  function enqueuePosters(service, snap) {
    var posters = {}
    var fanarts = {}
    var calendar = snap.calendar || []
    for (var c = 0; c < calendar.length; c++) {
      var cid = calendar[c].posterId
      if (cid) {
        posters[cid] = true
        fanarts[cid] = true
      }
    }
    var lists = [snap.queue || [], snap.wanted || []]
    for (var l = 0; l < lists.length; l++) {
      for (var i = 0; i < lists[l].length; i++) {
        var pid = lists[l][i].posterId
        if (pid) posters[pid] = true
      }
    }
    var auth = root.cred(service.id)
    var header = auth.apiKey ? Model.headerApiKey(auth.apiKey) : ""
    for (var fid in fanarts) {
      root.enqueueArt({
        kind: "poster",
        serviceId: service.id,
        url: Model.arrFanartUrl(service.url, fid),
        headerText: header,
        outputPath: Model.fanartCachePath(root.cacheDir, service.id, fid),
        image: true
      })
    }
    for (var id in posters) {
      root.enqueueArt({
        kind: "poster",
        serviceId: service.id,
        url: Model.arrPosterUrl(service.url, service.kind, id),
        headerText: header,
        outputPath: Model.posterCachePath(root.cacheDir, service.id, id),
        image: true
      })
    }
  }

  function enqueueGeneric(service) {
    root.enqueue({ kind: "generic", serviceId: service.id, url: service.url })
  }

  function enqueueArr(service) {
    var auth = root.cred(service.id)
    var header = auth.apiKey ? Model.headerApiKey(auth.apiKey) : ""
    var range = Model.arrCalendarRange(new Date(), 7)
    root.enqueue({ kind: "arr-status", serviceId: service.id, url: Model.arrStatusUrl(service.url), headerText: header })
    root.enqueue({ kind: "arr-queue", serviceId: service.id, url: Model.arrQueueUrl(service.url, 1, root.pageSize), headerText: header })
    root.enqueue({ kind: "arr-calendar", serviceId: service.id, url: Model.arrCalendarUrl(service.url, range.start, range.end), headerText: header })
    root.enqueue({ kind: "arr-history", serviceId: service.id, url: Model.arrHistoryUrl(service.url, service.kind, root.pageSize), headerText: header })
    if (root.panelOpen)
      root.enqueue({ kind: "arr-wanted", serviceId: service.id, url: Model.arrWantedUrl(service.url, service.kind), headerText: header })
  }

  function enqueueSab(service, queueOnly) {
    var auth = root.cred(service.id)
    root.enqueue({
      kind: "sab-queue",
      serviceId: service.id,
      url: Model.sabApiUrl(service.url),
      method: "POST",
      bodyText: Model.sabBody(auth.apiKey, "queue", null, root.pageSize)
    })
    if (queueOnly) return
    root.enqueue({
      kind: "sab-history",
      serviceId: service.id,
      url: Model.sabApiUrl(service.url),
      method: "POST",
      bodyText: Model.sabBody(auth.apiKey, "history", null, root.pageSize)
    })
  }

  function enqueueQbitLogin(service) {
    var auth = root.cred(service.id)
    root.enqueue({
      kind: "qbit-login",
      serviceId: service.id,
      url: Model.qbitLoginUrl(service.url),
      method: "POST",
      bodyText: Model.qbitLoginBody(auth.username || "admin", auth.password),
      cookieWrite: root.cookiePath(service.id)
    })
  }

  function enqueueQbit(service, skipLogin) {
    var ready = root.qbitReady[service.id] === true
    var auth = root.cred(service.id)
    if (!skipLogin && !ready && (auth.username || auth.password)) {
      root.enqueueQbitLogin(service)
      return
    }
    var jar = root.cookiePath(service.id)
    root.enqueue({
      kind: "qbit-torrents",
      serviceId: service.id,
      url: Model.qbitTorrentsUrl(service.url, 1, root.pageSize),
      cookieRead: ready || skipLogin ? jar : ""
    })
    root.enqueue({
      kind: "qbit-transfer",
      serviceId: service.id,
      url: Model.qbitTransferUrl(service.url),
      cookieRead: ready || skipLogin ? jar : ""
    })
  }

  function enqueuePlex(service) {
    var auth = root.cred(service.id)
    var header = Model.headerPlex(auth.apiKey)
    root.enqueue({ kind: "plex-identity", serviceId: service.id, url: Model.plexIdentityUrl(service.url), headerText: header })
    root.enqueue({ kind: "plex-sessions", serviceId: service.id, url: Model.plexSessionsUrl(service.url), headerText: header })
    root.enqueue({ kind: "plex-ondeck", serviceId: service.id, url: Model.plexOnDeckUrl(service.url), headerText: header })
    root.enqueue({
      kind: "plex-recent",
      serviceId: service.id,
      url: Model.plexRecentlyAddedUrl(service.url, root.pageSize),
      headerText: header
    })
  }

  function enqueuePlexArt(service, snap) {
    var auth = root.cred(service.id)
    var header = Model.headerPlex(auth.apiKey)
    var lists = [snap.sessions || [], snap.onDeck || [], snap.recent || []]
    var seen = {}
    for (var l = 0; l < lists.length; l++) {
      for (var i = 0; i < lists[l].length; i++) {
        var item = lists[l][i]
        var id = item && item.id
        if (!id || seen[id]) continue
        seen[id] = true
        var url = Model.plexArtUrl(service.url, item.artPath || item.thumbPath)
        if (!url) continue
        root.enqueueArt({
          kind: "poster",
          serviceId: service.id,
          url: url,
          headerText: header,
          outputPath: Model.plexCachePath(root.cacheDir, service.id, id),
          image: true
        })
      }
    }
  }

  function enqueueJellyfin(service) {
    var auth = root.cred(service.id)
    var header = Model.headerJellyfin(auth.apiKey)
    root.enqueue({
      kind: "jellyfin-identity",
      serviceId: service.id,
      url: Model.jellyfinSystemInfoUrl(service.url),
      headerText: header
    })
    root.enqueue({
      kind: "jellyfin-sessions",
      serviceId: service.id,
      url: Model.jellyfinSessionsUrl(service.url),
      headerText: header
    })
    root.enqueue({
      kind: "jellyfin-users",
      serviceId: service.id,
      url: Model.jellyfinUsersUrl(service.url),
      headerText: header
    })
  }

  function enqueueJellyfinLibrary(service, userId) {
    var auth = root.cred(service.id)
    var header = Model.headerJellyfin(auth.apiKey)
    root.enqueue({
      kind: "jellyfin-ondeck",
      serviceId: service.id,
      url: Model.jellyfinResumeUrl(service.url, userId, root.pageSize),
      headerText: header
    })
    root.enqueue({
      kind: "jellyfin-recent",
      serviceId: service.id,
      url: Model.jellyfinLatestUrl(service.url, userId, root.pageSize),
      headerText: header
    })
  }

  function enqueueJellyfinArt(service, snap) {
    var auth = root.cred(service.id)
    var header = Model.headerJellyfin(auth.apiKey)
    var lists = [snap.sessions || [], snap.onDeck || [], snap.recent || []]
    var seen = {}
    for (var l = 0; l < lists.length; l++) {
      for (var i = 0; i < lists[l].length; i++) {
        var item = lists[l][i] || {}
        var id = String(item.id || "")
        if (!id || seen[id]) continue
        seen[id] = true
        var url = Model.jellyfinArtUrl(service.url, item.artItemId || id, item.artType)
        if (!url) continue
        root.enqueueArt({
          kind: "poster",
          serviceId: service.id,
          url: url,
          headerText: header,
          outputPath: Model.jellyfinCachePath(root.cacheDir, service.id, id),
          image: true
        })
      }
    }
  }

  function enqueuePoll(scope) {
    if (root.reqQueue.length) return
    var downloaders = scope === "downloaders"
    function enqueueOne(svc) {
      if (!Model.isHttpUrl(svc.url)) return
      if (svc.kind === "sonarr" || svc.kind === "radarr") root.enqueueArr(svc)
      else if (svc.kind === "sabnzbd") root.enqueueSab(svc, downloaders)
      else if (svc.kind === "qbittorrent") root.enqueueQbit(svc)
      else if (downloaders) return
      else if (svc.kind === "plex") root.enqueuePlex(svc)
      else if (svc.kind === "jellyfin") root.enqueueJellyfin(svc)
      else root.enqueueGeneric(svc)
    }
    for (var i = 0; i < root.services.length; i++) {
      var downloader = root.services[i]
      if (downloader.kind === "sabnzbd" || downloader.kind === "qbittorrent") enqueueOne(downloader)
    }
    if (downloaders) return
    for (var j = 0; j < root.services.length; j++) {
      var other = root.services[j]
      if (other.kind === "sabnzbd" || other.kind === "qbittorrent") continue
      enqueueOne(other)
    }
  }

  function forcePoll() {
    root.rebuildSnapshots()
    if (!root.reqQueue.length && !apiProc.running) root.enqueuePoll()
    root.pump()
  }

  function hasDownloaderRequest() {
    function isDl(req) {
      if (!req) return false
      var k = String(req.kind || "")
      return k === "sab-queue" || k.indexOf("qbit-") === 0
    }
    if (isDl(root.currentReq)) return true
    for (var i = 0; i < root.reqQueue.length; i++) {
      if (isDl(root.reqQueue[i])) return true
    }
    return false
  }

  function forceDownloaderPoll() {
    if (root.writingFiles || root.hasDownloaderRequest()) return
    var rest = root.reqQueue
    root.reqQueue = []
    root.enqueuePoll("downloaders")
    root.reqQueue = root.reqQueue.concat(rest)
    root.pump()
  }

  function startScan() {
    root.scanning = true
    root.scanResults = []
    var targets = Model.scanTargets()
    for (var i = 0; i < targets.length; i++) {
      var t = targets[i]
      root.enqueue({
        kind: "scan",
        url: Model.scanUrl("127.0.0.1", t.port),
        port: t.port,
        name: t.name,
        scan: true
      })
    }
    root.pump()
  }

  function finishScanIfIdle() {
    if (!root.scanning) return
    if (root.reqQueue.length || apiProc.running || root.writingFiles) return
    root.scanning = false
  }

  function commandReq(kind, service, spec) {
    var req = spec || {}
    req.kind = "command"
    req.serviceId = service.id
    root.enqueue(req)
  }

  function runControl(serviceId, action, itemId) {
    var service = root.serviceById(serviceId)
    if (!service) return
    var auth = root.cred(service.id)
    if (service.kind === "sabnzbd") {
      var extra = {}
      var mode = action
      if (action === "pause-item") {
        mode = "queue"
        extra = { name: "pause", value: String(itemId || "") }
      } else if (action === "resume-item") {
        mode = "queue"
        extra = { name: "resume", value: String(itemId || "") }
      } else return
      root.commandReq("command", service, {
        url: Model.sabApiUrl(service.url),
        method: "POST",
        bodyText: Model.sabBody(auth.apiKey, mode, extra)
      })
    }
    if (service.kind === "qbittorrent") {
      if (action !== "pause-item" && action !== "resume-item") return
      var pause = action === "pause-item"
      var hashes = String(itemId || "")
      root.commandReq("command", service, {
        url: pause ? Model.qbitPauseUrl(service.url) : Model.qbitResumeUrl(service.url),
        method: "POST",
        bodyText: Model.qbitHashesBody(hashes),
        cookieRead: root.cookiePath(service.id)
      })
      root.commandReq("command", service, {
        url: pause ? Model.qbitStopUrl(service.url) : Model.qbitStartUrl(service.url),
        method: "POST",
        bodyText: Model.qbitHashesBody(hashes),
        cookieRead: root.cookiePath(service.id)
      })
    }
    Qt.callLater(root.forcePoll)
  }

  function posterPath(serviceId, posterId) {
    return Model.posterCachePath(root.cacheDir, serviceId, posterId)
  }

  function fanartPath(serviceId, posterId) {
    return Model.fanartCachePath(root.cacheDir, serviceId, posterId)
  }

  function plexPath(serviceId, itemId) {
    return Model.plexCachePath(root.cacheDir, serviceId, itemId)
  }

  function mediaPath(serviceId, itemId) {
    var service = root.serviceById(serviceId)
    if (service && service.kind === "jellyfin")
      return Model.jellyfinCachePath(root.cacheDir, serviceId, itemId)
    return Model.plexCachePath(root.cacheDir, serviceId, itemId)
  }

  function copyMap(obj) {
    var next = {}
    if (!obj) return next
    for (var k in obj) next[k] = obj[k]
    return next
  }

  function enqueueArt(req) {
    var path = req && req.outputPath
    if (!path || root.artReady[path] || root.artPending[path]) return
    var pending = root.copyMap(root.artPending)
    pending[path] = true
    root.artPending = pending
    root.enqueue(req)
  }

  function finishArt(path, ok) {
    if (!path) return
    var pending = root.copyMap(root.artPending)
    delete pending[path]
    root.artPending = pending
    if (!ok || root.artReady[path]) return
    var ready = root.copyMap(root.artReady)
    ready[path] = true
    root.artReady = ready
    var rev = root.copyMap(root.artRev)
    rev[path] = (rev[path] || 0) + 1
    root.artRev = rev
  }

  FileView {
    id: credsFile
    path: root.credsPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.credentials = Model.parseCredentials(text())
    onLoadFailed: root.credentials = ({})
    onFileChanged: reload()
  }

  FileView {
    id: seenFile
    path: root.seenPath
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: root.seenIds = Model.parseSeenFile(text())
    onLoadFailed: root.seenIds = []
  }

  FileView {
    id: headerFile
    path: root.headerPath
    watchChanges: false
    atomicWrites: true
    blockWrites: true
    printErrors: false
  }

  FileView {
    id: bodyFile
    path: root.bodyPath
    watchChanges: false
    atomicWrites: true
    blockWrites: true
    printErrors: false
  }

  Process {
    id: ensureDirProc
    running: false
    onExited: {
      cacheIndexProc.command = ["ls", "-1", root.cacheDir]
      cacheIndexProc.running = true
    }
  }

  Process {
    id: cacheIndexProc
    running: false
    stdout: StdioCollector {
      id: cacheIndexOut
      waitForEnd: true
    }
    onExited: {
      var ready = {}
      var lines = String(cacheIndexOut.text || "").split("\n")
      for (var i = 0; i < lines.length; i++) {
        var name = String(lines[i] || "").replace(/^\s+|\s+$/g, "")
        if (!name || name.indexOf(".jpg") === -1) continue
        ready[root.cacheDir + "/" + name] = true
      }
      root.artReady = ready
      root.dirsReady = true
      credsFile.reload()
      seenFile.reload()
      chmodStateProc.command = ["chmod", "700", root.stateDir]
      chmodStateProc.running = true
      root.rebuildSnapshots()
      root.forcePoll()
    }
  }

  Process {
    id: chmodStateProc
    running: false
  }

  Process {
    id: chmodProc
    running: false
    onExited: {
      root.writingFiles = false
      root.runCurl(root.currentReq)
    }
  }

  Process {
    id: toastProc
    running: false
    onExited: Qt.callLater(root.pumpToasts)
  }

  Process {
    id: openProc
    running: false
  }

  Process {
    id: apiProc
    running: false
    stdout: StdioCollector {
      id: apiOut
      waitForEnd: true
    }
    onExited: function(exitCode) {
      if (root.currentReq && root.currentReq.kind === "scan") {
        if (exitCode === 0) root.handleSuccess(apiOut.text)
      } else if (exitCode !== 0) {
        root.handleFailure()
      } else {
        root.handleSuccess(apiOut.text)
      }
      root.currentReq = null
      if (!root.reqQueue.length) {
        if (root.seeding) {
          root.seeding = false
          root.persistSeen()
        } else {
          root.persistSeen()
        }
        root.finishScanIfIdle()
      }
      Qt.callLater(root.pump)
    }
  }

  Timer {
    interval: Math.max(5, root.pollSeconds) * 1000
    running: root.dirsReady
    repeat: true
    triggeredOnStart: false
    onTriggered: root.forcePoll()
  }

  Timer {
    interval: 8000
    running: root.panelOpen && root.dirsReady
    repeat: true
    onTriggered: if (!root.reqQueue.length && !apiProc.running) root.forcePoll()
  }

  Timer {
    interval: Model.DOWNLOAD_POLL_MS
    running: root.dirsReady
    repeat: true
    onTriggered: root.forceDownloaderPoll()
  }

  onServicesChanged: root.rebuildSnapshots()
  onShellChanged: root.pluginSettings = Model.pluginSettings(root.shell ? root.shell.shellConfig : null, Model.PLUGIN_ID)
  onPanelOpenChanged: if (root.panelOpen) {
    root.clearUnread()
    root.forcePoll()
  }

  DownloadToast {
    shell: root.shell
    service: root
    job: root.progressJob
    showToast: root.showProgressToast
    onDismissRequested: root.dismissProgressToast()
  }

  Component.onCompleted: {
    ensureDirProc.command = ["mkdir", "-p", root.stateDir, root.cacheDir]
    ensureDirProc.running = true
  }
}
