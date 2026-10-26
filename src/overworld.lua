-- Helpers for handling the overworld chunks (and underground/extra
-- chunks if requested).

local Overworld = {}

-- The overworld as boxes of chunk IDs: the main map first, then the
-- disjoint extra areas the chunk picker treats as overworld. See src/chunk.lua.
Overworld.BOXES = {
    { 6950, 15424 },    -- main overworld
    { 5206, 5721 },
    { 7085, 10427 },
    { 20512, 22824 },
    { 13332, 14876 },
}

---Check if a chunk is in the overworld (mapped above).
---@param chunk table
---@return boolean
function Overworld.isOverworldChunk(chunk)
    for _, box in ipairs(Overworld.BOXES) do
        if chunk:inBox(box[1], box[2]) then return true end
    end
    return false
end

---Tells us if a chunk is in the overworld or an underground area
---to determine if we should grey it out. Instances/regions are
---never greyed out.
---@param chunk table
---@param detectOverworld boolean
---@return boolean
function Overworld.applies(chunk, detectOverworld)
    if World.IsRegion() then return false end
    if not detectOverworld then return true end
    return Overworld.isOverworldChunk(chunk)
end

return Overworld
