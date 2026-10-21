-- Pango shapes once per line; a clipped SVG moves glyphs without moving native bar layers.
local M = {}
local weights = { normal = "Normal", medium = "Medium", semibold = "Semi-Bold", bold = "Bold" }

function M.offset(elapsed, width, viewport)
    if width <= viewport then return 0 end
    local distance = width - viewport
    local phase = elapsed % (1600 + distance / 0.028)
    return math.min(distance, math.max(0, (phase - 800) * 0.028))
end

function M.new(onReady)
    local self = { cache = {}, order = {}, metrics = {}, files = {}, sequence = 0, scrolling = false }
    local token = tostring({}):gsub("[^%w]", "") .. "-" .. tostring(noctalia.nowMs())
    self.directory = "/tmp/noctalia-lyric-" .. token
    if not noctalia.commandExists("pango-view") or not noctalia.mkdirAll(self.directory) then self.disabled = true end

    function self:source(slot, config)
        local family = config("font_family")
        if family == "" then family = noctalia.getSetting("shell.font_family") or "sans-serif" end
        local color = noctalia.getColor(slot.color)
        if not color then return nil end
        local font = family .. " " .. weights[slot.weight] .. " " .. slot.size
        local key = slot.text .. "\31" .. font .. "\31" .. color
        local cached = self.cache[key]
        if cached then return cached end
        if self.busy or self.closed then return nil end
        cached = {}
        self.cache[key] = cached
        self.order[#self.order + 1] = key
        if #self.order > 12 then self.cache[table.remove(self.order, 1)] = nil end
        self.busy = true
        local path = self.directory .. "/source.svg"
        local accepted = noctalia.runAsync({ "pango-view", "--no-display", "--pixels", "--margin=0",
            "--single-par", "--font=" .. font, "--foreground=" .. color, "--background=#00000000",
            "--text=" .. slot.text, "--output=" .. path }, function(result)
            self.busy = false
            if self.closed then
                noctalia.removeFile(path)
                noctalia.runAsync({ "rmdir", self.directory })
                return
            end
            if result.exitCode ~= 0 or result.timedOut or result.stdoutTruncated then return end
            local svg = noctalia.readFile(path)
            if not svg then return end
            local w, h = svg:match('viewBox="0 0 ([%d.]+) ([%d.]+)"')
            local body = svg:match('<svg[^>]*>(.*)</svg>')
            if not w or not body then return end
            cached.width, cached.height = tonumber(w), tonumber(h)
            cached.body = body
            cached.rows = {}
            cached.baseline = tonumber(body:match('<use[^>]- y="([%d.]+)"')) or cached.height * 0.8
            self.metrics[font] = self.metrics[font] or cached.baseline - cached.height / 2
            cached.anchor = self.metrics[font]
            if onReady then onReady() end
        end, 2000)
        if not accepted then self.busy = false end
        return cached
    end

    function self:draw(slots, config, width, height, gap, frame, single, layer)
        if self.disabled or self.closed then return nil end
        if layer == "incoming" and self.current ~= slots[1].text then
            self.current, self.scrollStarted = slots[1].text, noctalia.nowMs()
        end
        local sources = {}
        for i, slot in ipairs(slots) do
            sources[i] = self:source(slot, config)
            if not sources[i] or not sources[i].body then
                return self.last and self.last[layer] and self.last[layer].path or nil
            end
        end
        local offsets, signature = {}, { tostring(width), tostring(height), tostring(gap), config("text_align") }
        for i, slot in ipairs(slots) do
            local source = sources[i]
            local x = 0
            if single and source.width > width and layer == "incoming" then
                x = -M.offset(noctalia.nowMs() - self.scrollStarted, source.width, width)
                self.scrolling = true
            elseif source.width < width then
                x = config("text_align") == "center" and (width - source.width) / 2
                    or config("text_align") == "end" and width - source.width or 0
            end
            offsets[i] = x
            for _, value in ipairs({ tostring(source), slot.height, frame and frame.x or 0, frame and frame.y or 0, string.format("%.2f", x) }) do
                signature[#signature + 1] = tostring(value)
            end
        end
        local input = table.concat(signature, "\31")
        self.last = self.last or {}
        if self.last[layer] and self.last[layer].input == input then return self.last[layer].path end
        local y = (height - slots[1].height - (slots[2] and slots[2].height + gap or 0)) / 2
        local parts = { string.format('<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="%s" height="%s" viewBox="0 0 %s %s">', width, height, width, height),
            string.format('<defs><clipPath id="viewport"><rect width="%s" height="%s"/></clipPath></defs><g clip-path="url(#viewport)">', width, height) }
        for i, slot in ipairs(slots) do
            local source = sources[i]
            local x = offsets[i]
            source.rows[i] = source.rows[i] or source.body:gsub('glyph', 'row' .. i .. 'glyph')
            -- Separate nested SVG documents keep Pango's glyph IDs independent between rows.
            parts[#parts + 1] = string.format('<svg x="%.2f" y="%.2f" width="%s" height="%s" overflow="visible">%s</svg>',
                x + (frame and frame.x or 0), y + slot.height / 2 + source.anchor - source.baseline + (frame and frame.y or 0),
                source.width, source.height, source.rows[i])
            y = y + slot.height + gap
        end
        parts[#parts + 1] = '</g></svg>'
        local svg = table.concat(parts)
        self.sequence = self.sequence + 1
        local path = self.directory .. "/frame-" .. self.sequence .. ".svg"
        if not noctalia.writeFile(path, svg) then return nil end
        self.files[#self.files + 1] = path
        if #self.files > 16 then
            local old = table.remove(self.files, 1)
            local other = self.last[layer == "incoming" and "outgoing" or "incoming"]
            if other and old == other.path then
                self.files[#self.files + 1] = old
                old = table.remove(self.files, 1)
            end
            noctalia.removeFile(old)
        end
        self.last[layer] = { input = input, path = path }
        return path
    end

    function self:close()
        self.closed = true
        for _, path in ipairs(self.files) do noctalia.removeFile(path) end
        noctalia.removeFile(self.directory .. "/source.svg")
        -- removeFile accepts files only; remove the now-empty private temporary directory.
        noctalia.runAsync({ "rmdir", self.directory })
    end
    return self
end
return M
