-- Helpers for handling chunk IDs.
--
-- A chunk ID is chunkX * 256 + chunkZ, mostly the same ID the Chunk Picker uses.
-- Existing chunk lists paste straight in except for a few regions the
-- picker stores at a constant offset, which Chunk.pickerToGame corrects.

local Chunk = {}

Chunk.TILES_PER_CHUNK = 64
Chunk.CHUNKS_PER_AXIS = 256

---Decodes a chunk ID into a coordinate region.
---@param id integer
---@return integer chunkX, integer chunkZ
function Chunk.decode(id)
    id = math.floor(id)
    return id // Chunk.CHUNKS_PER_AXIS, id % Chunk.CHUNKS_PER_AXIS
end

---Encodes a coordinate region into a chunk ID.
---@param chunkX integer
---@param chunkZ integer
---@return integer
function Chunk.encode(chunkX, chunkZ)
    return chunkX * Chunk.CHUNKS_PER_AXIS + chunkZ
end

---The chunk a coordinate is in.
---@param coord table CoordGrid-like (absolute tile .x/.z)
---@return integer chunkX, integer chunkZ
function Chunk.fromCoord(coord)
    return coord.x // Chunk.TILES_PER_CHUNK, coord.z // Chunk.TILES_PER_CHUNK
end

---The ID of the chunk a coordinate is in.
---@param coord table CoordGrid-like
---@return integer
function Chunk.idFromCoord(coord)
    return Chunk.encode(Chunk.fromCoord(coord))
end

---Returns a string key of the coordinate region.
---@param chunkX integer
---@param chunkZ integer
---@return string
function Chunk.key(chunkX, chunkZ)
    return chunkX .. "," .. chunkZ
end

---Checks if a chunk is in a given bounding box.
---@param chunkX integer
---@param chunkZ integer
---@param loID integer
---@param hiID integer
---@return boolean
function Chunk.inBox(chunkX, chunkZ, loID, hiID)
    local ax, az = Chunk.decode(loID)
    local bx, bz = Chunk.decode(hiID)
    if ax > bx then ax, bx = bx, ax end
    if az > bz then az, bz = bz, az end
    return chunkX >= ax and chunkX <= bx and chunkZ >= az and chunkZ <= bz
end

-- Chunk Picker -> in-game chunk-ID remap. The picker stores a
-- handful of regions at a different ID offset than the game.
Chunk.PICKER_REMAP = {
    { 14870, 18212, -7785 },   -- Arc Islands
    { 14655, 16967,  5857 },   -- Anachronia
    { 16176, 17720, -2844 },   -- Havenhythe
    {  7471,  7986, -2265 },   -- Lost Grove
}

---Uses the picker remap above to map the chunk picker IDs into ingame ones.
---@param id integer a Chunk Picker chunk ID
---@return integer the in-game chunk ID
function Chunk.pickerToGame(id)
    local chunkX, chunkZ = Chunk.decode(id)
    for _, remap in ipairs(Chunk.PICKER_REMAP) do
        if Chunk.inBox(chunkX, chunkZ, remap[1], remap[2]) then
            return id + remap[3]
        end
    end
    return id
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
