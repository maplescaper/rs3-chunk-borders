-- Cache for the shapes being drawn.
--
-- Helps with keeping, and removing shapes from the draw cycle.

local Cache = {}
Cache.__index = Cache

---An empty cache.
---@return table cache
function Cache.new()
    return setmetatable({ entries = {} }, Cache)
end

---The entry stored under this key, if any.
---@param key string
---@return table|nil entry
function Cache:get(key)
    return self.entries[key]
end

---Marks an entry as used this frame so we don't evict it.
---@param entry table
---@param frame integer
function Cache:keep(entry, frame)
    entry.lastSeen = frame
end

---Stores an entry under this key and keeps it this frame.
---@param key string
---@param entry table
---@param frame integer
---@return table|nil previous the entry this one replaced
function Cache:put(key, entry, frame)
    local previous = self.entries[key]
    self.entries[key] = entry
    self:keep(entry, frame)
    return previous
end

---Removes every entry not kept on this frame and returns them.
---@param frame integer the current frame
---@return table[] entries
function Cache:evict(frame)
    local evicted = {}
    for key, entry in pairs(self.entries) do
        if entry.lastSeen ~= frame then
            evicted[#evicted + 1] = entry
            self.entries[key] = nil
        end
    end
    return evicted
end

---Clears the full cache and returns whatever was being held.
---@return table[] entries
function Cache:clear()
    local all = {}
    for _, entry in pairs(self.entries) do all[#all + 1] = entry end
    self.entries = {}
    return all
end

---How many entries are live.
---@return integer
function Cache:count()
    local count = 0
    for _ in pairs(self.entries) do count = count + 1 end
    return count
end

return Cache
