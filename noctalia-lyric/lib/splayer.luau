local M = {}

function M.parse(data, media)
    if type(data) ~= "table" then return {}, false end
    local id = media.trackId:match("/track/(%d+)$")
    if (id and tostring(data.id) ~= id) or (not id and data.name ~= media.title) or data.lyricLoading then
        return {}, true
    end
    local rows = data.lrcData
    if type(rows) ~= "table" or #rows == 0 then rows = data.yrcData end
    if type(rows) ~= "table" or #rows > 10000 then return {}, false end
    local lines = {}
    for _, row in ipairs(rows) do
        if type(row) == "table" and type(row.startTime) == "number" and row.startTime >= 0
                and row.startTime < 1e12 and type(row.words) == "table" and #row.words <= 10000 then
            local words = {}
            for _, word in ipairs(row.words) do
                if type(word) == "table" and type(word.word) == "string" then words[#words + 1] = word.word end
            end
            lines[#lines + 1] = { time = row.startTime, text = table.concat(words), order = #lines + 1 }
        end
    end
    table.sort(lines, function(a, b) return a.time < b.time or a.time == b.time and a.order < b.order end)
    return lines, false
end

return M
