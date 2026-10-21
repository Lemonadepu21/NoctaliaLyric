local M = {}

function M.parse(source)
    if type(source) ~= "string" or #source > 1048576 then return {} end
    local offset = tonumber(source:match("%[offset:([%+%-]?%d+)%]")) or 0
    local lines = {}
    for row in source:gmatch("[^\r\n]+") do
        local stamps, rest = {}, row:gsub("^\239\187\191", "")
        while true do
            local minutes, seconds, tail = rest:match("^%[(%d+):(%d+%.?%d*)%](.*)$")
            if not minutes then break end
            if tonumber(seconds) < 60 then
                stamps[#stamps + 1] = tonumber(minutes) * 60000 + tonumber(seconds) * 1000 - offset
            end
            rest = tail
        end
        -- shortcut: line sync only; add word timing when karaoke highlighting is needed.
        rest = rest:gsub("<%d+:%d+%.?%d*>", ""):match("^%s*(.-)%s*$")
        for _, time in ipairs(stamps) do
            if #lines >= 10000 then return {} end
            lines[#lines + 1] = { time = time, text = rest, order = #lines + 1 }
        end
    end
    table.sort(lines, function(a, b)
        return a.time < b.time or (a.time == b.time and a.order < b.order)
    end)
    local merged = {}
    for _, line in ipairs(lines) do
        local last = merged[#merged]
        if last and last.time == line.time then
            if line.text ~= "" and line.text ~= last.text then
                last.text = last.text == "" and line.text or last.text .. " / " .. line.text
            end
        else
            merged[#merged + 1] = { time = line.time, text = line.text }
        end
    end
    return merged
end

function M.at(lines, positionMs)
    local low, high = 1, #lines
    while low <= high do
        local middle = math.floor((low + high) / 2)
        if lines[middle].time <= positionMs then low = middle + 1 else high = middle - 1 end
    end
    return lines[high] and lines[high].text or "", lines[high + 1] and lines[high + 1].text or ""
end

return M
