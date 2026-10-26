-- Mesh builder used to build the volumes and grid lines.
--
-- Everything here is made of vertices and triangles (for ShapeData.tris), with
-- the triangles grouped into quads through mesh.quad. draw.lua uses this to build the
-- shader boxes and the border lines.
--
-- Every ground height read goes through mesh.height, so this is also the one
-- place that counts terrain samples for the frame budget in draw.lua.

local Chunk = require("src/chunk")

local Mesh = {}

local samplesThisFrame = 0

-- TODO: Move these to a constants file.
Mesh.UNITS_PER_TILE = 512.0
Mesh.UNITS_PER_CHUNK = Mesh.UNITS_PER_TILE * Chunk.TILES_PER_CHUNK

---How many ground heights have been read since the last reset.
---@return integer
function Mesh.samplesThisFrame() return samplesThisFrame end

---Starts the count over at the start of a frame.
function Mesh.resetSamples() samplesThisFrame = 0 end

---Starts a mesh for one chunk. The returned object carries originX, originZ,
---positions and tris, plus the builder functions below. Call mesh.finish to
---get a ShapeData object that can be drawn.
---@param level integer
---@param chunkX integer
---@param chunkZ integer
---@return table mesh
function Mesh.new(level, chunkX, chunkZ)
    local originX = chunkX * Mesh.UNITS_PER_CHUNK
    local originZ = chunkZ * Mesh.UNITS_PER_CHUNK
    local mesh = { originX = originX, originZ = originZ, positions = {}, tris = {} }

    ---Returns the ground height at this location.
    ---@param worldX number world units
    ---@param worldZ number world units
    ---@return number|nil height nil when the terrain there is not loaded
    function mesh.height(worldX, worldZ)
        samplesThisFrame = samplesThisFrame + 1
        local height, available = World.GetGroundHeight(level, worldX, worldZ)
        if not available then return nil end
        return height
    end

    ---Adds a new vertex to the positions.
    ---@param x number relative to the chunk's origin
    ---@param y number
    ---@param z number relative to the chunk's origin
    ---@return integer index of new vector
    local function push(x, y, z)
        mesh.positions[#mesh.positions + 1] = Vector3.new(x, y, z)
        return #mesh.positions - 1
    end

    ---Builds a new vertex at the requested position relative to
    ---the chunk's origin position.
    ---@param worldX number world units
    ---@param y number
    ---@param worldZ number world units
    ---@return integer new vertex index
    function mesh.vertex(worldX, y, worldZ)
        return push(worldX - originX, y, worldZ - originZ)
    end

    ---A vertex directly under an existing one (e.g. from the same ground reading).
    ---@param index integer position index
    ---@param drop number
    ---@return integer new vertex index
    function mesh.below(index, drop)
        local above = mesh.positions[index + 1]
        return push(above.x, above.y - drop, above.z)
    end

    ---Builds a triangle from three vertices.
    ---@param a integer zero-based vertex index
    ---@param b integer
    ---@param c integer
    function mesh.tri(a, b, c)
        local tris = mesh.tris
        tris[#tris + 1] = a
        tris[#tris + 1] = b
        tris[#tris + 1] = c
    end

    ---Draw a quad. Wound one way only since the client
    ---draws both faces of the quad.
    ---@param a integer vertex index, then b, c, d around the quad
    ---@param b integer
    ---@param c integer
    ---@param d integer
    function mesh.quad(a, b, c, d)
        mesh.tri(a, b, c)
        mesh.tri(a, c, d)
    end

    ---Builds a grid on a chunk. Used for the lid and volumes.
    ---@param samples integer number of times we sample for the grid height for vertices
    ---@param clearance number baseline height above the ground for every vertex
    ---@return integer|nil first index of the south-west vertex, nil when terrain is not loaded
    function mesh.grid(samples, clearance)
        local step = Mesh.UNITS_PER_CHUNK / samples
        local first = #mesh.positions

        for row = 0, samples do
            for column = 0, samples do
                -- Get the ground height at this location in the world
                local worldX = originX + column * step
                local worldZ = originZ + row * step
                local height = mesh.height(worldX, worldZ)
                if height == nil then return nil end

                -- Add a vertex for it
                mesh.vertex(worldX, height + clearance, worldZ)
            end
        end

        return first
    end

    ---Return a completed shape in a ShapeData object.
    ---@return table shapeData a fresh ShapeData each call, sharing this mesh's tables
    function mesh.finish()
        local shapeData = ShapeData.new()
        shapeData.positions = mesh.positions
        shapeData.rgba = {}
        shapeData.lines = {}
        shapeData.tris = mesh.tris
        return shapeData
    end

    return mesh
end

return Mesh
