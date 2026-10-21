-- Run from the project root: lua tests/run.lua
local function loadPlugin(path, mode, env)
    return loadfile("noctalia-lyric/" .. path, mode or "t", env or _G)
end
local checks = 0
local function equal(actual, expected, message)
    checks = checks + 1
    assert(actual == expected, (message or "unexpected value") .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
end
local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, child in pairs(value) do result[key] = copy(child) end
    return result
end
local function decodeUrl(value)
    return (value:gsub("%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end))
end
local lrc = assert(loadPlugin("lib/lrc.luau"))()
local lines = lrc.parse("\239\187\191[ar:Test]\r\n[00:02.25]Later\r\n[00:01.1][00:03.125]First\n[00:01.1]翻译\n[00:04]\n[offset:100]\n[00:99]Invalid")
equal(#lines, 4, "multi-stamp and translation merge")
equal(lines[1].time, 1000, "fraction and global offset")
equal(lines[1].text, "First / 翻译", "stable bilingual order")
equal(lines[2].time, 2150, "centiseconds")
equal(lines[3].time, 3025, "milliseconds")
local first, nextLine = lrc.at(lines, 999)
equal(first, "", "before first line")
equal(nextLine, "First / 翻译")
first, nextLine = lrc.at(lines, 2150)
equal(first, "Later", "exact timestamp")
equal(nextLine, "First")
equal(lrc.at(lines, 5000), "", "blank instrumental break")
equal(lrc.at(lines, 1000), "First / 翻译", "seek backwards")
equal(#lrc.parse(nil), 0)
equal(#lrc.parse("not lrc\n[garbage]"), 0)
equal(lrc.parse("[offset:-50]\n[00:01]<00:01.1>Word<00:01.2> time")[1].time, 1050)
equal(lrc.parse("[00:01]<00:01.1>Word<00:01.2> time")[1].text, "Word time")

local moduleEnv = setmetatable({ noctalia = { string = { urlDecode = decodeUrl } } }, { __index = _G })
local mediaLib = assert(loadPlugin("lib/media.luau", "t", moduleEnv))()
local function variant(kind, data) return { type = kind, data = data } end
local function props(title, status, position, embedded, art)
    return { PlaybackStatus = variant("s", status or "Paused"), Rate = variant("d", 1), Position = variant("x", position or 1000000),
        Metadata = variant("a{sv}", { ["xesam:title"] = variant("s", title or "Song"), ["xesam:artist"] = variant("as", { "Artist" }),
            ["mpris:trackid"] = variant("o", "/track/" .. (title or "Song")), ["mpris:length"] = variant("x", 180000000),
            ["xesam:asText"] = variant("s", embedded or ""), ["mpris:artUrl"] = variant("s", art or "") }) }
end
local node = { name = mediaLib.prefix .. "test.instance", owner = ":1.10", properties = props(), positionMs = 1500, sampledAtMs = 1000 }
local media = mediaLib.snapshot(node, 1000)
equal(media.positionMs, 1500); equal(media.duration, 180); equal(media.player, "test.instance")
equal(mediaLib.matches(node.name, "test"), true)
equal(mediaLib.matches(node.name, "other"), false)
equal(mediaLib.position({ playing = true, positionMs = 1000, sampledAtMs = 1000, rate = 2 }, 5000), 9000, "rate-aware uninterrupted interpolation")
equal(mediaLib.position({ playing = false, positionMs = 1000, sampledAtMs = 1000 }, 5000), 1000)
equal(mediaLib.filePath("file:///music/Hello%20World.jpg"), "/music/Hello World.jpg")
equal(mediaLib.filePath("file://remote/path.jpg"), nil)
equal(mediaLib.filePath("file:///music/%00.jpg"), nil)
local name, owner = mediaLib.prefix .. "test.instance", ":1.10"
local function service(playerName)
    local fake = { now = 1000, requests = {}, httpRequests = {}, httpCount = 0, state = {}, publications = {}, downloads = {}, removed = {}, streams = 0, json = {}, serial = 0 }
    local api = {
        nowMs = function() return fake.now end, getConfig = function(k)
            if k == "player" then return fake.filter or "" end
            if k == "splayer_lyrics" then return fake.splayerEnabled ~= false end
            if k == "splayer_port" then return fake.port or 25884 end
            return 30000
        end,
        pluginDataDir = function() return "/tmp/noctalia-lyric-test" end, commandExists = function() return true end,
        setUpdateInterval = function() end, fileExists = function() return true end,
        runStream = function(cmd, cb) fake.streams = fake.streams + 1; fake.stream = cb; fake.streamCommand = cmd; return true end,
        runAsync = function(argv, cb) fake.requests[#fake.requests + 1] = { argv = argv, callback = cb }; return true end,
        http = function(request, cb)
            fake.httpCount = fake.httpCount + 1
            fake.httpRequests[#fake.httpRequests + 1] = { url = request.url, callback = cb }
            return true
        end,
        download = function(url, path, cb) fake.downloads[#fake.downloads + 1] = { url = url, path = path, callback = cb }; return true end,
        removeFile = function(path) fake.removed[#fake.removed + 1] = path end,
        state = { get = function(k) return fake.state[k] end, set = function(k,v)
            fake.state[k] = copy(v); fake.publications[k] = (fake.publications[k] or 0) + 1 end },
        json = { decode = function(token) return fake.json[token] end }, string = { urlDecode = decodeUrl },
    }
    local env = setmetatable({ noctalia = api }, { __index = _G })
    env.require = function(path)
        local module = assert(loadPlugin(path, "t", env))()
        if path == "./lib/lrc.luau" then
            local parse = module.parse
            module.parse = function(text) fake.parses = (fake.parses or 0) + 1; return parse(text) end
        end
        if path == "./lib/splayer.luau" then
            local parse = module.parse
            module.parse = function(data, media) fake.splayerParses = (fake.splayerParses or 0) + 1; return parse(data, media) end
        end
        return module
    end
    assert(loadPlugin("service.luau", "t", env))()
    fake.env = env
    function fake:encode(data) self.serial = self.serial + 1; local token = "json" .. self.serial; self.json[token] = data; return token end
    function fake:reply(data, index)
        local request = table.remove(self.requests, index or 1); assert(request, "pending request")
        request.callback({ exitCode = 0, stdout = self:encode(data) }); return request
    end
    function fake:httpReply(data)
        local request = table.remove(self.httpRequests, 1); assert(request, "pending HTTP request")
        request.callback({ ok = true, status = 200, body = self:encode(data) })
    end
    function fake:signal(sender, interface, member, data)
        self.stream(self:encode({ type = "signal", sender = sender, interface = interface, member = member,
            path = "/org/mpris/MediaPlayer2", payload = { data = data } }))
    end
    function fake:change(data, invalidated)
        self:signal(owner, "org.freedesktop.DBus.Properties", "PropertiesChanged", { "org.mpris.MediaPlayer2.Player", data, invalidated or {} })
    end
    function fake:tick(ms) self.now = self.now + (ms or 1000); self.env.update() end
    function fake:start(properties)
        self:reply({ { name = playerName or name, connection = owner }, { name = mediaLib.prefix .. "inactive", connection = "(activatable)" } })
        self:reply({ type = "a{sv}", data = { properties or props() } })
    end
    return fake
end
local fake = service(); fake:start(props("A", "Paused", 1000000, "[00:00]First\n[00:02]Next", "file:///music/art.jpg"))
equal(fake.state.media.embeddedLyrics, nil, "raw lyrics never ride along with media position updates")
equal(fake.streams, 1); equal(fake.state.media.title, "A"); equal(fake.state.lyrics.source, "mpris")
equal(fake.parses, 1); equal(fake.state.lyrics.lines[1].text, "First"); equal(fake.state.media.cover, "/music/art.jpg")
local publications = fake.publications.media
for _ = 1, 120 do fake:tick() end
equal(#fake.requests, 0, "paused player creates no query processes")
equal(fake.publications.media, publications, "paused player publishes no repeated snapshots")
equal(fake.streams, 1, "heartbeat never duplicates the listener")
fake:change({ Volume = variant("d", 0.5) })
equal(fake.publications.media, publications, "unrelated D-Bus signals are ignored")
fake:signal(":9.99", "org.mpris.MediaPlayer2.Player", "Seeked", { 999000000 })
equal(fake.state.media.positionMs, 1000, "reject signals from unrelated owners")
fake:signal(owner, "org.mpris.MediaPlayer2.Player", "Seeked", { 3000000 })
equal(fake.state.media.positionMs, 3000, "seek takes effect without a query")
fake:signal(owner, "org.mpris.MediaPlayer2.Player", "Seeked", { 500000 })
equal(fake.state.media.positionMs, 500, "backward seek")
local lyricPublications = fake.publications.lyrics
fake:change({ PlaybackStatus = variant("s", "Playing") })
fake:tick(30000)
equal(#fake.requests, 1, "playing uses low-frequency calibration")
equal(fake.requests[1].argv[5], "get-property", "calibration reads only Position")
fake:reply({ type = "x", data = { 30500000 } })
equal(fake.publications.lyrics, lyricPublications, "position calibration does not reparse or publish lyrics")
fake:change({ PlaybackStatus = variant("s", "Paused") })
fake:change({ Metadata = props("B", nil, nil, "").Metadata })
equal(fake.state.lyrics.status, "missing", "no lyrics immediately falls back without a lookup")
equal(#fake.requests, 0); equal(#fake.downloads, 0)
equal(fake.removed[1], nil, "never delete player-owned album art")
fake:change({ Metadata = props("A", nil, nil, "[00:00]First\n[00:02]Next").Metadata })
equal(fake.state.lyrics.lines[1].text, "First", "returning to cached MPRIS lyrics")
equal(fake.parses, 1, "cache hit skips parsing; missing lyrics skip parsing too")
fake:change({ Metadata = props("A", nil, nil, "[00:00]Arrived later").Metadata })
equal(fake.state.lyrics.lines[1].text, "Arrived later", "same-track lyrics updates")
equal(fake.parses, 2)
fake:signal("org.freedesktop.DBus", "org.freedesktop.DBus", "NameOwnerChanged", { name, owner, "" })
equal(fake.state.media.available, false, "player exit clears media immediately")
for _ = 1, 120 do fake:tick() end
equal(#fake.requests, 0, "no-player idle never polls")
fake.stream("__NOCTALIA_MPRIS_CLOSED__")
fake:tick(500)
equal(fake.streams, 1, "listener restart backs off")
fake:tick(1000)
equal(fake.streams, 2, "listener restarts after an actual exit")
fake.env.onExit(); fake:tick(60000)
equal(fake.streams, 2, "stopped service cannot restart")
local invalidated = service(); invalidated:start(props())
invalidated:change({}, { "Metadata" })
invalidated:change({}, { "Metadata" })
equal(#invalidated.requests, 1, "coalesce simultaneous invalidations")
invalidated:reply({ type = "a{sv}", data = { props("Old") } })
equal(#invalidated.requests, 1, "a fresh snapshot follows an invalidation received during a query")
invalidated:reply({ type = "a{sv}", data = { props("New") } })
equal(invalidated.state.media.title, "New")
local failed = service()
failed:reply({ { name = name, connection = owner } })
failed:reply(nil)
failed:tick(2000)
equal(#failed.requests, 1, "retry an unavailable initial MPRIS object")
failed:reply(nil); failed:tick(4000); failed:reply(nil)
for _ = 1, 100 do failed:tick() end
equal(#failed.requests, 0, "initial read failure retries are bounded")
local racing = service()
racing:reply({ { name = name, connection = owner } })
racing:signal("org.freedesktop.DBus", "org.freedesktop.DBus", "NameOwnerChanged", { name, owner, "" })
racing:reply({ type = "a{sv}", data = { props("Old") } })
equal(racing.state.media.available, false, "late snapshot cannot revive an exited player")
local cover = service(); cover:start(props("A", nil, nil, "", "https://art.test/a"))
cover:change({ Metadata = props("B", nil, nil, "", "https://art.test/b").Metadata })
cover.downloads[1].callback(true)
equal(cover.state.media.cover, nil, "late downloaded cover is discarded")
cover.downloads[2].callback(true)
equal(cover.state.media.cover, cover.downloads[2].path)
cover.env.onExit(); equal(cover.removed[#cover.removed], cover.downloads[2].path, "owned artwork cleanup")

local function song(title, loading)
    return { code = 200, data = { name = title, lyricLoading = loading or false, lrcData = {
        { startTime = 0, words = { { word = title }, { word = " lyric" } } },
        { startTime = 2000, words = { { word = "Next line" } } },
    } } }
end
local splayerLib = assert(loadPlugin("lib/splayer.luau"))()
local parsed, waiting = splayerLib.parse(song("A").data, { trackId = "/track/A", title = "A" })
equal(parsed[1].text, "A lyric", "SPlayer words become line text without retaining word timing")
equal(waiting, false)
local idSong = song("Different title").data; idSong.id = 123
equal(#splayerLib.parse(idSong, { trackId = "/com/splayer/track/123", title = "A" }), 2, "match SPlayer's numeric track ID")
equal(#splayerLib.parse(idSong, { trackId = "/com/splayer/track/124", title = "A" }), 0, "reject lyrics from the previous track")
idSong.lrcData = { { startTime = 0/0, words = { { word = "invalid" } } } }
equal(#splayerLib.parse(idSong, { trackId = "/track/123", title = "A" }), 0, "reject non-finite lyric timestamps")
local spName = mediaLib.prefix .. "splayer.instance"
local localPlayer = service(spName); localPlayer:start(props("A"))
equal(localPlayer.httpCount, 1, "one local lyric request when a SPlayer track appears")
equal(localPlayer.httpRequests[1].url, "http://127.0.0.1:25884/api/control/song-info", "only the player's loopback API is contacted")
localPlayer:httpReply(song("A"))
equal(localPlayer.state.lyrics.source, "splayer")
equal(localPlayer.state.lyrics.lines[1].text, "A lyric")
local localPublications = localPlayer.publications.lyrics
for _ = 1, 120 do localPlayer:tick() end
equal(localPlayer.httpCount, 1, "paused SPlayer does not poll HTTP")
equal(localPlayer.splayerParses, 1, "cached SPlayer lyrics are parsed only once")
equal(localPlayer.publications.lyrics, localPublications, "unchanged local lyrics are not republished")
localPlayer:signal(owner, "org.mpris.MediaPlayer2.Player", "Seeked", { 3000000 })
equal(localPlayer.httpCount, 1, "seeking does not reload complete lyrics")
localPlayer:change({ Metadata = props("B").Metadata })
localPlayer:change({ Metadata = props("C").Metadata })
equal(#localPlayer.httpRequests, 1, "local lyric requests are serialized")
localPlayer:httpReply(song("B"))
equal(localPlayer.state.lyrics.status, "missing", "late HTTP response cannot restore a previous track")
localPlayer:tick(); localPlayer:httpReply(song("C"))
equal(localPlayer.state.lyrics.lines[1].text, "C lyric")
localPlayer:change({ Metadata = props("A").Metadata })
equal(localPlayer.httpCount, 3, "returning to a cached song does not fetch again")
equal(localPlayer.state.lyrics.lines[1].text, "A lyric")
localPlayer:change({ PlaybackStatus = variant("s", "Playing") }); localPlayer:tick(30000)
localPlayer:reply({ type = "x", data = { 10000000 } })
equal(localPlayer.httpCount, 3, "position calibration does not reload local lyrics")
localPlayer.env.onConfigChanged()
equal(localPlayer.httpCount, 3, "unrelated config updates preserve the lyric cache")
localPlayer.splayerEnabled = false; localPlayer.env.onConfigChanged()
equal(localPlayer.state.lyrics.status, "missing", "disabling the fallback clears cached SPlayer lyrics")
equal(localPlayer.httpCount, 3)
localPlayer.splayerEnabled = true; localPlayer.env.onConfigChanged()
equal(localPlayer.httpCount, 4, "enabling the fallback reads the current song")
local delayed = service(spName); delayed:start(props("A"))
for attempt = 1, 4 do
    delayed:httpReply(song("A", true))
    delayed:tick(2000)
end
for _ = 1, 100 do delayed:tick() end
equal(delayed.httpCount, 4, "lyric-loading retries are bounded")
equal(#delayed.httpRequests, 0, "no idle retry loop after the limit")
local preferred = service(spName); preferred:start(props("A"))
preferred:change({ Metadata = props("A", nil, nil, "[00:00]MPRIS wins").Metadata })
preferred:httpReply(song("A"))
equal(preferred.state.lyrics.source, "mpris", "late local response cannot overwrite MPRIS lyrics")
equal(preferred.state.lyrics.lines[1].text, "MPRIS wins")
local stopped = service(spName); stopped:start(props("A"))
stopped.env.onExit(); stopped:httpReply(song("A"))
equal(stopped.state.lyrics.status, "missing", "HTTP callbacks are inert after service shutdown")
local disabled = service(spName); disabled.splayerEnabled = false; disabled:start(props("A"))
equal(disabled.httpCount, 0, "local SPlayer fallback can be disabled")
local custom = service(spName); custom.port = 12345; custom:start(props("A"))
equal(custom.httpRequests[1].url, "http://127.0.0.1:12345/api/control/song-info", "configured port retains loopback-only scope")
table.remove(custom.httpRequests, 1).callback({ ok = false, status = 0 })
for _ = 1, 100 do custom:tick() end
equal(custom.httpCount, 1, "unavailable API does not create a retry loop")

-- Render the real widget with recorded Noctalia snapshots and native control stubs.
local defaults = {
    hide_paused = false, hide_idle = true, font_family = "", time_offset = 0, text_width = 260,
    font_size = 13, font_weight = "medium", text_align = "start", text_color = "on_surface", second_line = "next",
    dual_font_size = 10, secondary_font_size = 8, secondary_color = "on_surface_variant", show_cover = true, cover_size = 28,
    cover_radius = 6, line_gap = 0, cover_gap = 9, padding_h = 4, padding_v = 1,
    background_radius = 12, show_background = false, background_color = "surface_variant",
    poll_interval = 500, content_height = 22, dim_paused = true, text_opacity = 1,
    show_progress = true, progress_color = "primary", progress_opacity = 0.25,
    transition = "none", transition_duration = 240,
}
local view, tooltip, visible, vertical, command, clockNow, interval = nil, nil, nil, nil, nil, 1000, nil
local watchers, state = {}, { media = { available = true, playing = true, title = "Test", artist = "Artist",
    player = "test.instance", positionMs = 1000, duration = 4, cover = "/art.png" },
    lyrics = { status = "synced", lines = lrc.parse("[00:00]Current\n[00:02]Next") } }
local env = setmetatable({ ui = {} }, { __index = _G })
for _, name in ipairs({ "row", "column", "label", "glyph", "image", "box", "progress" }) do
    env.ui[name] = function(props, children) return { kind = name, props = props, children = children } end
end
env.noctalia = {
    getConfig = function(key) assert(defaults[key] ~= nil, key); return defaults[key] end,
    tr = function(key) return key end, setUpdateInterval = function(value) interval = value end,
    nowMs = function() return clockNow end,
    getColor = function(role) return role end, getSetting = function() return "sans-serif" end,
    commandExists = function() return false end,
    runAsync = function(argv) command = argv end,
    state = { get = function(key) return state[key] end,
        watch = function(key, callback) watchers[key] = callback end },
}
env.barWidget = { setVisible = function(value) visible = value end,
    isVertical = function() return vertical end, render = function(value) view = value end,
    setTooltip = function(value) tooltip = value end }
env.require = function(path)
        if path == "./media.luau" then path = "lib/media.luau" end
        return assert(loadPlugin(path, "t", env))()
    end
assert(loadPlugin("widget.luau", "t", env))()
equal(visible, true)
equal(view.kind, "row")
equal(view.children[2].children[2].children[1].props.fill, "surface/0", "empty outgoing layer stays transparent")
local function find(node, key)
    if node.props.key == key then return node end
    for _, child in ipairs(node.children or {}) do
        local result = find(child, key)
        if result then return result end
    end
end
local function text(key) return find(find(view, "incoming"), key).children[1].props.text end
equal(find(view, "cover").kind, "image", "cover on left")
equal(text("current"), "Current", "lyrics on right")
equal(text("next"), "Next")
equal(find(find(view, "incoming"), "current").children[1].props.fontFamily, nil, "inherit default font")
equal(find(view, "progress").props.progress, 0.25, "native background progress")
equal(view.props.gap, -find(view, "content").props.width, "background overlays content without growing width")
equal(find(view, "incoming").props.height, 20, "padding is included in fixed content height")
equal(find(find(view, "incoming"), "current").props.height + find(find(view, "incoming"), "next").props.height + defaults.line_gap, 18, "compact rows leave balanced outer padding")
equal(find(view, "incoming").props.justify, "center", "compact pair is centered as one block")
equal(find(find(view, "incoming"), "current").children[1].props.fontSize, 10)
equal(find(find(view, "incoming"), "next").children[1].props.fontSize, 8)
defaults.show_progress = false
env.onConfigChanged()
equal(find(view, "progress"), nil, "progress background switch")
defaults.show_progress = true
equal(tooltip:find("Current", 1, true) ~= nil, true, "tooltip includes full lyric")
equal(env.onClick, nil, "clicks use native gesture actions without spawning a process")
defaults.second_line = "off"
env.onConfigChanged()
equal(#find(view, "incoming").children, 1)
equal(find(find(view, "incoming"), "current").children[1].props.fontSize, 13, "single-line font stays unchanged")
defaults.time_offset = 1000
env.onConfigChanged()
equal(text("current"), "Next", "positive timing offset")
defaults.hide_paused = true
env.onConfigChanged()
watchers.media({ available = true, playing = false })
equal(visible, false)
watchers.media({ available = false })
equal(visible, false)
watchers.media({ available = false, error = "dependency" })
equal(visible, true, "dependency error remains discoverable")
vertical = true
env.update()
equal(#find(view, "content").children, 1, "vertical bar uses compact cover")
equal(find(view, "progress"), nil, "vertical bar does not stretch a progress background")
local model = assert(loadPlugin("lib/view.luau", "t", env))()
equal(model.position({ playing = true, positionMs = 1000, sampledAtMs = 1000, duration = 4 }, 1250, 500), 1250)
equal(model.position({ playing = false, positionMs = 1000, sampledAtMs = 1000 }, 1250, 500), 1000)
equal(model.position({ playing = true, positionMs = 1000, sampledAtMs = 1000 }, 10000, 500), 10000, "interpolation continues between event-driven samples")
equal(model.position({ playing = true, positionMs = 3900, sampledAtMs = 1000, duration = 4 }, 1500, 500), 4000)
for _, mode in ipairs({ "none", "fade", "slide_up", "slide_left" }) do
    local start, finish = model.motion(mode, 0, 240), model.motion(mode, 240, 240)
    equal(start.active, mode ~= "none")
    equal(finish.active, false)
    equal(finish.opacity, 1)
    equal(finish.x + finish.y, 0)
end
vertical = false
defaults.hide_paused = false
defaults.time_offset = 0
defaults.transition = "slide_left"
env.onConfigChanged()
watchers.media({ available = true, playing = false, title = "Test", artist = "Artist", player = "test.instance", positionMs = 1000 })
watchers.media({ available = true, playing = false, title = "Test", artist = "Artist", player = "test.instance", positionMs = 3000 })
equal(find(view, "lyrics").props.height, 20)
equal(find(view, "incoming").props.width, 260, "motion keeps the text viewport fixed")
equal(interval, 33, "fast ticks only while transitioning")
local widthBefore = view.props.width
clockNow = clockNow + 240
env.update()
equal(find(view, "lyrics").props.width, 260)
equal(view.props.width, widthBefore, "animation does not move other bar widgets")
equal(interval, 1000, "paused widget returns to slow ticks")
equal(find(find(view, "incoming"), "current").children[1].props.color, "on_surface_variant", "native paused color")
equal(find(find(view, "incoming"), "current").children[1].props.baseline, "textFixedHeight", "baseline is independent of lyric glyphs")
local textRenderer = assert(loadPlugin("lib/text.luau", "t", env))()
equal(textRenderer.offset(0, 300, 260), 0)
equal(textRenderer.offset(800, 300, 260), 0)
equal(textRenderer.offset(1800, 300, 260), 28)
equal(textRenderer.offset(2300, 300, 260), 40)
equal(textRenderer.offset(4000, 200, 260), 0)
equal(#lrc.parse(string.rep("x", 1048577)), 0, "oversized lyrics are rejected before parsing")
-- Exercise one-time JSON measurement and native Unicode text windows.
local files, requests, removed, callbacks, layouts = {}, {}, {}, {}, {}
local rendererClock = 0
local renderEnv = { noctalia = {
    nowMs = function() return rendererClock end,
    commandExists = function() return true end, mkdirAll = function() return true end,
    getSetting = function() return "sans-serif" end,
    json = { decode = function(raw) return layouts[raw] end },
    readFile = function(path) return files[path] end,
    removeFile = function(path) removed[path] = true; files[path] = nil end,
    runAsync = function(argv, callback)
        requests[#requests + 1] = argv
        callbacks[#callbacks + 1] = callback
        return true
    end,
} }
setmetatable(renderEnv, { __index = _G })
local renderer = assert(loadPlugin("lib/text.luau", "t", renderEnv))().new()
local slots = { { text = "ABCD", size = 13, color = "on_surface", weight = "medium", height = 20 } }
local function config(key) return defaults[key] end
local measuredPair = { first = slots[1].text, second = "", color = "on_surface" }
equal(model.textWidth(measuredPair, config, 20, renderer), nil, "wait for asynchronous width measurement")
equal(renderer:display(slots[1], config, 260), "ABCD", "native fallback while measuring")
equal(#requests, 1, "measurement and display share one process")
equal(requests[1][7], "--text=ABCD", "text stays a single process argument")
equal(requests[1][8]:find("--serialize-to=", 1, true), 1, "Pango produces layout JSON, not an image")
layouts.fixture = { output = { width = 409600,
    ["log-attrs"] = { { ["cursor-position"] = true }, { ["cursor-position"] = true }, { ["cursor-position"] = true }, { ["cursor-position"] = true } },
    lines = { { runs = { { offset = 0, glyphs = {
        { width = 102400, ["log-cluster"] = 0 }, { width = 102400, ["log-cluster"] = 1 },
        { width = 102400, ["log-cluster"] = 2 }, { width = 102400, ["log-cluster"] = 3 },
    } } } } },
} }
files[renderer.directory .. "/layout.json"] = "fixture"
callbacks[1]({ exitCode = 0 })
equal(model.textWidth(measuredPair, config, 20, renderer), 260, "cap overflowing lyrics at the maximum")
defaults.text_width = 500
equal(model.textWidth(measuredPair, config, 20, renderer), 400, "expand completely when the text fits")
equal(#requests, 1, "resizing reuses the measured layout")
defaults.text_width = 260
equal(renderer:display(slots[1], config, 260), "AB", "long line begins with a fitting native text window")
equal(renderer.scrolling, true)
rendererClock = 4500
equal(renderer:display(slots[1], config, 260), "BC", "remove complete leading characters as time advances")
rendererClock = 6000
equal(renderer:display(slots[1], config, 260), "CD", "last window includes the complete ending")
equal(#requests, 1, "advancing text windows never starts a process")
local native = model.textBlock(measuredPair, config, 260, 20, "incoming", 1)
equal(native.kind, "column", "all lyric rendering uses native UI")
equal(find(native, "label").kind, "label")
local unicode = "A你e" .. utf8.char(0x301) .. "👨‍👩‍👧‍👦Z"
local stops = { { byte = 1, x = 0 }, { byte = 2, x = 10 }, { byte = 5, x = 30 },
    { byte = 8, x = 40 }, { byte = #unicode, x = 70 }, { byte = #unicode + 1, x = 80 } }
local unicodeSource = { width = 80, stops = stops }
equal(textRenderer.window(unicodeSource, unicode, 35, 0), "A你", "native window keeps UTF-8 characters intact")
equal(textRenderer.window(unicodeSource, unicode, 45, 2100), "👨‍👩‍👧‍👦Z", "tail window keeps joined emoji intact")
equal(textRenderer.window(unicodeSource, unicode, 80, 2100), unicode, "fitting text remains unchanged")
equal(textRenderer.window({ width = 100, stops = { { byte = 1, x = 0 }, { byte = #unicode + 1, x = 100 } } }, unicode, 60, 2300), unicode,
    "a cluster wider than the viewport is left to native clipping, never cut apart")
renderer:close()
equal(files[renderer.directory .. "/layout.json"], nil, "exit removes measured layout file")
equal(requests[#requests][1], "rmdir")
equal(renderer:source(slots[1], config), nil, "closed measurer cannot start another process")
local renders = 0
local originalRender = env.barWidget.render
env.barWidget.render = function(value) renders = renders + 1; originalRender(value) end
for _ = 1, 20 do env.update() end
equal(renders, 0, "unchanged paused widget does not resubmit UI")

-- Exercise sizing through the widget, including the native background and cover bounds.
local widths = { Current = 80.2, Next = 180, Long = 220, Overflow = 400 }
local sizingRenderer = { source = function(_, slot) return { width = widths[slot.text] } end,
    draw = function() end, close = function() end }
local originalRequire = env.require
env.require = function(path)
    if path == "./lib/text.luau" then return { new = function() return sizingRenderer end } end
    return originalRequire(path)
end
defaults.transition, defaults.second_line = "none", "off"
assert(loadPlugin("widget.luau", "t", env))()
equal(find(view, "lyrics").props.width, 81, "short lyrics shrink to rounded natural width")
equal(view.props.width, 118, "total width includes cover, gap and padding")
equal(find(view, "progress").props.width, 118, "progress fills the widget including horizontal padding")
equal(view.props.paddingH, nil, "progress has no extra left inset")
equal(find(view, "content").props.paddingH, 4, "cover and text retain their content padding")
watchers.lyrics({ status = "synced", lines = lrc.parse("[00:00]Long") })
equal(find(view, "lyrics").props.width, 220, "long lyrics expand before scrolling")
watchers.lyrics({ status = "synced", lines = lrc.parse("[00:00]Overflow") })
equal(find(view, "lyrics").props.width, 260, "overflow uses the full maximum viewport")
defaults.text_width = 500
env.onConfigChanged()
equal(find(view, "lyrics").props.width, 400, "increasing the maximum shows the complete line")
defaults.second_line = "next"
env.onConfigChanged()
watchers.lyrics({ status = "synced", lines = lrc.parse("[00:00]Current\n[00:02]Next") })
equal(find(view, "lyrics").props.width, 180, "dual lines use the longer row")
defaults.second_line = "off"
env.onConfigChanged()
watchers.lyrics({ status = "synced", lines = lrc.parse("[00:00]Pending") })
equal(find(view, "lyrics").props.width, 81, "pending shaping retains the previous width")
widths.Pending = 90
env.onConfigChanged()
equal(find(view, "lyrics").props.width, 90, "ready measurement updates the widget width")
sizingRenderer.display = function(_, slot) return slot.text == "Overflow" and "flow" or slot.text end
defaults.transition = "fade"
env.onConfigChanged()
watchers.lyrics({ status = "synced", source = "splayer", lines = lrc.parse("[00:00]Overflow") })
equal(text("current"), "flow", "SPlayer lyrics pass through the native text window")
watchers.lyrics({ status = "synced", lines = lrc.parse("[00:00]Long") })
equal(find(find(view, "outgoing"), "label").props.text, "flow", "fade out the visible window instead of jumping to the line beginning")
print(string.format("Passed %d checks", checks))
