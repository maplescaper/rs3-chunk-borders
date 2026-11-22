-- A mesh to contain the vertices and triangles one shape is made of.
--
-- Acts as a somewhat generic helper for building the chunk shapes we need. Both the
-- boxes and the outlines use this. It is a container for the shape definition with
-- helpers for building the more complex shapes.
--
-- Note: every ground height read goes through mesh:height to be able to control
-- the number of times we do ground samples for performance and provide a per-frame
-- budget.

local Chunk = require("src/chunk")

local Mesh = {}
Mesh.__index = Mesh

local samplesThisFrame = 0

---How many ground heights have been read since the last reset.
---@return integer
function Mesh.samplesThisFrame() return samplesThisFrame end

---Starts the count over at the start of a frame.
function Mesh.resetSamples() samplesThisFrame = 0 end

---Starts an empty mesh for one chunk. Vertices are stored relative to the
---chunk's world origin so the finished shape is translated to the origin.
---@param level integer
---@param chunk table
---@return table mesh
function Mesh.new(level, chunk)
    local originX, originZ = chunk:worldOrigin()
    return setmetatable({
        level = level,
        originX = originX,
        originZ = originZ,
        positions = {},
        tris = {},
        borrowed = {},
    }, Mesh)
end

---Returns the ground height at this location.
---@param worldX number world units
---@param worldZ number world units
---@return number|nil height nil when the terrain there is not loaded
function Mesh:height(worldX, worldZ)
    samplesThisFrame = samplesThisFrame + 1
    local height, available = World.GetGroundHeight(self.level, worldX, worldZ)
    if not available then return nil end
    return height
end

---Adds a new vertex to the positions.
---@param x number relative to the chunk's origin
---@param y number
---@param z number relative to the chunk's origin
---@return integer index of new vector
function Mesh:push(x, y, z)
    self.positions[#self.positions + 1] = Vector3.new(x, y, z)
    return #self.positions - 1
end

---Builds a new vertex at the requested position relative to
---the chunk's origin position.
---@param worldX number world units
---@param y number
---@param worldZ number world units
---@return integer new vertex index
function Mesh:vertex(worldX, y, worldZ)
    return self:push(worldX - self.originX, y, worldZ - self.originZ)
end

---A vertex directly under an existing one (e.g. from the same ground reading).
---@param index integer position index
---@param drop number
---@return integer new vertex index
function Mesh:below(index, drop)
    local above = self.positions[index + 1]
    return self:push(above.x, above.y - drop, above.z)
end

---Builds a triangle from three vertices.
---@param a integer zero-based vertex index
---@param b integer
---@param c integer
function Mesh:tri(a, b, c)
    local tris = self.tris
    tris[#tris + 1] = a
    tris[#tris + 1] = b
    tris[#tris + 1] = c
end

---Draw a quad.
---@param a integer vertex index, then b, c, d around the quad
---@param b integer
---@param c integer
---@param d integer
function Mesh:quad(a, b, c, d)
    self:tri(a, b, c)
    self:tri(a, c, d)
end

---Builds a grid on a chunk. Used for the lid and volumes.
---@param samples integer number of times we sample for the grid height for vertices
---@param clearance number baseline height above the ground for every vertex
---@return integer|nil first index of the south-west vertex, nil when none of the terrain is loaded
function Mesh:grid(samples, clearance)
    local step = Chunk.UNITS_PER_CHUNK / samples
    local first = #self.positions

    -- Sample the whole grid first, so points with no terrain loaded can
    -- borrow the nearest loaded height.
    local points = {}
    for row = 0, samples do
        for column = 0, samples do
            local worldX = self.originX + column * step
            local worldZ = self.originZ + row * step
            points[#points + 1] = { x = worldX, z = worldZ, height = self:height(worldX, worldZ) }
        end
    end
    if not self:fillMissing(points) then return nil end

    for _, point in ipairs(points) do
        self:vertex(point.x, point.height + clearance, point.z)
    end

    return first
end

---Fills in the height of every point where the terrain is not loaded from
---the nearest point where it is. Needed for lower draw distances. Stores the
---unloaded points in borrowed so we can check if we need to rebuild.
---@param points table[] { x, z, height|nil }, in world units
---@return boolean any false when no point has a height
function Mesh:fillMissing(points)
    local known = {}
    for _, point in ipairs(points) do
        if point.height ~= nil then known[#known + 1] = point end
    end
    if #known == 0 then return false end

    for _, point in ipairs(points) do
        if point.height == nil then
            local nearest, best = nil, math.huge
            for _, candidate in ipairs(known) do
                local dx, dz = candidate.x - point.x, candidate.z - point.z
                local distance = dx * dx + dz * dz
                if distance < best then nearest, best = candidate, distance end
            end
            point.height = nearest.height
            self.borrowed[#self.borrowed + 1] = point
        end
    end
    return true
end

---Whether terrain has loaded under any point that borrowed a height.
---@return boolean
function Mesh:terrainLoaded()
    for _, point in ipairs(self.borrowed) do
        if self:height(point.x, point.z) ~= nil then return true end
    end
    return false
end

---Return a completed shape in a ShapeData object.
---@return table shapeData a fresh ShapeData each call, sharing this mesh's tables
function Mesh:finish()
    local shapeData = ShapeData.new()
    shapeData.positions = self.positions
    shapeData.rgba = {}
    shapeData.lines = {}
    shapeData.tris = self.tris
    return shapeData
end

return Mesh
