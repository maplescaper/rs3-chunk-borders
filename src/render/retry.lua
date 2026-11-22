-- Helper storage for holding what shapes should be retried and when.

local Retry = {}
Retry.__index = Retry

---Build a new retry storage.
---@return table retry
function Retry.new()
    return setmetatable({
        -- Frame on which each key may be tried again
        dueAt = {},
    }, Retry)
end

---Records that this key should be tried on or after the given frame.
---@param key string
---@param frame integer
function Retry:defer(key, frame)
    self.dueAt[key] = frame
end

---If we're still waiting to retry at the given frame.
---@param key string
---@param frame integer the current frame
---@return boolean
function Retry:waiting(key, frame)
    local at = self.dueAt[key]
    return at ~= nil and frame < at
end

---Get rid of a key for retrying.
---@param key string
function Retry:forget(key)
    self.dueAt[key] = nil
end

---Clears retries that have expired.
---@param frame integer the current frame
function Retry:expire(frame)
    for key, at in pairs(self.dueAt) do
        if at <= frame then self:forget(key) end
    end
end

return Retry
