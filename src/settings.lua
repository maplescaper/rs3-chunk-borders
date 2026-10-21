-- Holds all the settings used by the plugin as well as helpers for
-- saving, validating, listening to changes, etc..

local Settings = {}

local SAVE_KEY = "chunkman-settings-v1"

-- Version is not needed at the moment but will be useful if there needs to
---be a setting migration of any sort.
local SETTINGS_VERSION = 1
local VERSION_FIELD = "settingsVersion"

local values, definitions = {}, {}
local listeners = {}

Settings.groups = {
    {
        id = "regions",
        name = "Regions",
        entries = {
            { key = "overworldDetection", name = "Overworld only", type = "bool", default = true },
            { key = "unlockedChunkIds", name = "Unlocked chunks", type = "text", default = "",
              placeholder = "16179,16180,16434", maxLength = 1000000 },
            { key = "pasteChunkIds", name = "Add chunks", type = "text", default = "",
              placeholder = "16179,16180,16434,16435,16436", maxLength = 1000000 },
            { key = "showPopups", name = "Unlock popups", type = "bool", default = true },
        },
    },
    {
        id = "looks",
        name = "Environment Looks",
        entries = {
            { key = "greyLocked", name = "Chunk Shader", type = "bool", default = true },
            { key = "lockedColour", name = "Shader colour", type = "colour", default = 0x000000BF },
            { key = "lockedVolumeOpacity", name = "Shader opacity", type = "float", default = 0.85, min = 0.0, max = 1.0 },
            { key = "fillCameraMargin", name = "Camera margin", type = "int", default = 3, min = 0 },
            { key = "lockedVolume", name = "Tall shader volume", type = "bool", default = true },
            { key = "lockedVolumeTiles", name = "Volume height", type = "int", default = 150, min = 0, max = 250 },
            { key = "lockedVolumeSkipBorder", name = "Volume gap", type = "bool", default = false },
            { key = "showRegionLines", name = "Border lines", type = "bool", default = true },
            { key = "lineThickness", name = "Border width", type = "float", default = 3.0, min = 0.0, step = 0.5 },
            { key = "regionColour", name = "Border colour", type = "colour", default = 0x8A8A8AFF },
            { key = "lineOpacity", name = "Border opacity", type = "float", default = 1.0, min = 0.0, max = 1.0 },
            { key = "regionRadius", name = "Chunk radius", type = "int", default = 2, min = 0, max = 4 },
        },
    },
    {
        id = "advanced",
        name = "Advanced",
        entries = {
            -- How many times the ground is sampled along each border line and
            -- across each shader box. Higher values follow the terrain closer but costs
            -- more per rebuild which can affect performance. Lower sampling rates can
            -- cause flickering/clipping issues with the ground also.
            { key = "lineSamples", name = "Border samples", type = "int", default = 64, min = 1, max = 64 },
            { key = "boxSamples", name = "Shader samples", type = "int", default = 8, min = 1, max = 24 },
        },
    },
}

for _, group in ipairs(Settings.groups) do
    for _, entry in ipairs(group.entries) do
        definitions[entry.key] = entry
        values[entry.key] = entry.default
    end
end

---Verifies that a new setting is valid.
---@param entry table
---@param value any
---@return boolean
local function valid(entry, value)
    local kind = entry.type
    if kind == "bool" then
        return type(value) == "boolean"
    elseif kind == "text" then
        return type(value) == "string"
    elseif kind == "int" or kind == "float" or kind == "colour" then
        if type(value) ~= "number" then return false end
        if kind ~= "float" and math.floor(value) ~= value then return false end
        if entry.min and value < entry.min then return false end
        if entry.max and value > entry.max then return false end
        return true
    end
    return false
end

---Calls the listener for the given changed key.
---@param key string
local function notify(key)
    local listener = listeners[key]
    if listener then listener(values[key], key) end
    local wildcard = listeners["*"]
    if wildcard then wildcard(values[key], key) end
end

---Saves the settings in the persistent DB.
local function save()
    local saved = { [VERSION_FIELD] = SETTINGS_VERSION }
    for key, entry in pairs(definitions) do
        if entry.type == "colour" then
            saved[key] = string.format("%08X", values[key])
        else
            saved[key] = values[key]
        end
    end
    PersistentDB:SetStructuredData(SAVE_KEY, saved)
end

---Flattens the JSON array from the DB into a table format.
---@param stored table
---@return table
local function flatten(stored)
    local flat, records = {}, false
    for index, record in pairs(stored) do
        if type(index) == "number" and type(record) == "table" and record.key ~= nil then
            flat[tostring(record.key)] = record.value
            records = true
        end
    end
    if records then return flat end
    return stored
end

---Loads the data from the DB and sets up the values found in it.
function Settings.load()
    local raw = PersistentDB:GetStructuredData(SAVE_KEY)
    if type(raw) ~= "table" then return end
    local stored = flatten(raw)

    for key, entry in pairs(definitions) do
        local raw = stored[key]
        if entry.type == "colour" and type(raw) == "string" then
            raw = tonumber(raw, 16)
        end
        if raw ~= nil and valid(entry, raw) then values[key] = raw end
    end
end

---Returns a key's value.
---@param key string
---@return any
function Settings.get(key) return values[key] end

---Sets a new value to a key and saves it.
---@param key string
---@param value any
---@return boolean accepted
function Settings.set(key, value)
    local entry = definitions[key]
    if not entry or not valid(entry, value) then return false end
    if values[key] == value then return true end
    values[key] = value
    save()
    notify(key)
    return true
end

---Resets all settings to default then runs the listeners for them.
---@param groupID string|nil
function Settings.reset(groupID)
    local touched = {}
    for _, group in ipairs(Settings.groups) do
        if not groupID or group.id == groupID then
            for _, entry in ipairs(group.entries) do
                if values[entry.key] ~= entry.default then
                    values[entry.key] = entry.default
                    touched[#touched + 1] = entry.key
                end
            end
        end
    end
    save()
    for _, key in ipairs(touched) do notify(key) end
end

---One listener per key, and passing nil clears it. Used for things like
---calling the appendList when chunk IDs are added to the settings.
---@param key string
---@param callback function|nil
function Settings.subscribe(key, callback) listeners[key] = callback end

---@param key string
---@return table|nil
function Settings.definition(key) return definitions[key] end

---Used for reseting settings in tests.
function Settings.resetForTests()
    for key, entry in pairs(definitions) do values[key] = entry.default end
    listeners = {}
end

return Settings
