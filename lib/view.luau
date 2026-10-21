local M = {}

M.position = require("./media.luau").position

function M.motion(mode, elapsed, duration)
    if mode == "none" or elapsed >= duration then return { opacity = 1, x = 0, y = 0, active = false } end
    local t = math.max(0, elapsed / duration)
    local eased = 1 - (1 - t) ^ 3
    return { opacity = eased, x = mode == "slide_left" and 8 * (1 - eased) or 0,
        y = mode == "slide_up" and 4 * (1 - eased) or 0, active = true }
end

function M.textBlock(pair, config, width, height, key, opacity, frame, renderer)
    local family = config("font_family")
    if family == "" then family = nil end
    local dual = config("second_line") ~= "off"
    local gap = dual and math.min(config("line_gap"), height / 4) or 0
    local firstSize = dual and config("dual_font_size") or config("font_size")
    local secondSize = config("secondary_font_size")
    local scale = dual and math.min(1, (height - gap) / (firstSize + secondSize)) or 1
    local firstHeight = dual and math.floor(firstSize * scale) or height
    local secondHeight = dual and math.floor(secondSize * scale) or 0
    local function line(text, size, color, weight, slotHeight, name)
        return ui.row({ key = name, width = width, height = slotHeight, align = "center" }, {
            ui.label({ key = "label", text = text, width = width, maxWidth = width, maxLines = 1,
                fontSize = dual and math.min(size, slotHeight) or size,
                fontFamily = family, fontWeight = weight, baseline = "textFixedHeight",
                textAlign = config("text_align"), color = color })
        })
    end
    local slots = {
        { text = pair.first, size = dual and math.min(firstSize, firstHeight) or firstSize,
            color = pair.color, weight = config("font_weight"), height = firstHeight },
    }
    if dual then slots[2] = { text = pair.second, size = math.min(secondSize, secondHeight),
        color = config("secondary_color"), weight = "normal", height = secondHeight } end
    local image = renderer and renderer:draw(slots, config, width, height, gap, frame, not dual, key)
    if image then return ui.image({ key = key, path = image, width = width, height = height, opacity = opacity, fit = "contain" }) end
    local rows = { line(pair.first, firstSize, pair.color, config("font_weight"), firstHeight, "current") }
    if dual then
        rows[#rows + 1] = line(pair.second, config("secondary_font_size"), config("secondary_color"),
            "normal", secondHeight, "next")
    end
    return ui.column({ key = key, gap = gap, width = width, height = height, opacity = opacity,
        align = "start", justify = "center" }, rows)
end

function M.lyricLayer(pair, previous, frame, config, width, height, renderer)
    -- Keep both layers and their bounds stable; only glyphs inside the SVG move.
    return ui.row({ key = "lyrics", width = width, height = height, gap = -width, align = "center" }, {
        previous and M.textBlock(previous, config, width, height, "outgoing", 1 - frame.opacity,
            nil, renderer) or ui.box({ key = "outgoing", width = width, height = height, fill = "surface/0" }),
        M.textBlock(pair, config, width, height, "incoming", frame.opacity, frame, renderer),
    })
end

return M
