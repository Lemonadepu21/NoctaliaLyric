local M = {}

M.position = require("./media.luau").position

function M.motion(mode, elapsed, duration)
    if mode == "none" or elapsed >= duration then return { opacity = 1, x = 0, y = 0, active = false } end
    local t = math.max(0, elapsed / duration)
    local eased = 1 - (1 - t) ^ 3
    return { opacity = eased, x = 0, y = 0, active = true }
end

local function slotsFor(pair, config, height)
    local dual = config("second_line") ~= "off"
    local gap = dual and math.min(config("line_gap"), height / 4) or 0
    local firstSize = dual and config("dual_font_size") or config("font_size")
    local secondSize = config("secondary_font_size")
    local scale = dual and math.min(1, (height - gap) / (firstSize + secondSize)) or 1
    local firstHeight = dual and math.floor(firstSize * scale) or height
    local secondHeight = dual and math.floor(secondSize * scale) or 0
    local slots = {
        { text = pair.first, size = dual and math.min(firstSize, firstHeight) or firstSize,
            color = pair.color, weight = config("font_weight"), height = firstHeight },
    }
    if dual then slots[2] = { text = pair.second, size = math.min(secondSize, secondHeight),
        color = config("secondary_color"), weight = "normal", height = secondHeight } end
    return slots, gap, dual
end

function M.textWidth(pair, config, height, renderer)
    if not renderer or renderer.disabled then return config("text_width") end
    local slots = slotsFor(pair, config, height)
    local width = 1
    for _, slot in ipairs(slots) do
        local source = renderer:source(slot, config)
        if not source or not source.width then return nil end
        width = math.max(width, math.ceil(source.width))
    end
    return math.min(config("text_width"), width)
end

function M.displayPair(pair, config, width, height, renderer)
    if config("second_line") ~= "off" or not renderer.display then return pair end
    local slots = slotsFor(pair, config, height)
    return { first = renderer:display(slots[1], config, width), second = pair.second, color = pair.color }
end

function M.textBlock(pair, config, width, height, key, opacity)
    local family = config("font_family")
    if family == "" then family = nil end
    local slots, gap, dual = slotsFor(pair, config, height)
    local function line(slot, name)
        local text, size, color, weight, slotHeight = slot.text, slot.size, slot.color, slot.weight, slot.height
        return ui.row({ key = name, width = width, height = slotHeight, align = "center" }, {
            ui.label({ key = "label", text = text, width = width, maxWidth = width, maxLines = 1,
                fontSize = dual and math.min(size, slotHeight) or size,
                fontFamily = family, fontWeight = weight, baseline = "textFixedHeight",
                textAlign = config("text_align"), color = color })
        })
    end
    local rows = { line(slots[1], "current") }
    if dual then rows[#rows + 1] = line(slots[2], "next") end
    return ui.column({ key = key, gap = gap, width = width, height = height, opacity = opacity,
        align = "start", justify = "center" }, rows)
end

function M.lyricLayer(pair, previous, frame, config, width, height)
    return ui.row({ key = "lyrics", width = width, height = height, gap = -width, align = "center" }, {
        previous and M.textBlock(previous, config, width, height, "outgoing", 1 - frame.opacity)
            or ui.box({ key = "outgoing", width = width, height = height, fill = "surface/0" }),
        M.textBlock(pair, config, width, height, "incoming", frame.opacity),
    })
end

return M
