-- Helpers for handling the overworld chunks (and underground/extra
-- chunks if requested).

local Chunk = require("src/chunk")

local Overworld = {}

-- Main overworld chunks, and extra overworld chunks from the chunk picker.
-- These are disjointed locations. See src/chunks.lua.
Overworld.OVERWORLD = { 6950, 15424 }
Overworld.EXTRA_OVERWORLD = {
    { 5206, 5721 },
    { 7085, 10427 },
    { 20512, 22824 },
    { 13332, 14876 },
}

---Check if a chunk is in the overworld (mapped above).
---@param squareX integer
---@param squareZ integer
---@return boolean
function Overworld.isOverworldSquare(squareX, squareZ)
    if Chunk.inBox(squareX, squareZ, Overworld.OVERWORLD[1], Overworld.OVERWORLD[2]) then
        return true
    end
    for _, box in ipairs(Overworld.EXTRA_OVERWORLD) do
        if Chunk.inBox(squareX, squareZ, box[1], box[2]) then return true end
    end
    return false
end

---The map square a coordinate is in.
---@param coord table CoordGrid-like
---@return integer squareX, integer squareZ
function Overworld.governingSquare(coord)
    return coord.x // Chunk.TILES_PER_SQUARE, coord.z // Chunk.TILES_PER_SQUARE
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
    local sx, sz = Overworld.governingSquare(coord)
    return Overworld.isOverworldSquare(sx, sz)
end

return Overworld
