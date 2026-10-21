local lrc = require("./lib/lrc.luau")
local view = require("./lib/view.luau")
local renderSignature, settings = nil, {}
local renderer = require("./lib/text.luau").new(function() renderSignature = nil; update() end)
local function config(key)
    if settings[key] == nil then settings[key] = noctalia.getConfig(key) end
    return settings[key]
end
local media = noctalia.state.get("media") or { available = false }
local function lyricState(value)
    return value and (not value.source or value.source == "mpris") and value or { lines = {}, status = "missing" }
end
local lyrics = lyricState(noctalia.state.get("lyrics"))
local shown, previous, track, changedAt, textWidth

function update()
    local tr = noctalia.tr
    local now = noctalia.nowMs()
    local vertical = barWidget.isVertical()
    local visible = media.error ~= nil or (media.available and not (config("hide_paused") and not media.playing))
        or (not media.available and not config("hide_idle"))
    barWidget.setVisible(visible)
    if not visible then
        shown, previous, renderSignature = nil, nil, nil
        renderer.scrolling = false
        noctalia.setUpdateInterval(1000)
        return
    end
    local position = view.position(media, now)
    local first, second = "", ""
    if media.available then
        first, second = lrc.at(lyrics.lines or {}, position + config("time_offset"))
        if first == "" then first = lyrics.status == "instrumental" and tr("state.instrumental") or media.title end
        if config("second_line") == "metadata" or (second == "" and config("second_line") == "next") then second = media.artist end
    else first = tr("state." .. (media.error or "idle")) end
    if config("second_line") == "off" then second = "" end
    local color = media.available and not media.playing and config("dim_paused")
        and config("secondary_color") or config("text_color")
    local pair = { first = first, second = second, color = color }
    local nextTrack = (media.player or "") .. "\31" .. (media.trackId or media.title or "")
    if not shown or track ~= nextTrack then
        previous, changedAt = nil, nil
    elseif shown.first ~= first or shown.second ~= second then
        previous, changedAt = shown, now
    end
    shown, track = pair, nextTrack
    local frame = view.motion(config("transition"), changedAt and now - changedAt or config("transition_duration"),
        config("transition_duration"))
    if not frame.active then previous = nil end

    local progress = config("show_progress") and media.available and (media.duration or 0) > 0 and position / (media.duration * 1000) or 0
    local signature = { first, second, color, media.cover or "", media.playing or false, media.available or false,
        progress, frame.opacity, frame.x, frame.y, vertical or false, media.title or "", media.artist or "",
        lyrics.source or lyrics.status or "", noctalia.getColor(color) or "", noctalia.getColor(config("secondary_color")) or "",
        noctalia.getSetting("shell.font_family") or "" }
    local unchanged = renderSignature ~= nil and #signature == #renderSignature
    if unchanged then for i, value in ipairs(signature) do if value ~= renderSignature[i] then unchanged = false; break end end end
    if unchanged and not renderer.scrolling then
        noctalia.setUpdateInterval(frame.active and 33 or media.available and media.playing and 200 or 1000)
        return
    end
    renderSignature = signature
    renderer.scrolling = false
    local height = config("content_height")
    local innerHeight = math.max(12, height - config("padding_v") * 2)
    local size = math.min(config("cover_size"), innerHeight)
    local showCover = config("show_cover") or vertical
    local coverWidth = showCover and size or 0
    local gap = showCover and not vertical and config("cover_gap") or 0
    if not vertical then
        textWidth = math.min(config("text_width"), view.textWidth(pair, config, innerHeight, renderer)
            or textWidth or config("text_width"))
    end
    local width = vertical and size or textWidth + coverWidth + gap
    local children = {}
    if showCover then
        if media.cover then
            children[#children + 1] = ui.image({ key = "cover", path = media.cover, width = size, height = size,
                radius = math.min(config("cover_radius"), size / 2), fit = "cover" })
        else
            children[#children + 1] = ui.column({ key = "placeholder", width = size, height = size,
                align = "center", justify = "center", fill = "surface_variant",
                radius = math.min(config("cover_radius"), size / 2) }, {
                    ui.glyph({ name = media.available and not media.playing and "player-pause" or "music",
                        size = math.max(10, size * 0.55), color = config("secondary_color") }) })
        end
    end
    if not vertical then
        children[#children + 1] = view.lyricLayer(pair, previous, frame, config, textWidth, innerHeight, renderer)
    end
    local container = vertical and ui.column or ui.row
    local content = container({ key = "content", gap = gap, width = width, height = innerHeight,
        align = "center", opacity = config("text_opacity") }, children)
    local layers = { content }
    if config("show_progress") and not vertical and media.available and (media.duration or 0) > 0 then
        table.insert(layers, 1, ui.progress({ key = "progress", width = width, height = innerHeight,
            progress = math.max(0, math.min(1, position / (media.duration * 1000))),
            fill = config("progress_color"), opacity = config("progress_opacity"),
            track = "primary/0", radius = config("background_radius") }))
    end
    barWidget.render(ui.row({ key = "root", gap = -width, width = width + config("padding_h") * 2,
        height = height, align = "center", paddingH = config("padding_h"), paddingV = config("padding_v"),
        radius = config("background_radius"), fill = config("show_background") and config("background_color") or "surface/0" }, layers))
    local tip = media.available and (media.title .. "\n" .. media.artist .. "\n" .. first .. "\n" .. second
        .. "\n" .. tr("state." .. (lyrics.source or lyrics.status))) or first
    barWidget.setTooltip(tip .. "\n" .. tr("hint"))
    noctalia.setUpdateInterval((frame.active or renderer.scrolling) and 33 or media.available and media.playing and 200 or 1000)
end

function onExit() renderer:close() end

function onConfigChanged()
    settings, renderSignature = {}, nil
    update()
end

noctalia.state.watch("media", function(value) media = value or { available = false }; update() end)
noctalia.state.watch("lyrics", function(value) lyrics = lyricState(value); update() end)
update()
