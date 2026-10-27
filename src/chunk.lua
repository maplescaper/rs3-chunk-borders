-- A chunk is a 64x64 tile region of the map which the plugin locks/unlocks.
-- There is one Chunk object per chunk and you can use atGrid, atID, and
-- atTile to access them depending on the input you have.
--
-- The term grid here refers to the chunk grid, or a grid of 64x64-tile chunks.
-- Tile refers to an in-game coordinate (like the play position).
--
-- A chunk ID is gridX * 256 + gridZ. The plugin holds in-game IDs, while the
-- player only ever sees and types Chunk Picker IDs. The two agree except for
-- a few regions.

local Chunk = {}
Chunk.__index = Chunk

Chunk.TILES_PER_CHUNK = 64
Chunk.CHUNKS_PER_AXIS = 256
Chunk.UNITS_PER_TILE = 512.0
Chunk.UNITS_PER_CHUNK = Chunk.UNITS_PER_TILE * Chunk.TILES_PER_CHUNK

-- Chunk Picker -> in-game chunk-ID remap. The picker uses the world map but
-- in-game these areas are at completely different chunk IDs so we need to
-- remap. First two numbers are the bounding box, and the third is an offset
-- to translate a picker ID: in-game = picker + offset
Chunk.PICKER_REMAP = {
    { 14870, 18212, -7785 },   -- Arc Islands
    { 14655, 16967,  5857 },   -- Anachronia
    { 16176, 17720, -2844 },   -- Havenhythe
    {  7471,  7986, -2265 },   -- Lost Grove
}

-- Every chunk object made so far, by ID, so that lookups share one object.
local chunksByID = {}

---Converts a grid position into a chunk ID.
---@param gridX integer
---@param gridZ integer
---@return integer
function Chunk.idFromGrid(gridX, gridZ)
    return gridX * Chunk.CHUNKS_PER_AXIS + gridZ
end

---The chunk at a grid position.
---@param gridX integer
---@param gridZ integer
---@return table chunk
function Chunk.atGrid(gridX, gridZ)
    local id = Chunk.idFromGrid(gridX, gridZ)
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

---The chunk a Chunk Picker ID names.
---@param pickerID integer
---@return table chunk
function Chunk.atPickerID(pickerID)
    local chunk = Chunk.atID(pickerID)
    for _, remap in ipairs(Chunk.PICKER_REMAP) do
        if chunk:inBox(remap[1], remap[2]) then
            return Chunk.atID(chunk.id + remap[3])
        end
    end
    return chunk
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
    instance.id = Chunk.idFromGrid(gridX, gridZ)
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

---The ID the Chunk Picker shows for this chunk.
---@return integer
function Chunk:pickerID()
    for _, remap in ipairs(Chunk.PICKER_REMAP) do
        if self:inBox(remap[1] + remap[3], remap[2] + remap[3]) then
            return self.id - remap[3]
        end
    end
    return self.id
end

---Parses a comma-separated list of chunk IDs as written. Junk tokens and
---negatives are dropped rather than raising because this parses text a
---player typed.
---@param text string|nil
---@return integer[] sorted, without duplicates
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

---Formats chunk IDs into a comma-separated list as they are.
---@param ids integer[]
---@return string
function Chunk.formatList(ids)
    local parts = {}
    for index, id in ipairs(ids) do parts[index] = tostring(id) end
    return table.concat(parts, ", ")
end

---Parses a list the player typed (assumes always Chunk Picker IDs) into the
---in-game IDs the plugin holds.
---@param text string|nil
---@return integer[] in-game IDs, sorted, without duplicates
function Chunk.parsePickerList(text)
    local seen, ids = {}, {}
    for _, pickerID in ipairs(Chunk.parseList(text)) do
        local id = Chunk.atPickerID(pickerID).id
        if not seen[id] then
            seen[id] = true
            ids[#ids + 1] = id
        end
    end
    table.sort(ids)
    return ids
end

---Formats in-game chunk IDs as the Chunk Picker IDs the player sees.
---@param ids integer[] in-game IDs
---@return string
function Chunk.formatPickerList(ids)
    local pickerIDs = {}
    for index, id in ipairs(ids) do pickerIDs[index] = Chunk.atID(id):pickerID() end
    table.sort(pickerIDs)
    return Chunk.formatList(pickerIDs)
end

return Chunk
