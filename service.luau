local mediaLib = require("./lib/media.luau")
local lrc = require("./lib/lrc.luau")
local players, removed, current = {}, {}, { available = false }
local currentKey, lyricText, coverPath, coverUrl, ownedCover
local cache, cacheOrder = {}, {}
local listening, closed, retryAt, retryDelay, scanning = false, false, 0, 1000, false
local lastCalibration, coverSequence, scanAttempts, scanRetryAt = 0, 0, 0, nil
local dataDir = noctalia.pluginDataDir()
local publish, refresh, scan

local function lyrics(media, key, text)
    if key == currentKey and text == lyricText then return end
    currentKey, lyricText = key, text
    local cached = key and cache[key]
    if not cached or cached.text ~= text then
        local lines = #text > 0 and #text <= 1048576 and lrc.parse(text) or {}
        cached = { text = text, value = { lines = lines, status = #lines > 0 and "synced" or "missing", source = #lines > 0 and "mpris" or nil } }
        if key then
            if not cache[key] then cacheOrder[#cacheOrder + 1] = key end
            cache[key] = cached
            if #cacheOrder > 32 then cache[table.remove(cacheOrder, 1)] = nil end
        end
    end
    noctalia.state.set("lyrics", cached.value)
end

publish = function()
    if closed then return end
    local now = noctalia.nowMs()
    local media = mediaLib.select(players, noctalia.getConfig("player"), now)
    local key = media.available and mediaLib.key(media) or nil
    local url = media.available and media.artUrl or ""
    if url ~= coverUrl then
        coverUrl = url
        if ownedCover then noctalia.removeFile(coverPath) end
        coverPath, ownedCover = nil, false
        local path = mediaLib.filePath(url)
        if path and noctalia.fileExists(path) then coverPath = path end
        if not path and dataDir and url:match("^https?://") then
            coverSequence = coverSequence + 1
            local token = coverSequence
            local target = dataDir .. "/cover-" .. now .. "-" .. token .. ".png"
            noctalia.download(url, target, function(ok)
                if closed or token ~= coverSequence or coverUrl ~= url then noctalia.removeFile(target); return end
                if ok then coverPath, ownedCover = target, true; publish() else noctalia.removeFile(target) end
            end)
        end
    end
    local text = media.available and media.embeddedLyrics or ""
    media.embeddedLyrics = nil
    media.cover = coverPath
    if not mediaLib.same(current, media, now) then
        current = media
        noctalia.state.set("media", media)
    end
    lyrics(media, key, text)
end

local function apply(node, properties)
    local now = noctalia.nowMs()
    local before = mediaLib.snapshot(node, now)
    node.positionMs = mediaLib.position(before, now)
    node.sampledAtMs = now
    for _, key in ipairs({ "Metadata", "PlaybackStatus", "Rate" }) do
        if properties[key] ~= nil then node.properties[key] = properties[key] end
    end
    local after = mediaLib.snapshot(node, now)
    if before.trackId ~= after.trackId or before.title ~= after.title and after.trackId == "" then node.positionMs = 0 end
    local position = properties.Position
    if type(position) == "table" and position.type == "x" and type(position.data) == "number" then
        node.positionMs = math.max(0, position.data / 1000)
    end
    node.revision = node.revision + 1
    publish()
end

refresh = function(node, positionOnly)
    if closed then return end
    if node.fetching then if not positionOnly then node.resync = true end; return end
    node.fetching = true
    local revision = node.revision
    local argv = { "busctl", "--user", "--json=short", "--timeout=2" }
    if positionOnly then
        for _, arg in ipairs({ "get-property", node.owner, "/org/mpris/MediaPlayer2", "org.mpris.MediaPlayer2.Player", "Position" }) do argv[#argv + 1] = arg end
    else
        for _, arg in ipairs({ "call", node.owner, "/org/mpris/MediaPlayer2", "org.freedesktop.DBus.Properties", "GetAll", "s", "org.mpris.MediaPlayer2.Player" }) do argv[#argv + 1] = arg end
    end
    local accepted = noctalia.runAsync(argv, function(result)
        node.fetching = false
        if closed or players[node.name] ~= node then return end
        if node.revision ~= revision or node.resync then node.resync = nil; refresh(node); return end
        local data = result.exitCode == 0 and not result.stdoutTruncated and noctalia.json.decode(result.stdout)
        local properties = type(data) == "table" and type(data.data) == "table" and data.data[1]
        if positionOnly and type(data) == "table" and data.type == "x" and type(properties) == "number" then
            node.failures, node.retryAt = 0, nil
            apply(node, { Position = { type = "x", data = properties } })
        elseif not positionOnly and type(properties) == "table" then
            node.failures, node.retryAt = 0, nil
            apply(node, properties)
        else
            node.failures = (node.failures or 0) + 1
            node.retryAt = node.failures < 3 and noctalia.nowMs() + node.failures * 2000 or nil
        end
    end, 2500)
    if not accepted then node.fetching = false; node.failures = (node.failures or 0) + 1; node.retryAt = node.failures < 3 and noctalia.nowMs() + 2000 or nil end
end

local function add(name, owner)
    if type(name) ~= "string" or name:sub(1, #mediaLib.prefix) ~= mediaLib.prefix
            or type(owner) ~= "string" or not owner:match("^:%d+%.%d+$") then return end
    if players[name] and players[name].owner == owner then return end
    local node = { name = name, owner = owner, properties = {}, revision = 0 }
    players[name], removed[name] = node, nil
    refresh(node)
end

scan = function()
    if scanning or closed then return end
    scanning = true
    scanAttempts = scanAttempts + 1
    local accepted = noctalia.runAsync({ "busctl", "--user", "--json=short", "--augment-creds=no", "list" }, function(result)
        scanning = false
        if closed then return end
        local rows = result.exitCode == 0 and not result.stdoutTruncated and noctalia.json.decode(result.stdout)
        if type(rows) ~= "table" then
            scanRetryAt = noctalia.nowMs() + 5000
            return
        end
        scanRetryAt = nil
        retryDelay = 1000
        for _, row in ipairs(rows) do
            if type(row) == "table" and type(row.name) == "string" and not players[row.name] and not removed[row.name] then
                add(row.name, row.connection)
            end
        end
        removed = {}
    end, 2500)
    if not accepted then scanning = false; scanRetryAt = noctalia.nowMs() + 5000 end
end

local function signal(line)
    if closed then return end
    if line == "__NOCTALIA_MPRIS_CLOSED__" then
        listening, retryAt = false, noctalia.nowMs() + retryDelay
        retryDelay = math.min(60000, retryDelay * 2)
        players, removed = {}, {}
        publish()
        return
    end
    if type(line) ~= "string" or #line > 2097152 then return end
    local message = noctalia.json.decode(line)
    if type(message) ~= "table" or message.type ~= "signal" then return end
    local payload = message.payload
    local args = type(payload) == "table" and payload.data
    if type(args) ~= "table" then return end
    if message.sender == "org.freedesktop.DBus" and message.member == "NameOwnerChanged" then
        local name, owner = args[1], args[3]
        if type(name) == "string" and name:sub(1, #mediaLib.prefix) == mediaLib.prefix then
            players[name], removed[name] = nil, scanning and true or nil
            if owner ~= "" then add(name, owner) end
            publish()
        end
        return
    end
    if message.path ~= "/org/mpris/MediaPlayer2" then return end
    for _, node in pairs(players) do
        if node.owner == message.sender then
            if message.interface == "org.mpris.MediaPlayer2.Player" and message.member == "Seeked" and type(args[1]) == "number" then
                apply(node, { Position = { type = "x", data = args[1] } })
            elseif message.interface == "org.freedesktop.DBus.Properties" and message.member == "PropertiesChanged"
                    and args[1] == "org.mpris.MediaPlayer2.Player" and type(args[2]) == "table" then
                local props = args[2]
                if props.Metadata or props.PlaybackStatus or props.Rate or props.Position then apply(node, props) end
                if type(args[3]) == "table" then
                    for _, key in ipairs(args[3]) do
                        if key == "Metadata" or key == "PlaybackStatus" or key == "Position" or key == "Rate" then refresh(node); break end
                    end
                end
            end
        end
    end
end

function update()
    noctalia.setUpdateInterval(1000)
    if closed then return end
    local now = noctalia.nowMs()
    if not listening and now >= retryAt then
        if not noctalia.commandExists("busctl") then
            noctalia.state.set("media", { available = false, error = "dependency" }); retryAt = now + 60000; return
        end
        -- The fixed command has no interpolated settings; the trailing marker reports stream exit.
        listening = noctalia.runStream("busctl --user --json=short "
            .. "--match='type=signal,interface=org.freedesktop.DBus.Properties,path=/org/mpris/MediaPlayer2' "
            .. "--match='type=signal,interface=org.mpris.MediaPlayer2.Player,member=Seeked,path=/org/mpris/MediaPlayer2' "
            .. "--match='type=signal,sender=org.freedesktop.DBus,member=NameOwnerChanged,arg0namespace=org.mpris.MediaPlayer2' monitor; "
            .. "printf '\\n__NOCTALIA_MPRIS_CLOSED__\\n'", signal)
        if listening then scanAttempts = 0; scan(); lastCalibration = now else retryAt = now + retryDelay end
    end
    if scanRetryAt and now >= scanRetryAt and scanAttempts < 3 then scanRetryAt = nil; scan() end
    for _, node in pairs(players) do
        if node.retryAt and now >= node.retryAt then node.retryAt = nil; refresh(node) end
    end
    if current.playing and now - lastCalibration >= math.max(10000, noctalia.getConfig("poll_interval")) then
        lastCalibration = now
        local node = players[current.bus]
        if node then refresh(node, true) end
    end
end

function onConfigChanged() publish() end
function onIpc(event)
    if event == "refresh" then currentKey, lyricText, cache, cacheOrder = nil, nil, {}, {}; for _, node in pairs(players) do refresh(node) end end
end
function onExit()
    closed = true
    if ownedCover then noctalia.removeFile(coverPath) end
end

noctalia.state.set("media", current)
noctalia.state.set("lyrics", { status = "missing", lines = {} })
update()
