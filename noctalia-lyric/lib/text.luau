-- Pango measures once per line; the UI always renders native labels.
local M = {}
local weights = { normal = "Normal", medium = "Medium", semibold = "Semi-Bold", bold = "Bold" }

function M.offset(elapsed, width, viewport)
    if width <= viewport then return 0 end
    local distance = width - viewport
    local phase = elapsed % (1600 + distance / 0.028)
    return math.min(distance, math.max(0, (phase - 800) * 0.028))
end

function M.window(source, text, width, elapsed)
    if source.width <= width or not source.stops then return text end
    local distance = source.width - width
    local offset = M.offset(elapsed, source.width, width)
    local first, last = 1, #source.stops - 1
    for i, stop in ipairs(source.stops) do
        if i == #source.stops then break end
        if stop.x <= offset or offset == distance and source.stops[first].x < distance then first = i end
        if stop.x >= offset then break end
    end
    local start = source.stops[first]
    for i = first + 1, #source.stops do
        if source.stops[i].x - start.x > width then last = math.max(first, i - 2); break end
    end
    return text:sub(start.byte, source.stops[last + 1] and source.stops[last + 1].byte - 1 or #text)
end

function M.new(onReady)
    local self = { cache = {}, order = {}, scrolling = false }
    local token = tostring({}):gsub("[^%w]", "") .. "-" .. tostring(noctalia.nowMs())
    self.directory = "/tmp/noctalia-lyric-" .. token
    if not noctalia.commandExists("pango-view") or not noctalia.mkdirAll(self.directory) then self.disabled = true end

    function self:source(slot, config)
        if self.disabled or self.closed then return nil end
        local family = config("font_family")
        if family == "" then family = noctalia.getSetting("shell.font_family") or "sans-serif" end
        local font = family .. " " .. weights[slot.weight] .. " " .. slot.size
        local key = slot.text .. "\31" .. font
        if self.cache[key] then return self.cache[key] end
        if self.busy then return nil end
        local cached = {}
        self.cache[key] = cached
        self.order[#self.order + 1] = key
        if #self.order > 12 then self.cache[table.remove(self.order, 1)] = nil end
        self.busy = true
        local path = self.directory .. "/layout.json"
        local accepted = noctalia.runAsync({ "pango-view", "--no-display", "--pixels", "--margin=0", "--single-par",
            "--font=" .. font, "--text=" .. slot.text, "--serialize-to=" .. path }, function(result)
            self.busy = false
            if self.closed then
                noctalia.removeFile(path)
                noctalia.runAsync({ "rmdir", self.directory })
                return
            end
            if result.exitCode ~= 0 or result.timedOut or result.stdoutTruncated then return end
            local raw = noctalia.readFile(path)
            local layout = raw and noctalia.json.decode(raw)
            local output = type(layout) == "table" and layout.output
            if type(output) ~= "table" or type(output.width) ~= "number" or not (output.width >= 0 and output.width < 1e12) then return end
            local advances = {}
            for _, line in ipairs(output.lines or {}) do
                for _, run in ipairs(line.runs or {}) do
                    for _, glyph in ipairs(run.glyphs or {}) do
                        local byte = run.offset + glyph["log-cluster"]
                        advances[byte] = (advances[byte] or 0) + glyph.width / 1024
                    end
                end
            end
            local stops, x, index = {}, 0, 1
            local ok = pcall(function()
                for byte in utf8.codes(slot.text) do
                    local attr = output["log-attrs"] and output["log-attrs"][index]
                    if byte == 1 or attr and attr["cursor-position"] then stops[#stops + 1] = { byte = byte, x = x } end
                    x, index = x + (advances[byte - 1] or 0), index + 1
                end
            end)
            stops[#stops + 1] = { byte = #slot.text + 1, x = output.width / 1024 }
            cached.width, cached.stops = output.width / 1024, ok and stops or nil
            if onReady then onReady() end
        end, 2000)
        if not accepted then self.busy = false end
        return cached
    end

    function self:display(slot, config, width)
        if self.current ~= slot.text then self.current, self.started = slot.text, noctalia.nowMs() end
        local source = self:source(slot, config)
        if not source or not source.width then return slot.text end
        if source.width > width then self.scrolling = true end
        return M.window(source, slot.text, width, noctalia.nowMs() - self.started)
    end

    function self:close()
        self.closed = true
        noctalia.removeFile(self.directory .. "/layout.json")
        noctalia.runAsync({ "rmdir", self.directory })
    end
    return self
end
return M
