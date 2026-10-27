-- Handles the current state of locked/unlocked chunks along with helpers.
--
-- The unlocked list is stored as in-game chunk IDs. Anything the player types
-- is assumed to be Chunk Picker IDs and converted to in-game IDs. We also
-- always show these IDs as Chunk Picker IDs to the user.

local Chunk = require("src/chunk")
local Settings = require("src/settings")

local State = {}

State.unlockedIDs = {}
State.unlockedSet = {}

---Gets the list of unlocked chunks and sets them to the state.
function State.rebuild()
    local ids = Chunk.parseList(Settings.get("unlockedChunkIds"))
    local set = {}
    for _, id in ipairs(ids) do
        set[Chunk.atID(id)] = true
    end
    State.unlockedIDs = ids
    State.unlockedSet = set
end

---Used to determine if a chunk is unlocked/locked.
---@param chunk table
---@return boolean
function State.isUnlockedChunk(chunk)
    return State.unlockedSet[chunk] == true
end

---If an ID is an unlocked chunk.
---@param id integer
---@return boolean
function State.isUnlockedChunkID(id)
    return State.isUnlockedChunk(Chunk.atID(id))
end

---Count of all the unlocked chunks.
---@return integer
function State.count() return #State.unlockedIDs end

---Sets the state of the chunk (either locked or unlocked).
---@param chunk table
---@param unlocked boolean
---@return boolean changed
function State.setUnlocked(chunk, unlocked)
    -- Don't do anything if the chunk is already in the expected state
    if State.isUnlockedChunk(chunk) == unlocked then return false end

    if unlocked then
        State.appendList({ chunk.id })
    else
        -- Rebuild the list without the locked chunk (keeping it sorted)
        local ids = {}
        for _, existing in ipairs(State.unlockedIDs) do
            if existing ~= chunk.id then ids[#ids + 1] = existing end
        end
        Settings.set("unlockedChunkIds", Chunk.formatList(ids))
    end

    return true
end

---Toggles a locked/unlocked chunk.
---@param chunk table
---@return boolean nowUnlocked
function State.toggle(chunk)
    local target = not State.isUnlockedChunk(chunk)
    State.setUnlocked(chunk, target)
    return target
end

---Used for appending to the chunk ID list instead of overwriting it.
---@param ids integer[]
---@return integer added how many were not already unlocked
function State.appendList(ids)
    local known, order = {}, {}
    for index, id in ipairs(State.unlockedIDs) do
        known[id] = true
        order[index] = id
    end

    local added = 0
    for _, id in ipairs(ids) do
        id = math.floor(id)
        if id >= 0 and not known[id] then
            known[id] = true
            order[#order + 1] = id
            added = added + 1
        end
    end

    if added > 0 then
        table.sort(order)
        Settings.set("unlockedChunkIds", Chunk.formatList(order))
    end
    return added
end

---Replaces the unlocked list with the one input. Assumes the input is in
---Chunk Picker IDs.
---@param text string
function State.commitList(text)
    Settings.set("unlockedChunkIds", Chunk.formatList(Chunk.parsePickerList(text)))
end

---Adds a list of chunks, in Chunk Picker IDs, to what is already unlocked.
---@param text string
---@return integer how many were not already unlocked
function State.pasteList(text)
    return State.appendList(Chunk.parsePickerList(text))
end

---The unlocked list as Chunk Picker IDs for displaying.
---@return string
function State.pickerList()
    return Chunk.formatPickerList(State.unlockedIDs)
end

---Initialize the State.
function State.init()
    Settings.subscribe("unlockedChunkIds", function() State.rebuild() end)
    State.rebuild()
end

return State
