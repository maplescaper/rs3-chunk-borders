-- Helpers for handling the overworld chunks (and underground/extra
-- chunks if requested).

local Chunk = require("src/chunk")

local Overworld = {}

-- Main overworld chunks, and extra overworld chunks from the chunk picker.
-- These are disjointed locations. See src/chunk.lua.
Overworld.OVERWORLD = { 6950, 15424 }
Overworld.EXTRA_OVERWORLD = {
    { 5206, 5721 },
    { 7085, 10427 },
    { 20512, 22824 },
    { 13332, 14876 },
}

---Check if a chunk is in the overworld (mapped above).
---@param chunkX integer
---@param chunkZ integer
---@return boolean
function Overworld.isOverworldChunk(chunkX, chunkZ)
    if Chunk.inBox(chunkX, chunkZ, Overworld.OVERWORLD[1], Overworld.OVERWORLD[2]) then
        return true
    end
    for _, box in ipairs(Overworld.EXTRA_OVERWORLD) do
        if Chunk.inBox(chunkX, chunkZ, box[1], box[2]) then return true end
    end
    return false
end

---Tells us if a chunk is in the overworld or an underground area
---to determine if we should grey it out. Instances/regions are
---never greyed out.
---@param coord table
---@param detectOverworld boolean
---@return boolean
function Overworld.applies(coord, detectOverworld)
    if World.IsRegion() then return false end
    if not detectOverworld then return true end
    local sx, sz = Chunk.fromCoord(coord)
    return Overworld.isOverworldChunk(sx, sz)
end

return Overworld
