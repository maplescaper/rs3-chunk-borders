-- Helper for ensuring the PrettyUI dependency exists.

local Library = {}

local MESSAGE = "Chunk Man requires the PrettyUI dependency to be enabled first"

---@return table prettyui
function Library.get()
    return assert(prettyui, MESSAGE)
end

---@return boolean
function Library.available()
    return prettyui ~= nil
end

return Library
