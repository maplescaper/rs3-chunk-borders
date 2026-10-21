-- Handles the current state of locked/unlocked chunks along with helpers.

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
        set[Chunk.key(Chunk.decode(id))] = true
    end
    State.unlockedIDs = ids
    State.unlockedSet = set
end

---Used to determine if a chunk is unlocked/locked.
---@param squareX integer
---@param squareZ integer
---@return boolean
function State.isUnlockedSquare(squareX, squareZ)
    return State.unlockedSet[Chunk.key(squareX, squareZ)] == true
end

---If an ID is an unlocked chunk.
---@param id integer
---@return boolean
function State.isUnlocked(id)
    return State.isUnlockedSquare(Chunk.decode(id))
end

---Count of all the unlocked chunks.
---@return integer
function State.count() return #State.unlockedIDs end

---Sets the state of the chunk (either locked or unlocked).
---@param id integer
---@param unlocked boolean
---@return boolean changed
function State.setUnlocked(id, unlocked)
    id = math.floor(id)
    -- Don't do anything if the chunk is already in the expected state
    if State.isUnlocked(id) == unlocked then return false end

    if unlocked then
        State.appendList({ id })
    else
        -- Rebuild the list without the locked chunk (keeping it sorted)
        local ids = {}
        for _, existing in ipairs(State.unlockedIDs) do
            if existing ~= id then ids[#ids + 1] = existing end
        end
        Settings.set("unlockedChunkIds", Chunk.formatList(ids))
    end

    return true
end

---Toggles a locked/unlocked chunk.
---@param id integer
---@return boolean nowUnlocked
function State.toggle(id)
    local target = not State.isUnlocked(id)
    State.setUnlocked(id, target)
    return target
end

---Used for appending to the chunk ID list instead of overwriting it.
---@param ids integer[]
---@return integer added how many were not already unlocked
function State.appendList(ids)
    local known, order = {}, {}
    for _, id in ipairs(State.unlockedIDs) do
        if not known[id] then
            known[id] = true
            order[#order + 1] = id
        end
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

---Converts new IDs added through the settings panel into in-game IDs.
---Only what is new is converted to in-game IDs.
---@param ids integer[]
---@return integer[] sorted, without duplicates
function State.convertNew(ids)
    local known = {}
    for _, id in ipairs(State.unlockedIDs) do known[id] = true end
    local seen, out = {}, {}
    for _, id in ipairs(ids) do
        if not known[id] then id = Chunk.pickerToGame(id) end
        if not seen[id] then
            seen[id] = true
            out[#out + 1] = id
        end
    end
    table.sort(out)
    return out
end

---Sets a parsed, converted list of chunk IDs into the settings.
---@param text string
function State.commitList(text)
    Settings.set(
        "unlockedChunkIds",
        Chunk.formatList(State.convertNew(Chunk.parseList(tostring(text or ""))))
    )
end

---Adds the chunks from a pasted string to what is already unlocked.
---@param text string
---@return integer how many were not already unlocked
function State.pasteList(text)
    text = tostring(text or "")
    if text == "" then return 0 end
    return State.appendList(State.convertNew(Chunk.parseList(text)))
end

---Initialize the State.
function State.init()
    Settings.subscribe("unlockedChunkIds", function() State.rebuild() end)
    State.rebuild()
end

return State
