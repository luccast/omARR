#!/usr/bin/env node
const assert = require("node:assert/strict")
const fs = require("fs")
const path = require("path")
const Model = require("../Model.js")

function eq(rows) {
  for (const [actual, expected, msg] of rows) assert.equal(actual, expected, msg)
}

function has(rows) {
  for (const [text, frag, msg] of rows) assert.ok(String(text).indexOf(frag) !== -1, msg)
}

eq([
  [Model.PLUGIN_ID, "io.github.luccast.omarr", "plugin id"], [Model.API_MAX_BYTES, 2 * 1024 * 1024, "api max"],
  [Model.curlBounds(0).join(" "), "--connect-timeout 4 --max-time 20 --max-filesize 2097152", "curl bounds fallback"],
  [Model.normalizeUrl(" http://box:8989/ "), "http://box:8989", "normalizeUrl trim"], [Model.normalizeUrl(""), "", "normalizeUrl empty"]
])
has([[Model.curlBounds(Model.IMAGE_MAX_BYTES).join(" "), "8388608", "image bounds"]])
;[
  ["http://127.0.0.1:8989", true, "http ok"],
  ["https://media.lan", true, "https ok"],
  ["ftp://x", false, "ftp rejected"],
  ["javascript:alert(1)", false, "js rejected"],
  ["", false, "empty url rejected"]
].forEach(([url, ok, msg]) => assert.equal(Model.isHttpUrl(url), ok, msg))

var empty = Model.defaultSettings()
eq([
  [empty.services.length, 0, "default services"], [empty.pollSeconds, 30, "default poll"],
  [empty.pageSize, 20, "default page size"], [empty.density, "comfortable", "default density"],
  [empty.showProgressToast, true, "progress toast on"]
])
assert.ok(empty.showCalendar === undefined && empty.showQueue === undefined, "no global panes")

var fromBar = Model.pluginSettings({
  bar: {
    layout: {
      right: [{
        id: Model.PLUGIN_ID,
        pollSeconds: 15,
        pageSize: 10,
        density: "compact",
        showCalendar: false,
        showArrQueue: true,
        showQueue: false,
        services: [
          { kind: "sonarr", url: "http://127.0.0.1:8989/", name: "TV" },
          { kind: "sabnzbd", url: "http://127.0.0.1:8080/", name: "SABnzbd" }
        ]
      }]
    }
  }
})
eq([
  [fromBar.pollSeconds, 15, "poll from shell.json"], [fromBar.pageSize, 10, "page size from shell.json"],
  [fromBar.density, "compact", "density from shell.json"], [fromBar.services.length, 2, "two services"],
  [fromBar.services[0].kind, "sonarr", "kind"], [fromBar.services[0].url, "http://127.0.0.1:8989", "url stripped"],
  [fromBar.services[0].group, "Media", "default group"], [fromBar.services[0].notifyGrab, true, "notify grab default"],
  [fromBar.services[0].showQueue, true, "legacy showArrQueue migrates"], [fromBar.services[0].showCalendar, false, "legacy showCalendar migrates"],
  [fromBar.services[1].showQueue, false, "legacy showQueue off migrates to sab"], [fromBar.services[1].showCalendar, false, "sab has no calendar"],
  [Model.normalizeService({ kind: "sonarr" }).showQueue, false, "sonarr queue off"], [Model.normalizeService({ kind: "sonarr" }).showCalendar, true, "sonarr calendar on"],
  [Model.normalizeService({ kind: "sabnzbd" }).showQueue, true, "sab queue on"],
  [Model.normalizeService({ kind: "sonarr", showQueue: true }).showQueue, true, "sonarr queue opt in"],
  [Model.normalizeSettings({}).showProgressToast, true, "progress toast default"],
  [Model.normalizeSettings({ showProgressToast: false }).showProgressToast, false, "progress toast off"],
  [Model.settingsPayload({}).showProgressToast, true, "payload keeps progress toast"],
  [Model.settingsPayload({ showProgressToast: false }).showProgressToast, false, "payload progress toast off"]
])
assert.ok(!("showQueue" in Model.settingsPayload({})), "payload drops global queue")
assert.ok(!("showCalendar" in Model.settingsPayload({})), "payload drops global calendar")
assert.ok(!("showArrQueue" in Model.settingsPayload({})), "payload drops global arr queue")

assert.equal(Model.pluginSettings({}).services.length, 0, "missing config")
assert.equal(Model.pluginSettings({
  plugins: [{ id: Model.PLUGIN_ID, services: [{ kind: "radarr", url: "http://r:7878" }] }]
}).services[0].kind, "radarr", "plugins[] fallback")

var bogus = Model.normalizeService({ kind: "nope", url: "not-a-url" }, 0)
assert.equal(bogus.kind, "generic", "unknown kind")
assert.equal(bogus.url, "", "invalid url dropped")

var idA = Model.newServiceId([])
var idB = Model.newServiceId([{ id: "svc-1" }, { id: "svc-4" }])
assert.ok(idA.indexOf("svc-") === 0, "new id prefix")
assert.equal(idB, "svc-5", "new id increments")

var s1 = Model.addService(Model.defaultSettings(), { kind: "sonarr", url: "http://127.0.0.1:8989" })
assert.equal(s1.services.length, 1, "add service")
assert.equal(s1.services[0].name, "Sonarr", "kind default name")
assert.ok(s1.services[0].showQueue === false, "add sonarr queue off")
assert.ok(s1.services[0].showCalendar === true, "add sonarr calendar on")
var s2 = Model.addService(s1, { kind: "radarr", url: "http://127.0.0.1:7878" })
assert.equal(s2.services.length, 2, "second service")
var twoSonarr = Model.addService(s1, { kind: "sonarr", url: "http://192.168.2.200:8989", name: "Sonarr 4K" })
assert.equal(twoSonarr.services.length, 2, "two sonarrs")
assert.equal(twoSonarr.services[0].kind, "sonarr", "first remains sonarr")
assert.equal(twoSonarr.services[1].kind, "sonarr", "second is sonarr")
assert.ok(twoSonarr.services[0].id !== twoSonarr.services[1].id, "sonarrs get distinct ids")
var twoKeys = Model.setCredential({}, twoSonarr.services[0].id, { apiKey: "aaa" })
twoKeys = Model.setCredential(twoKeys, twoSonarr.services[1].id, { apiKey: "bbb" })
assert.equal(Model.credentialFor(twoKeys, twoSonarr.services[0].id).apiKey, "aaa", "first sonarr key")
assert.equal(Model.credentialFor(twoKeys, twoSonarr.services[1].id).apiKey, "bbb", "second sonarr key")

assert.ok(Model.kindNeedsApiKey("sonarr") && Model.kindNeedsApiKey("radarr") && Model.kindNeedsApiKey("sabnzbd") && Model.kindNeedsApiKey("plex") && Model.kindNeedsApiKey("jellyfin"), "arr/sab/media need api key")
assert.ok(!Model.kindNeedsApiKey("generic") && !Model.kindNeedsApiKey("qbittorrent"), "generic/qbit no api key")
assert.ok(Model.kindNeedsUserPass("qbittorrent"), "qbit needs user/pass")
assert.ok(!Model.kindNeedsUserPass("sonarr"), "sonarr no user/pass")
assert.ok(Model.kindNeedsUsername("jellyfin"), "jellyfin accepts profile name")
assert.ok(!Model.kindNeedsUserPass("jellyfin"), "jellyfin profile needs no password")
assert.ok(Model.isMediaKind("plex") && Model.isMediaKind("jellyfin"), "media kinds")
assert.equal(Model.defaultUrlForKind("jellyfin"), "http://127.0.0.1:8096", "jellyfin default url")
assert.equal(Model.uniqueServiceName([], "sonarr"), "Sonarr", "first sonarr name")
assert.equal(Model.uniqueServiceName(s1.services, "sonarr"), "Sonarr 2", "second sonarr name")
assert.equal(Model.uniqueServiceName(twoSonarr.services, "sonarr"), "Sonarr 2", "third default skips 4K custom")

var collided = Model.normalizeSettings({
  services: [
    { id: "svc-2", kind: "sonarr", url: "http://a:8989" },
    { kind: "sonarr", url: "http://b:8989" }
  ]
})
assert.equal(collided.services.length, 2, "colliding ids kept both")
assert.ok(collided.services[0].id !== collided.services[1].id, "normalize uniquifies ids")
assert.equal(collided.services[0].kind, "sonarr", "collided first kind")
assert.equal(collided.services[1].kind, "sonarr", "collided second kind")
var s3 = Model.updateService(s2, s2.services[0].id, { name: "TV" })
assert.equal(s3.services[0].name, "TV", "rename")
var s4 = Model.moveService(s3, s3.services[0].id, 1)
assert.equal(s4.services[0].kind, "radarr", "moved down")
var s5 = Model.removeService(s4, s4.services[0].id)
assert.equal(s5.services.length, 1, "removed")
assert.equal(s5.services[0].kind, "sonarr", "remaining")

var grouped = Model.groupedServices([
  { id: "a", group: "Other", order: 2, name: "HA" },
  { id: "b", group: "Media", order: 0, name: "Sonarr" },
  { id: "c", group: "Media", order: 1, name: "Radarr" }
])
assert.equal(grouped.length, 2, "two groups")
assert.equal(grouped[0].group, "Media", "media first")
assert.equal(grouped[0].services.length, 2, "media members")
assert.equal(grouped[1].group, "Other", "other second")

var blankGroup = Model.normalizeService({ kind: "sonarr", url: "http://s:8989", group: "" }, 0)
assert.equal(blankGroup.group, "", "empty group is kept")
assert.equal(Model.normalizeService({ kind: "sonarr", url: "http://s:8989", group: "  Night  " }, 0).group, "Night", "group trimmed")
assert.equal(Model.normalizeService({ kind: "sonarr", url: "http://s:8989" }, 0).group, "Media", "missing group uses kind default")
var cleared = Model.updateService({
  services: [{ id: "svc-1", kind: "sonarr", url: "http://s:8989", group: "Other" }]
}, "svc-1", { group: "" })
assert.equal(cleared.services[0].group, "", "update can clear group")

var regroup = Model.groupedServices([
  { id: "a", group: "", order: 0, name: "Ungrouped" },
  { id: "b", group: "Media", order: 2, name: "Later media" },
  { id: "c", group: "Media", order: 1, name: "First media" },
  { id: "d", group: "Downloads", order: 3, name: "SAB" }
])
assert.equal(regroup.length, 3, "named groups plus ungrouped")
assert.equal(regroup[0].group, "Downloads", "groups sort alphabetically")
assert.equal(regroup[1].group, "Media", "media after downloads")
assert.equal(regroup[1].services[0].name, "First media", "within group by order")
assert.equal(regroup[1].services[1].name, "Later media", "within group second")
assert.equal(regroup[2].group, "", "ungrouped last")
assert.equal(regroup[2].services[0].name, "Ungrouped", "ungrouped member")

var stale = Model.emptySnapshot({ id: "svc-1", kind: "sonarr", name: "Old", url: "http://old", group: "Other" })
stale.health = "up"
var synced = Model.applyServiceMeta(stale, { id: "svc-1", kind: "sonarr", name: "Sonarr LQ", url: "http://new", group: "Media" })
assert.equal(synced.group, "Media", "meta sync group")
assert.equal(synced.name, "Sonarr LQ", "meta sync name")
assert.equal(synced.health, "up", "meta sync keeps health")

var withOrder = Model.applyServiceMeta(Model.emptySnapshot({ id: "a" }), {
  id: "a", kind: "sonarr", name: "Later", group: "Media", order: 2
})
assert.equal(withOrder.order, 2, "snapshot keeps service order")
var unorderedSnaps = [
  Model.applyServiceMeta(Model.emptySnapshot({ id: "a" }), {
    id: "a", kind: "sonarr", name: "First", group: "Media", order: 1
  }),
  Model.applyServiceMeta(Model.emptySnapshot({ id: "b" }), {
    id: "b", kind: "sonarr", name: "Second", group: "Media", order: 0
  })
]
var fleet = Model.groupedServices(unorderedSnaps)
assert.equal(fleet[0].services[0].id, "b", "fleet list sorts by service order")
assert.equal(fleet[0].services[1].id, "a", "fleet list follows moved order")

var creds = Model.parseCredentials('{"svc-1":{"apiKey":"abc"}}')
assert.equal(Model.credentialFor(creds, "svc-1").apiKey, "abc", "cred read")
var creds2 = Model.setCredential(creds, "svc-1", { username: "admin" })
assert.equal(creds2["svc-1"].apiKey, "abc", "cred merge keeps key")
assert.equal(creds2["svc-1"].username, "admin", "cred merge username")
assert.ok(Model.parseCredentials("nope")["x"] === undefined, "bad creds")
assert.ok(Model.serializeCredentials({ "svc-1": { apiKey: "z" } }).indexOf("svc-1") !== -1, "serialize creds")

assert.equal(Model.parseSeenFile('["a","b"]').join(","), "a,b", "seen parse")
assert.equal(Model.parseSeenFile("x").length, 0, "seen bad")
assert.equal(Model.rememberIds(["1"], ["1", "2"]).join(","), "1,2", "remember")
var longSeen = []
for (var i = 0; i < Model.SEEN_LIMIT + 5; i++) longSeen.push(String(i))
assert.equal(Model.rememberIds(longSeen, ["new"]).length, Model.SEEN_LIMIT, "seen cap")

var range = Model.arrCalendarRange(new Date(Date.UTC(2026, 7, 26)), 7)
assert.equal(range.start, "2026-08-26", "cal start")
assert.equal(range.end, "2026-09-02", "cal end")

assert.equal(Model.arrStatusUrl("http://s:8989"), "http://s:8989/api/v3/system/status", "status url")
eq([
  [Model.LIST_PAGE_SIZE, 20, "page size"], [Model.clampPageSize(10), 10, "page size ok"],
  [Model.clampPageSize(1), 5, "page size min"], [Model.clampPageSize(999), 50, "page size max"],
  [Model.clampPageSize("nope"), 20, "page size fallback"], [Model.normalizeSettings({ pageSize: 40 }).pageSize, 40, "normalize page size"],
  [Model.listOffset(2, 10), 10, "offset custom size"], [Model.listPage(0), 1, "page min"],
  [Model.listPage(-2), 1, "page negative"], [Model.listPage(3), 3, "page 3"],
  [Model.listOffset(1), 0, "offset page 1"], [Model.listOffset(2), 20, "offset page 2"],
  [Model.arrQueueUrl("http://s:8989", 2, 10), "http://s:8989/api/v3/queue?page=2&pageSize=10", "arr custom page size"],
  [Model.arrQueueUrl("http://s:8989"), "http://s:8989/api/v3/queue?page=1&pageSize=20", "queue url"],
  [Model.arrQueueUrl("http://s:8989", 2), "http://s:8989/api/v3/queue?page=2&pageSize=20", "queue page 2"],
  [Model.arrTotalRecords('{"totalRecords":247,"records":[]}'), 247, "arr total"], [Model.arrTotalRecords("nope"), 0, "arr total junk"],
  [Model.listPager(1, 10, 25, 10).label, "1-10 of 25", "pager custom label"], [Model.listPager(2, 10, 0, 10).hasNext, true, "pager custom full page"]
])
has([
  [Model.qbitTorrentsUrl("http://q:8080", 2, 10), "limit=10", "qbit custom limit"],
  [Model.qbitTorrentsUrl("http://q:8080", 2, 10), "offset=10", "qbit custom offset"],
  [Model.sabBody("k", "queue", null, 10), "limit=10", "sab custom limit"]
])
var pager = Model.listPager(1, 20, 247)
assert.equal(pager.hasNext, true, "pager next")
assert.equal(pager.hasPrev, false, "pager prev")
assert.equal(pager.label, "1-20 of 247", "pager label")
var pageTwo = Model.listPager(2, 20, 0)
assert.equal(pageTwo.hasPrev, true, "unknown total prev")
assert.equal(pageTwo.hasNext, true, "full page implies more")
assert.equal(pageTwo.label, "21-40", "pager label no total")
var lastPage = Model.listPager(2, 5, 0)
assert.equal(lastPage.hasNext, false, "short page is last")
assert.equal(Model.listPager(1, 3, 3).hasNext, false, "exact total no next")
has([
  [Model.arrCalendarUrl("http://s:8989", "2026-08-26", "2026-09-02"), "start=2026-08-26", "cal url"],
  [Model.arrCalendarUrl("http://s:8989", "2026-08-26", "2026-09-02"), "includeSeries=true", "cal include series"],
  [Model.arrWantedUrl("http://s:8989", "sonarr"), "includeSeries=true", "wanted include series"],
  [Model.arrHistoryUrl("http://s:8989", "sonarr"), "/api/v3/history?", "arr history url"],
  [Model.arrHistoryUrl("http://s:8989", "sonarr"), "includeSeries=true", "arr history series"],
  [Model.arrHistoryUrl("http://r:7878", "radarr"), "includeMovie=true", "arr history movie"]
])
eq([
  [Model.arrPosterUrl("http://s:8989", "sonarr", 12), "http://s:8989/api/v3/mediacover/12/poster-500.jpg", "poster url"],
  [Model.arrFanartUrl("http://s:8989", 12), "http://s:8989/api/v3/mediacover/12/fanart.jpg", "fanart url"],
  [Model.formatRating(8.4, "imdb"), "IMDb 8.4", "imdb rating label"], [Model.formatRating(8.5, ""), "8.5", "generic rating"],
  [Model.formatRating(0, "imdb"), "", "empty rating"]
])

var status = Model.parseArrStatus('{"version":"4.0.1","appName":"Sonarr"}')
assert.equal(status.version, "4.0.1", "arr version")
assert.ok(status.healthy === true, "arr healthy")
assert.equal(Model.parseArrStatus("nope").healthy, false, "arr status junk")

var fixtureQueue = fs.readFileSync(path.join(__dirname, "fixtures/sonarr-queue.json"), "utf8")
var queue = Model.parseArrQueue(fixtureQueue, "sonarr")
eq([
  [queue.length, 1, "arr queue len"], [queue[0].progress, 0.75, "arr progress"],
  [queue[0].title, "Show.S01E01", "arr queue title"], [queue[0].protocol, "torrent", "arr queue protocol"],
  [queue[0].timeleft, "00:10:00", "arr queue eta"], [queue[0].status, "downloading", "arr queue status"]
])
var warned = Model.parseArrQueue(JSON.stringify({
  records: [{ id: 2, title: "X", status: "downloading", trackedDownloadStatus: "warning", protocol: "usenet", timeleft: "00:05:00", size: 10, sizeleft: 5 }]
}), "sonarr")
assert.equal(warned[0].status, "warning", "arr queue warning status")
assert.ok(Model.isActiveDownload(warned[0]), "warning still downloading")
assert.equal(Model.queueLine(warned[0]), "warning · usenet · 5m", "queue line warning")
assert.equal(Model.queueLine(queue[0]), "downloading · torrent · 10m", "queue line eta")
assert.equal(Model.formatTimeLeft("00:10:00"), "10m", "format timeleft")
assert.equal(Model.formatTimeLeft("01:05:00"), "1h 5m", "format timeleft hours")
assert.equal(Model.formatTimeLeft("00:00:00"), "", "format timeleft zero")

var cal = Model.parseArrCalendar(JSON.stringify([
  {
    id: 4,
    airDate: "2026-08-26",
    hasFile: false,
    monitored: true,
    series: { title: "Show", id: 3 },
    seasonNumber: 1,
    episodeNumber: 2,
    title: "Next"
  }
]), "sonarr")
assert.equal(cal[0].title, "Show", "cal series")
assert.equal(cal[0].subtitle, "S01E02 Next", "cal episode")
assert.equal(cal[0].posterId, "3", "cal poster")
assert.equal(cal[0].rating, 0, "cal no rating")

var calRated = Model.parseArrCalendar(JSON.stringify([
  {
    id: 40,
    airDate: "2026-08-26",
    seasonNumber: 1,
    episodeNumber: 1,
    title: "Pilot",
    series: { title: "Show", id: 3, ratings: { votes: 10, value: 8.5 } }
  }
]), "sonarr")
assert.equal(calRated[0].rating, 8.5, "sonarr series rating")
assert.equal(calRated[0].ratingSource, "", "sonarr rating is not imdb")

var calFlat = Model.parseArrCalendar(JSON.stringify([
  {
    id: 5,
    airDate: "2026-08-27",
    title: "The Episode",
    seasonNumber: 2,
    episodeNumber: 3,
    seriesTitle: "The Show",
    seriesId: 9
  }
]), "sonarr")
assert.equal(calFlat[0].title, "The Show", "cal seriesTitle fallback")
assert.equal(calFlat[0].subtitle, "S02E03 The Episode", "cal episode stays subtitle")
assert.equal(calFlat[0].posterId, "9", "cal seriesId poster")

var calBare = Model.parseArrCalendar(JSON.stringify([
  { id: 6, title: "Naked Episode", seasonNumber: 1, episodeNumber: 1 }
]), "sonarr")
assert.equal(calBare[0].title, "", "cal no series not episode title")
assert.ok(calBare[0].subtitle.indexOf("Naked Episode") !== -1, "cal episode in subtitle")

var wed = new Date(2026, 7, 26)
eq([
  [Model.calendarDayKey("2026-08-26"), "2026-08-26", "day key date"], [Model.calendarDayKey("2026-08-26T02:00:00Z"), "2026-08-26", "day key iso"],
  [Model.calendarDayKey(""), "", "day key empty"], [Model.calendarDayLabel("2026-08-26", wed), "Today", "label today"],
  [Model.calendarDayLabel("2026-08-27", wed), "Tomorrow", "label tomorrow"], [Model.calendarDayLabel("2026-08-28", wed), "Friday", "label friday"],
  [Model.calendarDayLabel("2026-09-02", wed), "Next Wednesday", "label next week"], [Model.calendarDateMeta("2026-08-26"), "26-08-26", "date meta"],
  [Model.calendarDateMeta("2026-08-26T18:00:00Z"), "26-08-26", "date meta iso"]
])
var groupedCal = Model.groupedCalendar([
  { id: "1", title: "B", airDate: "2026-08-27" },
  { id: "2", title: "A", airDate: "2026-08-26" },
  { id: "3", title: "C", airDate: "2026-08-26T18:00:00Z" }
], wed)
assert.equal(groupedCal.length, 2, "grouped two days")
assert.equal(groupedCal[0].day, "Today", "grouped today first")
assert.equal(groupedCal[0].heading, "Today · 26-08-26", "grouped heading has date")
assert.equal(groupedCal[1].heading, "Tomorrow · 27-08-26", "grouped tomorrow heading")
assert.equal(groupedCal[0].items.length, 2, "grouped two on today")
assert.equal(groupedCal[1].day, "Tomorrow", "grouped tomorrow")

var mixedDates = Model.groupedCalendar([
  { id: "hq-1", title: "HQ Friday", airDate: new Date(2026, 7, 28) },
  { id: "lq-1", title: "LQ Today", airDate: "2026-08-26" },
  { id: "hq-2", title: "HQ Tomorrow", airDate: "2026-08-27T06:00:00Z" }
], wed)
assert.equal(mixedDates.map(function(g) { return g.day }).join(","), "Today,Tomorrow,Friday", "mixed services regroup by day")

var lqSnap = Model.emptySnapshot({ id: "lq", kind: "sonarr", name: "Sonarr LQ", showCalendar: true })
lqSnap.health = "up"
lqSnap.calendar = [
  { id: "1", title: "LQ Friday", airDate: "2026-08-28" },
  { id: "2", title: "LQ Today", airDate: "2026-08-26" }
]
var hqSnap = Model.emptySnapshot({ id: "hq", kind: "sonarr", name: "Sonarr HQ", showCalendar: true })
hqSnap.health = "up"
hqSnap.calendar = [
  { id: "3", title: "HQ Tomorrow", airDate: "2026-08-27T00:00:00Z" }
]
var mergedCal = Model.mergeNow([lqSnap, hqSnap])
var mergedGroups = Model.groupedCalendar(mergedCal.calendar, wed)
assert.equal(mergedGroups.map(function(g) { return g.day }).join(","), "Today,Tomorrow,Friday", "merged now calendar by day")

lqSnap.calendar[1].rating = 8.5
lqSnap.calendar[1].ratingSource = ""
var mergedRated = Model.mergeNow([lqSnap])
var todayItems = mergedRated.calendar.filter(function(ev) { return ev.title === "LQ Today" })
assert.equal(todayItems[0].rating, 8.5, "merged rating")

var movies = Model.parseArrCalendar(JSON.stringify([
  { id: 8, title: "Film", year: 2024, inCinemas: "2026-08-27", hasFile: false, monitored: true }
]), "radarr")
assert.equal(movies[0].title, "Film", "radarr cal")
assert.equal(movies[0].subtitle, "2024", "radarr year")

var movieRated = Model.parseArrCalendar(JSON.stringify([
  {
    id: 9,
    title: "Rated Film",
    year: 2025,
    inCinemas: "2026-08-27",
    ratings: { imdb: { votes: 100, value: 7.3 }, tmdb: { value: 6.1 } }
  }
]), "radarr")
assert.equal(movieRated[0].rating, 7.3, "radarr imdb rating")
assert.equal(movieRated[0].ratingSource, "imdb", "radarr rating source")

var wanted = Model.parseArrWanted(JSON.stringify({
  records: [{ id: 1, title: "Pilot", seasonNumber: 1, episodeNumber: 1, series: { title: "Show", id: 3 } }]
}), "sonarr")
assert.equal(wanted[0].title, "Show", "wanted series")

var wantedFlat = Model.parseArrWanted(JSON.stringify({
  records: [{ id: 2, title: "Pilot", seasonNumber: 1, episodeNumber: 1, seriesTitle: "Flat Show", seriesId: 8 }]
}), "sonarr")
assert.equal(wantedFlat[0].title, "Flat Show", "wanted seriesTitle fallback")
assert.equal(wantedFlat[0].posterId, "8", "wanted seriesId poster")

var arrHist = Model.parseArrHistory(JSON.stringify({
  records: [
    { id: 11, eventType: "grabbed", sourceTitle: "Show.S01E01", series: { title: "Show" }, episode: { seasonNumber: 1, episodeNumber: 1, title: "Pilot" } },
    { id: 12, eventType: "downloadFolderImported", sourceTitle: "Show.S01E01", series: { title: "Show" }, episode: { seasonNumber: 1, episodeNumber: 1, title: "Pilot" } },
    { id: 13, eventType: "downloadFailed", sourceTitle: "Show.S01E02", series: { title: "Show" } },
    { id: 14, eventType: "rssSync" }
  ]
}), "sonarr")
assert.equal(arrHist.length, 3, "arr history skips rss")
assert.equal(arrHist[0].status, "grabbed", "arr hist grab")
assert.equal(arrHist[1].status, "imported", "arr hist import")
assert.equal(arrHist[2].status, "failed", "arr hist fail")
assert.equal(arrHist[0].title, "Show", "arr hist series title")

var radHist = Model.parseArrHistory(JSON.stringify({
  records: [{ id: 21, eventType: "downloadFolderImported", sourceTitle: "Film.mkv", movie: { title: "Film" } }]
}), "radarr")
assert.equal(radHist[0].title, "Film", "radarr hist movie")
assert.equal(radHist[0].status, "imported", "radarr hist import")

var sab = Model.parseSabQueue(JSON.stringify({
  queue: {
    paused: false,
    speed: "1.5 M",
    speedlimit: "",
    mbleft: "100",
    timeleft: "0:12:00",
    kbpersec: 1536,
    noofslots: 40,
    slots: [{
      nzo_id: "SABnzbd_nzo_x",
      filename: "Show.nzb",
      status: "Downloading",
      mb: "800",
      mbleft: "200",
      percentage: "75"
    }]
  }
}))
assert.ok(sab.paused === false, "sab not paused")
assert.equal(sab.queue.length, 1, "sab slots")
assert.equal(sab.total, 40, "sab total")
assert.equal(sab.queue[0].id, "SABnzbd_nzo_x", "sab id")
assert.ok(sab.speed > 0, "sab speed")

var sabHist = Model.parseSabHistory(JSON.stringify({
  history: {
    slots: [
      { nzo_id: "done1", name: "A", status: "Completed" },
      { nzo_id: "fail1", name: "B", status: "Failed" }
    ]
  }
}))
assert.equal(sabHist[0].status, "completed", "hist complete")
assert.equal(sabHist[1].status, "failed", "hist fail")

var torrents = Model.parseQbitTorrents(JSON.stringify([
  { hash: "aa", name: "ubuntu.iso", state: "downloading", progress: 0.4, dlspeed: 1024, upspeed: 0, eta: 90, size: 1000 }
]))
assert.equal(torrents[0].id, "aa", "qbit hash")
assert.equal(torrents[0].progress, 0.4, "qbit progress")
var xfer = Model.parseQbitTransfer('{"dl_info_speed":2048,"up_info_speed":10}')
assert.equal(xfer.speed, 2048, "qbit xfer")

eq([[Model.headerApiKey("secret"), "X-Api-Key: secret\n", "api header"]])
has([
  [Model.sabBody("k", "queue"), "apikey=k", "sab body key"], [Model.sabBody("k", "queue"), "mode=queue", "sab body mode"],
  [Model.sabBody("k", "queue"), "limit=20", "sab queue limit"], [Model.sabBody("k", "queue"), "start=0", "sab queue start"],
  [Model.sabBody("k", "queue", { start: "20" }), "start=20", "sab queue page 2"], [Model.sabBody("k", "history"), "mode=history", "sab history mode"],
  [Model.sabBody("k", "history"), "archive=1", "sab history uses archive"], [Model.sabBody("k", "history", null, 10), "limit=10", "sab history custom limit"],
  [Model.qbitLoginBody("admin", "p a"), "username=admin", "qbit login"], [Model.qbitTorrentsUrl("http://q:8080"), "/api/v2/torrents/info?", "qbit torrents url"],
  [Model.qbitTorrentsUrl("http://q:8080"), "limit=20", "qbit limit"], [Model.qbitTorrentsUrl("http://q:8080"), "offset=0", "qbit offset 0"],
  [Model.qbitTorrentsUrl("http://q:8080", 2), "offset=20", "qbit page 2"]
])
eq([[Model.qbitLoginUrl("http://q:8080"), "http://q:8080/api/v2/auth/login", "qbit login url"]])
var manyTorrents = []
for (var ti = 0; ti < 25; ti++) {
  manyTorrents.push({ hash: "h" + ti, name: "t" + ti, state: "pausedUP", progress: 1, dlspeed: 0, upspeed: 0, eta: 0, size: 1 })
}
assert.equal(Model.parseQbitTorrents(JSON.stringify(manyTorrents)).length, 20, "qbit parse cap")
assert.equal(Model.parseQbitTorrents(JSON.stringify(manyTorrents), 10).length, 10, "qbit parse custom cap")
eq([
  [Model.qbitPauseUrl("http://q:8080"), "http://q:8080/api/v2/torrents/pause", "qbit pause url"],
  [Model.qbitResumeUrl("http://q:8080"), "http://q:8080/api/v2/torrents/resume", "qbit resume url"],
  [Model.plexIdentityUrl("http://p:32400"), "http://p:32400/identity", "plex identity url"],
  [Model.plexSessionsUrl("http://p:32400"), "http://p:32400/status/sessions", "plex sessions url"],
  [Model.plexOnDeckUrl("http://p:32400"), "http://p:32400/library/onDeck", "plex ondeck url"],
  [Model.plexArtUrl("http://p:32400", "/library/metadata/1/thumb/2"), "http://p:32400/library/metadata/1/thumb/2?width=720&height=405&minSize=1", "plex relative art"],
  [Model.plexArtUrl("http://p:32400", "https://plex.tv/photo.jpg"), "", "plex skips remote art"],
  [Model.plexCachePath("/tmp/omarr", "svc-1", "99"), "/tmp/omarr/svc-1-99-plex-hd.jpg", "plex cache path"],
  [Model.jellyfinSystemInfoUrl("http://j:8096"), "http://j:8096/System/Info", "jellyfin system url"],
  [Model.jellyfinUsersUrl("http://j:8096"), "http://j:8096/Users?isDisabled=false", "jellyfin users url"],
  [Model.jellyfinSessionsUrl("http://j:8096"), "http://j:8096/Sessions?activeWithinSeconds=300", "jellyfin sessions url"],
  [Model.jellyfinArtUrl("http://j:8096", "abc", "Backdrop"), "http://j:8096/Items/abc/Images/Backdrop?maxWidth=720&maxHeight=405&quality=90", "jellyfin art url"],
  [Model.jellyfinCachePath("/tmp/omarr", "svc-2", "abc"), "/tmp/omarr/svc-2-abc-jellyfin-hd.jpg", "jellyfin cache path"]
])
has([
  [Model.plexRecentlyAddedUrl("http://p:32400"), "/library/recentlyAdded", "plex recent url"],
  [Model.plexRecentlyAddedUrl("http://p:32400", 10), "X-Plex-Container-Size=10", "plex recent size"],
  [Model.headerPlex("tok"), "X-Plex-Token: tok\n", "plex token header"], [Model.headerPlex("tok"), "Accept: application/json", "plex json accept"],
  [Model.curlHeaderConfig(Model.headerPlex("tok")), "header = \"X-Plex-Token: tok\"", "curl config token"],
  [Model.headerJellyfin("key"), "Authorization: MediaBrowser", "jellyfin auth scheme"],
  [Model.headerJellyfin("key"), "Token=\"key\"", "jellyfin token"],
  [Model.jellyfinResumeUrl("http://j:8096", "user id", 10), "userId=user%20id", "jellyfin resume user"],
  [Model.jellyfinResumeUrl("http://j:8096", "u", 10), "limit=10", "jellyfin resume limit"],
  [Model.jellyfinLatestUrl("http://j:8096", "u", 10), "/Items/Latest?", "jellyfin latest url"]
])
assert.ok(Model.headerIsConfig(Model.headerPlex("tok")), "plex headers need curl config")
assert.ok(!Model.headerIsConfig(Model.headerApiKey("k")), "api key is one header")

var plexIdent = Model.parsePlexIdentity(JSON.stringify({ MediaContainer: { version: "1.41.2", machineIdentifier: "abc" } }))
assert.equal(plexIdent.version, "1.41.2", "plex version")
assert.ok(plexIdent.healthy === true, "plex identity ok")

var plexRecent = Model.parsePlexLibrary(JSON.stringify({
  MediaContainer: {
    Metadata: [
      {
        ratingKey: "11",
        type: "episode",
        title: "Pilot",
        grandparentTitle: "Show",
        parentIndex: 1,
        index: 1,
        thumb: "/library/metadata/11/thumb/1",
        art: "/library/metadata/9/art/1",
        audienceRating: 8.2
      },
      { ratingKey: "12", type: "movie", title: "Film", year: 2024, thumb: "/library/metadata/12/thumb/1" }
    ]
  }
}))
assert.equal(plexRecent.length, 2, "plex recent len")
assert.equal(plexRecent[0].title, "Show", "plex episode uses show title")
assert.equal(plexRecent[0].subtitle.indexOf("S01E01") !== -1, true, "plex episode code")
assert.equal(plexRecent[0].artPath, "/library/metadata/9/art/1", "plex prefers art")
assert.equal(plexRecent[0].rating, 8.2, "plex audience rating")
assert.equal(plexRecent[1].title, "Film", "plex movie title")
assert.equal(plexRecent[1].subtitle, "2024", "plex movie year")

var plexDeck = Model.parsePlexLibrary(JSON.stringify({
  MediaContainer: {
    Metadata: [{
      ratingKey: "21",
      type: "episode",
      title: "Next",
      grandparentTitle: "Show",
      parentIndex: 2,
      index: 4,
      viewOffset: 600000,
      duration: 2400000,
      thumb: "/library/metadata/21/thumb/1"
    }]
  }
}))
assert.equal(plexDeck[0].progress, 0.25, "plex ondeck progress")
assert.ok(plexDeck[0].subtitle.indexOf("%") === -1, "plex ondeck has no percent text")
assert.ok(plexDeck[0].watched !== true, "plex ondeck in progress is not watched")

var plexWatched = Model.parsePlexLibrary(JSON.stringify({
  MediaContainer: {
    Metadata: [{
      ratingKey: "22",
      type: "movie",
      title: "Done",
      year: 2020,
      viewCount: 1,
      duration: 1000
    }]
  }
}))
assert.ok(plexWatched[0].watched === true, "plex viewCount is watched")
assert.equal(plexWatched[0].progress, 0, "plex watched has no leftover progress")

var plexDone = Model.parsePlexLibrary(JSON.stringify({
  MediaContainer: {
    Metadata: [{
      ratingKey: "23",
      type: "movie",
      title: "Finished",
      viewOffset: 400,
      duration: 400
    }]
  }
}))
assert.equal(plexDone[0].progress, 1, "plex complete progress")
assert.ok(plexDone[0].watched === true, "plex complete is watched")
assert.ok(plexDone[0].subtitle.indexOf("%") === -1, "plex complete has no percent text")

var plexNow = Model.parsePlexSessions(JSON.stringify({
  MediaContainer: {
    Metadata: [{
      ratingKey: "31",
      type: "movie",
      title: "Film",
      viewOffset: 100,
      duration: 400,
      User: { title: "del" },
      Player: { title: "TV", state: "playing" }
    }]
  }
}))
assert.equal(plexNow.length, 1, "plex session")
assert.equal(plexNow[0].title, "Film", "plex watching title")
assert.ok(plexNow[0].subtitle.indexOf("del") !== -1, "plex watching user")
assert.equal(plexNow[0].progress, 0.25, "plex session progress")

// Synthetic payloads keep personal server and library data out of the test suite.
var jellyfinIdent = Model.parseJellyfinIdentity(JSON.stringify({
  ServerName: "Test Server", Version: "1.2.3", ProductName: "Jellyfin Server"
}))
assert.equal(jellyfinIdent.name, "Test Server", "jellyfin server name")
assert.equal(jellyfinIdent.version, "1.2.3", "jellyfin version")
assert.ok(jellyfinIdent.healthy === true, "jellyfin identity ok")

var jellyfinUsers = JSON.stringify([
  { Id: "disabled-user", Name: "Disabled User", Policy: { IsDisabled: true } },
  { Id: "primary-user", Name: "Primary User", Policy: { IsDisabled: false } },
  { Id: "guest-user", Name: "Guest User", Policy: { IsDisabled: false } }
])
assert.equal(Model.pickJellyfinUser(jellyfinUsers, "pRiMaRy UsEr").id, "primary-user", "jellyfin profile match")
assert.equal(Model.pickJellyfinUser(jellyfinUsers, "").id, "primary-user", "jellyfin first enabled profile")
assert.equal(Model.pickJellyfinUser(jellyfinUsers, "missing").id, "", "jellyfin missing profile")

var jellyfinStale = Model.emptySnapshot({ id: "j", kind: "jellyfin", name: "Jellyfin" })
jellyfinStale.onDeck = [{ id: "old-deck" }]
jellyfinStale.recent = [{ id: "old-recent" }]
var jellyfinMiss = Model.applyJellyfinProfileMiss(jellyfinStale, "Missing User")
assert.equal(jellyfinMiss.statusText, "Profile not found: Missing User", "jellyfin missing profile text")
assert.equal(jellyfinMiss.onDeck.length, 0, "jellyfin miss clears on deck")
assert.equal(jellyfinMiss.recent.length, 0, "jellyfin miss clears recent")
assert.equal(Model.applyJellyfinProfileMiss(jellyfinStale, "").statusText, "No enabled profile", "jellyfin no profile text")

var jellyfinDeck = Model.parseJellyfinLibrary(JSON.stringify({ Items: [{
  Id: "episode-id",
  Type: "Episode",
  Name: "First Episode",
  SeriesName: "Example Series",
  SeriesId: "series-id",
  SeriesPrimaryImageTag: "series-tag",
  ParentIndexNumber: 1,
  IndexNumber: 1,
  RunTimeTicks: 40000000,
  CommunityRating: 8.4,
  UserData: { PlaybackPositionTicks: 10000000, PlayedPercentage: 25, Played: false }
}] }), 20)
assert.equal(jellyfinDeck.length, 1, "jellyfin deck len")
assert.equal(jellyfinDeck[0].title, "Example Series", "jellyfin episode uses series title")
assert.ok(jellyfinDeck[0].subtitle.indexOf("S01E01") !== -1, "jellyfin episode code")
assert.equal(jellyfinDeck[0].progress, 0.25, "jellyfin resume progress")
assert.equal(jellyfinDeck[0].artItemId, "series-id", "jellyfin series artwork")
assert.equal(jellyfinDeck[0].rating, 8.4, "jellyfin community rating")

var jellyfinEpisodeStill = Model.parseJellyfinLibrary(JSON.stringify([{
  Id: "episode-still-id",
  Type: "Episode",
  Name: "Last Episode",
  SeriesName: "Example Series",
  SeriesId: "series-id",
  SeriesPrimaryImageTag: "series-tag",
  ImageTags: { Primary: "episode-tag" }
}]), 20)
assert.equal(jellyfinEpisodeStill[0].artItemId, "episode-still-id", "jellyfin prefers episode still")
assert.equal(jellyfinEpisodeStill[0].artType, "Primary", "jellyfin episode still type")

var jellyfinRecent = Model.parseJellyfinLibrary(JSON.stringify([{
  Id: "movie-id",
  Type: "Movie",
  Name: "Example Movie",
  ProductionYear: 2000,
  BackdropImageTags: ["backdrop-tag"],
  UserData: { Played: true }
}]), 20)
assert.equal(jellyfinRecent[0].subtitle, "2000", "jellyfin movie year")
assert.equal(jellyfinRecent[0].artItemId, "movie-id", "jellyfin movie artwork")
assert.equal(jellyfinRecent[0].artType, "Backdrop", "jellyfin prefers backdrop")
assert.ok(jellyfinRecent[0].watched === true, "jellyfin watched state")

var jellyfinNow = Model.parseJellyfinSessions(JSON.stringify([
  { UserName: "Test User", DeviceName: "Test Player", PlayState: { PositionTicks: 100, IsPaused: true }, NowPlayingItem: {
    Id: "now-id", Type: "Movie", Name: "Example Movie", RunTimeTicks: 400
  } },
  { UserName: "Idle User", DeviceName: "Idle Device" }
]), 20)
assert.equal(jellyfinNow.length, 1, "jellyfin active session")
assert.equal(jellyfinNow[0].progress, 0.25, "jellyfin session progress")
assert.ok(jellyfinNow[0].subtitle.indexOf("Test User · Test Player · Paused") !== -1, "jellyfin session context")

var jellyfinLive = Model.parseJellyfinSessions(JSON.stringify([{
  UserName: "Test User",
  DeviceName: "TV",
  PlayState: { PositionTicks: 200, IsPaused: false },
  NowPlayingItem: {
    Id: "live-id",
    Type: "Movie",
    Name: "Example Movie",
    RunTimeTicks: 400,
    UserData: { PlayedPercentage: 10, PlaybackPositionTicks: 40 }
  }
}]), 20)
assert.equal(jellyfinLive[0].progress, 0.5, "jellyfin session uses live playstate")

var snap = Model.emptySnapshot({ id: "svc-1", kind: "sonarr", name: "Sonarr", url: "http://s:8989", group: "Media" })
assert.equal(snap.health, "unknown", "empty health")
var up = Model.applyHttpHealth(snap, 200)
assert.equal(up.health, "up", "http 200")
var down = Model.applyHttpHealth(snap, 0)
assert.equal(down.health, "down", "http fail")
var unauthorized = Model.applyHttpHealth(snap, 401)
assert.equal(unauthorized.statusText, "HTTP 401", "http 401 text")

;[
  ["arr-status", true], ["sab-queue", true], ["generic", true],
  ["qbit-torrents", true], ["plex-identity", true], ["jellyfin-identity", true],
  ["plex-ondeck", false], ["plex-recent", false], ["plex-sessions", false],
  ["arr-calendar", false], ["arr-queue", false], ["arr-wanted", false],
  ["arr-history", false], ["sab-history", false], ["poster", false]
].forEach(([kind, health]) => assert.equal(Model.isHealthKind(kind), health, kind))

var hold = Model.decideHealth("up", 0, 0)
var secondMiss = Model.decideHealth("up", 0, 1)
var authDown = Model.decideHealth("up", 401, 0)
var recovered = Model.decideHealth("down", 200, 4)
var unknownFail = Model.decideHealth("unknown", 0, 0)
eq([
  [hold.health, "up", "one timeout keeps up"], [hold.misses, 1, "timeout counted"],
  [hold.commit, false, "timeout does not rewrite"], [secondMiss.health, "down", "two timeouts mark down"],
  [secondMiss.commit, true, "second timeout commits"], [authDown.health, "down", "401 marks down now"],
  [authDown.commit, true, "401 commits"], [recovered.health, "up", "200 recovers"],
  [recovered.misses, 0, "success clears misses"], [recovered.commit, true, "recovery commits"],
  [unknownFail.health, "down", "first fail from unknown is down"]
])

var sonarrSnap = Model.emptySnapshot({ id: "s", kind: "sonarr", name: "Sonarr", url: "http://s:8989", group: "Media" })
sonarrSnap.health = "up"
sonarrSnap.queue = queue
sonarrSnap.calendar = cal
sonarrSnap.showCalendar = true
var radarrSnap = Model.emptySnapshot({ id: "r", kind: "radarr", name: "Radarr", url: "http://r:7878", group: "Media" })
radarrSnap.health = "down"
radarrSnap.statusText = "Unreachable"
var sabSnap = Model.emptySnapshot({ id: "z", kind: "sabnzbd", name: "SABnzbd", url: "http://z:8080", group: "Downloads" })
sabSnap.health = "up"
sabSnap.queue = sab.queue
sabSnap.speed = sab.speed
sabSnap.showQueue = true
var nowClients = Model.mergeNow([sonarrSnap, radarrSnap, sabSnap])
assert.equal(nowClients.downloads.length, 1, "arr queue hidden by default")
assert.equal(nowClients.downloads[0].kind, "sabnzbd", "download clients only")
assert.ok(nowClients.showQueue === true, "queue pane from sab")
assert.ok(nowClients.showCalendar === true, "calendar pane from sonarr")
sonarrSnap.showQueue = true
var now = Model.mergeNow([sonarrSnap, radarrSnap, sabSnap])
assert.ok(now.downloads.length >= 2, "merged downloads")
assert.equal(now.downloads[0].protocol, "torrent", "merged protocol")
assert.ok(now.calendar.length >= 1, "merged calendar")
assert.ok(now.warnings.length === 1, "warning for down")
assert.ok(now.downloadingCount >= 1, "download count")
assert.equal(now.downCount, 1, "down count")

assert.ok(Model.fleetLine(radarrSnap).indexOf("down") !== -1, "fleet down")
assert.ok(Model.fleetLine(sabSnap).length > 0, "fleet sab")

var plexSnap = Model.emptySnapshot({ id: "p", kind: "plex", name: "Plex" })
plexSnap.health = "up"
plexSnap.sessions = plexNow
plexSnap.onDeck = plexDeck
plexSnap.recent = plexRecent
assert.ok(Model.fleetLine(plexSnap).indexOf("Watching") !== -1, "fleet watching")
var plexIdle = Model.emptySnapshot({ id: "p", kind: "plex", name: "Plex" })
plexIdle.health = "up"
plexIdle.onDeck = plexDeck
assert.ok(Model.fleetLine(plexIdle).indexOf("on deck") !== -1, "fleet on deck")
var plexNowFeed = Model.mergeNow([plexSnap])
assert.equal(plexNowFeed.sessions.length, 1, "merged sessions")
assert.ok(plexNowFeed.onDeck.length >= 1, "merged ondeck")
assert.ok(plexNowFeed.recent.length >= 2, "merged recent")

var plexPrev = Model.emptySnapshot({ id: "p", kind: "plex", name: "Plex" })
plexPrev.health = "up"
plexPrev.recent = []
var plexNext = Model.emptySnapshot({ id: "p", kind: "plex", name: "Plex" })
plexNext.health = "up"
plexNext.recent = plexRecent
var plexEvents = Model.eventsFromPoll(plexPrev, plexNext, { id: "p", kind: "plex", notifyGrab: true })
assert.ok(plexEvents.some(function(e) { return e.type === "library-added" }), "plex added event")
var added = plexEvents.filter(function(e) { return e.type === "library-added" })[0]
assert.ok(Model.shouldNotify(added, { notifyGrab: true }, []) === true, "notify plex added")
assert.ok(Model.shouldNotify(added, { notifyGrab: false }, []) === false, "plex added flag off")
assert.ok(Model.toastParts(added).title.indexOf("added") !== -1, "plex added toast")

var jellyfinSnap = Model.emptySnapshot({ id: "j", kind: "jellyfin", name: "Jellyfin" })
jellyfinSnap.health = "up"
jellyfinSnap.sessions = jellyfinNow
jellyfinSnap.onDeck = jellyfinDeck
jellyfinSnap.recent = jellyfinRecent
assert.ok(Model.fleetLine(jellyfinSnap).indexOf("Watching") !== -1, "jellyfin fleet watching")
var jellyfinFeed = Model.mergeNow([jellyfinSnap])
assert.equal(jellyfinFeed.sessions[0].kind, "jellyfin", "jellyfin merged session")
var jellyfinPrev = Model.emptySnapshot({ id: "j", kind: "jellyfin", name: "Jellyfin" })
jellyfinPrev.health = "up"
var jellyfinEvents = Model.eventsFromPoll(jellyfinPrev, jellyfinSnap, { id: "j", kind: "jellyfin", notifyGrab: true })
assert.ok(jellyfinEvents.some(function(e) { return e.type === "library-added" }), "jellyfin added event")

var badge = Model.barBadge([sonarrSnap, radarrSnap, sabSnap])
assert.ok(badge.urgent === true, "badge urgent when down")
assert.ok(badge.count >= 1, "badge count")
sonarrSnap.showQueue = false
assert.equal(Model.barBadge([sonarrSnap]).count, 0, "arr queue not in badge by default")
sonarrSnap.showQueue = true
assert.ok(Model.barBadge([sonarrSnap]).count >= 1, "arr queue in badge when on")
assert.ok(Model.barStatusText([sonarrSnap, radarrSnap]).indexOf("Radarr") !== -1, "bar status names down")
sonarrSnap.showQueue = false
assert.ok(Model.barStatusText([sonarrSnap]).indexOf("downloading") === -1, "bar status skips arr queue")
sonarrSnap.showQueue = true
assert.ok(Model.barStatusText([sonarrSnap]).indexOf("downloading") !== -1, "bar status counts arr queue")
sonarrSnap.showQueue = false

var prev = Model.emptySnapshot({ id: "s", kind: "sonarr", name: "Sonarr", url: "http://s", group: "Media" })
prev.health = "up"
prev.activity = []
var next = Model.emptySnapshot({ id: "s", kind: "sonarr", name: "Sonarr", url: "http://s", group: "Media" })
next.health = "up"
next.activity = arrHist
var svc = { id: "s", kind: "sonarr", notifyGrab: true, notifyHealth: true, notifyDownload: true, notifyImport: true }
var events = Model.eventsFromPoll(prev, next, svc)
assert.ok(events.some(function(e) { return e.type === "grabbed" }), "grabbed event")
assert.ok(events.some(function(e) { return e.type === "import" }), "import event")
assert.ok(events.some(function(e) { return e.type === "download-failed" }), "arr failed event")
var queueOnly = Model.emptySnapshot({ id: "s", kind: "sonarr", name: "Sonarr" })
queueOnly.health = "up"
queueOnly.queue = queue
assert.ok(!Model.eventsFromPoll(prev, queueOnly, svc).some(function(e) { return e.type === "grabbed" }), "queue does not fake grab")

var downPrev = Model.emptySnapshot({ id: "s", kind: "sonarr", name: "Sonarr", url: "http://s", group: "Media" })
downPrev.health = "up"
var downNext = Model.emptySnapshot({ id: "s", kind: "sonarr", name: "Sonarr", url: "http://s", group: "Media" })
downNext.health = "down"
var healthEvents = Model.eventsFromPoll(downPrev, downNext, svc)
assert.ok(healthEvents.some(function(e) { return e.type === "service-down" }), "service down event")

var recovered = Model.eventsFromPoll(downNext, downPrev, svc)
assert.ok(recovered.some(function(e) { return e.type === "service-up" }), "service up event")

var grab = events.filter(function(e) { return e.type === "grabbed" })[0]
assert.ok(Model.shouldNotify(grab, svc, []) === true, "notify new grab")
assert.ok(Model.shouldNotify(grab, svc, [grab.id]) === false, "skip seen")
assert.ok(Model.shouldNotify(grab, { notifyGrab: false }, []) === false, "flag off")
var imported = events.filter(function(e) { return e.type === "import" })[0]
assert.ok(Model.shouldNotify(imported, svc, []) === true, "notify import")
assert.ok(Model.shouldNotify(imported, { notifyImport: false }, []) === false, "import flag off")
var grabParts = Model.toastParts(grab)
var importParts = Model.toastParts(imported)
assert.ok(importParts.title.indexOf("imported") !== -1, "import toast title")
assert.ok(grabParts.title && grabParts.body && grabParts.glyph, "toast parts")
var toastCmd = Model.toastCommand(grab)
assert.equal(toastCmd[0], "omarchy-notification-send", "toast binary")
assert.ok(toastCmd.indexOf("--exec") > toastCmd.indexOf(grabParts.title), "exec after headline")
assert.equal(toastCmd[toastCmd.indexOf("--exec") + 1], "omarchy-shell", "exec is split argv")
assert.ok(toastCmd[toastCmd.indexOf("--exec") + 1].indexOf(" ") === -1, "exec not one quoted string")
assert.equal(toastCmd[toastCmd.indexOf("--exec") + 4], Model.PLUGIN_ID, "summon plugin id")

var sabPrev = Model.emptySnapshot({ id: "z", kind: "sabnzbd", name: "SABnzbd", url: "http://z", group: "Downloads" })
sabPrev.health = "up"
sabPrev.activity = []
var sabNext = Model.emptySnapshot({ id: "z", kind: "sabnzbd", name: "SABnzbd", url: "http://z", group: "Downloads" })
sabNext.health = "up"
sabNext.activity = sabHist
var sabEvents = Model.eventsFromPoll(sabPrev, sabNext, { id: "z", kind: "sabnzbd", notifyDownload: true })
assert.ok(sabEvents.some(function(e) { return e.type === "download-finished" }), "sab finished")
assert.ok(sabEvents.some(function(e) { return e.type === "download-failed" }), "sab failed")

assert.ok(Model.scanTargets().length >= 8, "scan list")
assert.equal(Model.scanHitsForPort(8080).length, 2, "port 8080 hits both downloaders")
eq([
  [Model.scanUrl("127.0.0.1", 8989), "http://127.0.0.1:8989", "scan url"], [Model.kindFromPort(8989), "sonarr", "port sonarr"],
  [Model.kindFromPort(7878), "radarr", "port radarr"], [Model.kindFromPort(8080), "generic", "port 8080 ambiguous"],
  [Model.kindFromPort(8096), "jellyfin", "port jellyfin"], [Model.kindFromPort(32400), "plex", "port plex"],
  [Model.defaultUrlForKind("plex"), "http://127.0.0.1:32400", "default plex url"],
  [Model.kindLabel("plex"), "Plex", "plex label"], [Model.formatSpeed(1536), "1.5 KB/s", "speed"],
  [Model.formatBytes(1048576), "1.0 MB", "bytes"], [Model.kindLabel("qbittorrent"), "qBittorrent", "kind label"]
])
assert.ok(Model.formatEta(90).indexOf("m") !== -1 || Model.formatEta(90).indexOf("s") !== -1, "eta")
;[
  [{ kind: "plex", name: "Living Room" }, "plex", "plex kind icon"],
  [{ kind: "radarr" }, "radarr", "radarr kind icon"],
  [{ kind: "sonarr", name: "Sonarr LQ" }, "sonarr", "sonarr kind wins"],
  [{ kind: "sabnzbd" }, "sabnzbd", "sab icon"],
  [{ kind: "qbittorrent" }, "qbittorrent", "qbit icon"],
  [{ kind: "generic", name: "Jellyfin" }, "jellyfin", "jellyfin by name"],
  [{ kind: "generic", name: "Home Assistant" }, "home-assistant", "ha by name"],
  [{ kind: "generic", name: "Plex" }, "plex", "plex by name"],
  [{ kind: "generic", name: "Prowlarr" }, "prowlarr", "prowlarr by name"],
  [{ kind: "generic", name: "Mystery Box" }, "", "unknown has no icon"],
  [{ kind: "generic", name: "Transmission" }, "transmission", "transmission by name"],
  [{ kind: "generic", name: "Lidarr" }, "lidarr", "lidarr by name"]
].forEach(([svc, slug, msg]) => assert.equal(Model.iconSlug(svc), slug, msg))
eq([
  [Model.iconPageUrl("radarr"), "https://dashboardicons.com/icons/radarr", "icon page"],
  [Model.iconPageUrl(""), "", "empty icon page"],
  [Model.iconCdnUrl("radarr"), "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/radarr.svg", "icon cdn"]
])
assert.ok(Model.iconSlugs().indexOf("sonarr") !== -1, "bundled sonarr")
assert.ok(Model.iconSlugs().indexOf("radarr") !== -1, "bundled radarr")

var slugs = Model.iconSlugs()
assert.ok(slugs.length >= 30, "bundled icon count")
for (var i = 0; i < slugs.length; i++) {
  assert.ok(fs.existsSync(path.join(__dirname, "..", "icons", slugs[i] + ".svg")), "svg " + slugs[i])
}

eq([
  [Model.posterCachePath("/tmp/omarr", "svc-1", "12"), "/tmp/omarr/svc-1-12-poster-hd.jpg", "poster path"],
  [Model.fanartCachePath("/tmp/omarr", "svc-1", "12"), "/tmp/omarr/svc-1-12-fanart-hd.jpg", "fanart path"],
  [Model.fileUrl("/tmp/omarr/svc-1-12-poster-hd.jpg", 3), "file:///tmp/omarr/svc-1-12-poster-hd.jpg?3", "file url"],
  [Model.fileUrl("", 1), "", "file url empty"],
  [Model.fleetOrderKey([{ id: "a", order: 2 }, { id: "b", order: 0 }]), "a:2,b:0", "fleet order key keeps 0"]
])

var keep = [{ id: "a", title: "Old", progress: 0.2 }]
var newer = [{ id: "a", title: "New", progress: 0.8 }]
var reused = Model.reuseFeedList(keep, newer)
assert.ok(reused === keep, "reuse same ids")
assert.equal(keep[0].title, "New", "reuse patches fields")
assert.equal(keep[0].progress, 0.8, "reuse patches progress")
var swapped = Model.reuseFeedList(keep, [{ id: "b", title: "Other" }])
assert.ok(swapped !== keep, "new ids replace list")

function sabProgressSnap(queue, extra) {
  var snap = {
    id: "sab",
    kind: "sabnzbd",
    name: "SABnzbd",
    paused: false,
    speed: 1024 * 1024,
    queue: queue
  }
  if (extra) for (var k in extra) snap[k] = extra[k]
  return snap
}

function qbitItem(id, title, status, progress, dlspeed) {
  return {
    id: id,
    title: title,
    status: status,
    progress: progress,
    dlspeed: dlspeed,
    timeleft: "10m",
    kind: "qbittorrent"
  }
}

assert.ok(Model.progressToast([]) === null, "progress toast empty")
assert.ok(Model.progressToast([{
  id: "son", kind: "sonarr", name: "Sonarr",
  queue: [{ id: "1", title: "Show", status: "downloading", progress: 0.4, kind: "sonarr" }]
}]) === null, "progress toast skips arr")

var sabJob = Model.progressToast([sabProgressSnap([{
  id: "nzo1", title: "Show.S01E01", status: "downloading", progress: 0.4, timeleft: "00:10:00", kind: "sabnzbd"
}])])
assert.ok(sabJob && sabJob.key === "sab:nzo1", "progress toast sab key")
assert.equal(sabJob.title, "Show.S01E01", "progress toast sab title")
assert.equal(sabJob.kind, "sabnzbd", "progress toast sab kind")
assert.equal(sabJob.progress, 0.4, "progress toast sab progress")
assert.equal(sabJob.speed, 1024 * 1024, "progress toast sab speed")

assert.ok(Model.progressToast([sabProgressSnap([{
  id: "nzo1", title: "Show.S01E01", status: "downloading", progress: 0.4, kind: "sabnzbd"
}], { paused: true })]) === null, "progress toast skips paused sab")

assert.ok(Model.progressToast([sabProgressSnap([{
  id: "nzo1", title: "Queued", status: "queued", progress: 0, kind: "sabnzbd"
}])]) === null, "progress toast skips queued sab")

assert.ok(Model.progressToast([sabProgressSnap([{
  id: "nzo1", title: "Show.S01E01", status: "downloading", progress: 0, kind: "sabnzbd"
}], { speed: 0 })]) !== null, "progress toast shows sab at start")

var qbitSnap = {
  id: "qbit",
  kind: "qbittorrent",
  name: "qBittorrent",
  queue: [
    qbitItem("seed", "Old Movie", "uploading", 1, 0),
    qbitItem("slow", "Show A", "downloading", 0.2, 1000),
    qbitItem("fast", "Show B", "downloading", 0.8, 9000)
  ]
}
var qbitJob = Model.progressToast([qbitSnap])
assert.ok(qbitJob && qbitJob.key === "qbit:fast", "progress toast picks fastest")
assert.equal(qbitJob.title, "Show B", "progress toast fastest title")

assert.ok(Model.progressToast([{
  id: "qbit", kind: "qbittorrent", name: "qBittorrent",
  queue: [
    qbitItem("seed", "Seeded", "uploading", 1, 0),
    qbitItem("done", "Done", "stalledup", 1, 0),
    qbitItem("full", "Finished", "downloading", 1, 5000)
  ]
}]) === null, "progress toast skips seeding")

var nextJob = Model.progressToast([qbitSnap], "qbit:fast")
assert.ok(nextJob && nextJob.key === "qbit:slow", "progress toast skip dismissed")
assert.ok(Model.progressToastStale("qbit:gone", [qbitSnap]) === true, "stale dismissed key")
assert.ok(Model.progressToastStale("qbit:fast", [qbitSnap]) === false, "active dismissed key stays")

var posted = Model.progressToast([
  sabProgressSnap([{
    id: "nzo1", title: "Show.S01E01", status: "downloading", progress: 0.4, kind: "sabnzbd"
  }]),
  {
    id: "son", kind: "sonarr", name: "Sonarr",
    queue: [{ id: "9", title: "Show.S01E01", posterId: "12", downloadId: "abc", kind: "sonarr" }]
  }
])
assert.equal(posted.posterServiceId, "son", "progress toast poster service")
assert.equal(posted.posterId, "12", "progress toast poster id")

var hashed = Model.progressToast([
  {
    id: "qbit", kind: "qbittorrent", name: "qBittorrent",
    queue: [qbitItem("deadbeef", "Movie.2024", "downloading", 0.5, 2000)]
  },
  {
    id: "rad", kind: "radarr", name: "Radarr",
    queue: [{ id: "3", title: "Other", posterId: "44", downloadId: "deadbeef", kind: "radarr" }]
  }
])
assert.equal(hashed.posterId, "44", "progress toast matches torrent hash")

assert.equal(Model.DOWNLOAD_POLL_MS, 2000, "downloader poll ms")
assert.ok(Model.downloaderBusy([]) === false, "downloader idle empty")
assert.ok(Model.downloaderBusy([sabProgressSnap([{
  id: "nzo1", title: "Show.S01E01", status: "downloading", progress: 0.4, kind: "sabnzbd"
}])]) === true, "downloader busy sab")
assert.ok(Model.downloaderBusy([sabProgressSnap([{
  id: "nzo1", title: "Show.S01E01", status: "downloading", progress: 0.4, kind: "sabnzbd"
}], { paused: true })]) === false, "downloader idle paused sab")
assert.ok(Model.downloaderBusy([qbitSnap]) === true, "downloader busy qbit")
assert.ok(Model.downloaderBusy([{
  id: "qbit", kind: "qbittorrent", name: "qBittorrent",
  queue: [qbitItem("seed", "Seeded", "uploading", 1, 0)]
}]) === false, "downloader idle seeding")
assert.ok(Model.downloaderBusy([{
  id: "son", kind: "sonarr", name: "Sonarr",
  queue: [{ id: "1", title: "Show", status: "downloading", progress: 0.4, kind: "sonarr" }]
}]) === false, "downloader idle arr")

console.log("Model.test.js ok")
