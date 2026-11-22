-- The box or volume that greys out a locked chunk.
--
-- The ground fill and tall volume are both built through this, and share the same
-- geometry if they both exist.

local Chunk = require("src/chunk")
local Mesh = require("src/render/mesh")
local Settings = require("src/settings")

local Box = {}
Box.__index = Box

-- Clearance given to the box so it doesn't flicker/collide with the terrain.
-- Causes flickering when moving the camera without this.
Box.CLEARANCE = 30.0

-- Every box is built this tall and pushed down by the difference, so we only
-- need to do height translations based on camera movements. The other thing this
-- is needed for is to make sure the grid lines are always visible through the
-- transparent boxes. Otherwise, if the volume creeps up too high, we'll start losing the
-- grid (also why volume has a height limit).
Box.REFERENCE_HEIGHT = 1000.0 * Chunk.UNITS_PER_TILE

---A box for one chunk.
---@param level integer
---@param chunk table
---@return table box
function Box.new(level, chunk)
    return setmetatable({
        level = level,
        chunk = chunk,
        samples = Settings.get("boxSamples"),
        attempted = false,
        mesh = nil,
    }, Box)
end

---Signature for the box. Unique for specific chunks.
---See drawShape in draw.lua for more info.
---@return string
function Box:signature()
    return "box" .. self.samples
end

---Whether build has already run.
---@return boolean
function Box:built()
    return self.attempted
end

---Builds the mesh, or returns a previous build.
---@return table|nil mesh nil when none of the terrain is loaded
function Box:build()
    if self.attempted then return self.mesh end
    self.attempted = true

    local mesh = Mesh.new(self.level, self.chunk)
    local samples = self.samples
    local lidHeight = Box.CLEARANCE + Box.REFERENCE_HEIGHT

    -- Build the lid as a grid above some sampled ground then create all the
    -- quads that make up the lid using the mesh vertices.
    local lidStart = mesh:grid(samples, lidHeight)
    if lidStart == nil then return nil end

    local verticesPerRow = samples + 1
    for row = 0, samples - 1 do
        for column = 0, samples - 1 do
            local corner = lidStart + row * verticesPerRow + column
            mesh:quad(corner, corner + 1, corner + verticesPerRow + 1, corner + verticesPerRow)
        end
    end

    -- Build a wall hanging down from the lid to the ground.
    ---@param lidVertexAt fun(i: integer): integer
    ---       a helper to get vertices along an edge in the grid
    local function wall(lidVertexAt)
        local previousBottom, previousLid
        for i = 0, samples do
            local lidVertex = lidVertexAt(i)
            local bottomVertex = mesh:below(lidVertex, Box.REFERENCE_HEIGHT)
            if previousBottom ~= nil then
                mesh:quad(previousBottom, bottomVertex, lidVertex, previousLid)
            end
            previousBottom, previousLid = bottomVertex, lidVertex
        end
    end

    -- Build the walls in order: south, north, west, east
    -- lidStart provides the first vertex/position in the grid which is the south-west corner
    wall(function(i) return lidStart + i end)
    wall(function(i) return lidStart + samples * verticesPerRow + i end)
    wall(function(i) return lidStart + i * verticesPerRow end)
    wall(function(i) return lidStart + i * verticesPerRow + samples end)

    self.mesh = mesh
    return mesh
end

---How far down to translate the box so the lid sits at the requested height
---above the ground, in world units (capped at the reference height).
---@param lidHeight number
---@return number y
function Box.translationFor(lidHeight)
    if lidHeight > Box.REFERENCE_HEIGHT then lidHeight = Box.REFERENCE_HEIGHT end
    return lidHeight - Box.REFERENCE_HEIGHT
end

return Box
