-- A chunk is a 64x64 tile region of the map which the plugin locks/unlocks.
-- There is one Chunk object per chunk and you can use atGrid, atID, and
-- atTile to access them depending on the input you have.
--
-- The term grid here refers to the chunk grid, or a grid of 64x64-tile chunks.
-- Tile refers to an in-game coordinate (like the play position).
--
-- A chunk ID is gridX * 256 + gridZ, mostly the same ID the Chunk Picker uses.
-- Existing chunk lists paste straight in except for a few regions the
-- picker stores at a constant offset, which Chunk.pickerToGameID corrects.

local Chunk = {}
Chunk.__index = Chunk

Chunk.TILES_PER_CHUNK = 64
Chunk.CHUNKS_PER_AXIS = 256
Chunk.UNITS_PER_TILE = 512.0
Chunk.UNITS_PER_CHUNK = Chunk.UNITS_PER_TILE * Chunk.TILES_PER_CHUNK

-- Every chunk object made so far, by ID, so that lookups share one object.
local chunksByID = {}

---Converts a grid position into a chunk ID.
---@param gridX integer
---@param gridZ integer
---@return integer
function Chunk.encode(gridX, gridZ)
    return gridX * Chunk.CHUNKS_PER_AXIS + gridZ
end

---The chunk at a grid position.
---@param gridX integer
---@param gridZ integer
---@return table chunk
function Chunk.atGrid(gridX, gridZ)
    local id = Chunk.encode(gridX, gridZ)
    local chunk = chunksByID[id]
    if chunk == nil then
        chunk = Chunk:new(gridX, gridZ)
        chunksByID[id] = chunk
    end
    return chunk
end

---The chunk with a given ID.
---@param id integer
---@return table chunk
function Chunk.atID(id)
    id = math.floor(id)
    return Chunk.atGrid(id // Chunk.CHUNKS_PER_AXIS, id % Chunk.CHUNKS_PER_AXIS)
end

---The chunk a tile coordinate is in.
---@param coord table CoordGrid-like (absolute tile .x/.z)
---@return table chunk
function Chunk.atTile(coord)
    return Chunk.atGrid(
        math.floor(coord.x / Chunk.TILES_PER_CHUNK),
        math.floor(coord.z / Chunk.TILES_PER_CHUNK)
    )
end

---A fresh chunk object. Callers go through Chunk.atGrid, Chunk.atID or
---Chunk.atTile instead, so that two lookups of the same chunk share one object.
---@param gridX integer
---@param gridZ integer
---@return table chunk with .id, .gridX and .gridZ
function Chunk:new(gridX, gridZ)
    local instance = setmetatable({}, self)
    instance.gridX = gridX
    instance.gridZ = gridZ
    instance.id = Chunk.encode(gridX, gridZ)
    return instance
end

---The chunk some grid steps away from this one.
---@param dx integer
---@param dz integer
---@return table chunk
function Chunk:neighbour(dx, dz)
    return Chunk.atGrid(self.gridX + dx, self.gridZ + dz)
end

---The south-west corner of the chunk, in world units.
---@return number originX, number originZ
function Chunk:worldOrigin()
    return self.gridX * Chunk.UNITS_PER_CHUNK, self.gridZ * Chunk.UNITS_PER_CHUNK
end

---Checks if the chunk is inside the box spanned by two chunk IDs.
---@param loID integer
---@param hiID integer
---@return boolean
function Chunk:inBox(loID, hiID)
    local lo, hi = Chunk.atID(loID), Chunk.atID(hiID)
    local ax, bx = lo.gridX, hi.gridX
    local az, bz = lo.gridZ, hi.gridZ
    if ax > bx then ax, bx = bx, ax end
    if az > bz then az, bz = bz, az end
    return self.gridX >= ax and self.gridX <= bx and self.gridZ >= az and self.gridZ <= bz
end

-- Chunk Picker -> in-game chunk-ID remap. The picker stores a
-- handful of regions at a different ID offset than the game.
Chunk.PICKER_REMAP = {
    { 14870, 18212, -7785 },   -- Arc Islands
    { 14655, 16967,  5857 },   -- Anachronia
    { 16176, 17720, -2844 },   -- Havenhythe
    {  7471,  7986, -2265 },   -- Lost Grove
}

---Uses the picker remap above to map a chunk picker ID to an in-game one.
---@param id integer a Chunk Picker chunk ID
---@return integer the in-game chunk ID
function Chunk.pickerToGameID(id)
    local chunk = Chunk.atID(id)
    for _, remap in ipairs(Chunk.PICKER_REMAP) do
        if chunk:inBox(remap[1], remap[2]) then
            return chunk.id + remap[3]
        end
    end
    return chunk.id
end

---Junk tokens and negatives are dropped rather than raising because this
---parses a text field a player typed.
---@param text string|nil
---@return integer[]
function Chunk.parseList(text)
    local seen, ids = {}, {}

    for token in tostring(text or ""):gmatch("[^,%s]+") do
        local id = tonumber(token)

        if id and id >= 0 then
            id = math.floor(id)
            if not seen[id] then
                seen[id] = true
                ids[#ids + 1] = id
            end
        end
    end

    table.sort(ids)
    return ids
end

---Formats the chunk IDs into a list for display or storage.
---@param ids integer[]
---@return string
function Chunk.formatList(ids)
    local parts = {}
    for index, id in ipairs(ids) do parts[index] = tostring(id) end
    return table.concat(parts, ", ")
end

return Chunk
