local M = {}
M.prefix = "org.mpris.MediaPlayer2."

local function value(properties, key, kind)
    local entry = type(properties) == "table" and properties[key]
    if type(entry) ~= "table" or entry.type ~= kind then return nil end
    local data = entry.data
    if (kind == "s" or kind == "o") and type(data) == "string" then return data end
    if (kind == "x" or kind == "d") and type(data) == "number" and data == data and math.abs(data) < 1e15 then return data end
    if (kind == "a{sv}" or kind == "as") and type(data) == "table" then return data end
end

function M.position(media, now)
    local elapsed = media.playing and math.max(0, now - (media.sampledAtMs or now)) * (media.rate or 1) or 0
    local position = math.max(0, (media.positionMs or 0) + elapsed)
    if (media.duration or 0) > 0 then position = math.min(position, media.duration * 1000) end
    return position
end

function M.snapshot(node, now)
    local props = node.properties
    local metadata = value(props, "Metadata", "a{sv}") or {}
    local status = value(props, "PlaybackStatus", "s")
    local title = value(metadata, "xesam:title", "s") or ""
    if title == "" or (status ~= "Playing" and status ~= "Paused") then return { available = false } end
    local artists = value(metadata, "xesam:artist", "as") or {}
    local artist = {}
    for _, name in ipairs(artists) do if type(name) == "string" then artist[#artist + 1] = name end end
    local rate = value(props, "Rate", "d") or 1
    if type(rate) ~= "number" or rate ~= rate or rate <= 0 or rate > 100 then rate = 1 end
    return { available = true, bus = node.name, player = node.name:sub(#M.prefix + 1), playing = status == "Playing",
        title = title, artist = table.concat(artist, ", "), album = value(metadata, "xesam:album", "s") or "",
        artUrl = value(metadata, "mpris:artUrl", "s") or "", url = value(metadata, "xesam:url", "s") or "",
        trackId = value(metadata, "mpris:trackid", "o") or "", embeddedLyrics = value(metadata, "xesam:asText", "s") or "",
        duration = math.max(0, tonumber(value(metadata, "mpris:length", "x")) or 0) / 1000000,
        rate = rate, positionMs = node.positionMs or 0, sampledAtMs = node.sampledAtMs or now }
end

function M.matches(name, filter)
    local short = name:sub(#M.prefix + 1)
    return filter == "" or short == filter or short:sub(1, #filter + 1) == filter .. "."
end

function M.select(players, filter, now)
    local selected
    for name, node in pairs(players) do
        if M.matches(name, filter) then
            local media = M.snapshot(node, now)
            if media.available and (not selected or media.playing and not selected.playing
                    or media.playing == selected.playing and name < selected.bus) then selected = media end
        end
    end
    return selected or { available = false }
end

function M.key(media)
    return media.bus .. "\31" .. (media.trackId ~= "" and media.trackId or media.url .. "\31" .. media.title .. "\31" .. media.artist)
end

function M.same(a, b, now)
    for key, v in pairs(a) do
        if key ~= "positionMs" and key ~= "sampledAtMs" and v ~= b[key] then return false end
    end
    for key, v in pairs(b) do
        if key ~= "positionMs" and key ~= "sampledAtMs" and v ~= a[key] then return false end
    end
    return math.abs(M.position(a, now) - M.position(b, now)) < 25
end

function M.filePath(url)
    local path = url:match("^file://localhost(/.*)$") or url:match("^file://(/.*)$")
    if path then path = noctalia.string.urlDecode(path)
    elseif url:sub(1, 1) == "/" then path = url end
    if path and not path:find("%z") then return path end
end

return M
