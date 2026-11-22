-- The border outline drawn around a chunk.
--
-- The outline is a series of flat quad segments laid along each edge of the
-- chunk centered on the boundary line. Done this way to be able to provide
-- line widths since no existing API shapes work with widths.
--
-- TODO: Test more with ShapeData.lines, ShapeList.Draw, and ShapeList.DrawLine.
-- They all draw, but the line stays thin at any lineWidth settings.

local Box = require("src/render/box")
local Chunk = require("src/chunk")
local Mesh = require("src/render/mesh")
local Settings = require("src/settings")

local Outline = {}
Outline.__index = Outline

-- World units per unit of the line width setting
Outline.UNITS_PER_LINE_WIDTH = 32.0

-- The line floats just above the box lid so it stays visible through it.
Outline.CLEARANCE = Box.CLEARANCE + 4.0

---An outline for one chunk, not built yet.
---@param level integer
---@param chunk table
---@param lineWidth number the line width setting
---@return table outline
function Outline.new(level, chunk, lineWidth)
    return setmetatable({
        level = level,
        chunk = chunk,
        width = lineWidth * Outline.UNITS_PER_LINE_WIDTH,
        samples = Settings.get("lineSamples"),
    }, Outline)
end

---Signature for the outline. Unique for specific chunks.
---See drawShape in draw.lua for more info.
---@return string
function Outline:signature()
    return "w" .. self.width .. "s" .. self.samples
end

---Builds the outline.
---@return table|nil mesh nil when none of the terrain is loaded
function Outline:build()
    local mesh = Mesh.new(self.level, self.chunk)
    local half = self.width * 0.5
    local x0, z0 = mesh.originX, mesh.originZ
    local x1, z1 = x0 + Chunk.UNITS_PER_CHUNK, z0 + Chunk.UNITS_PER_CHUNK

    -- The four edges of the chunk and a unit vector across it
    -- for handling the width: south, north, west, east.
    local edges = {
        { fromX = x0, fromZ = z0, toX = x1, toZ = z0, acrossX = 0.0, acrossZ = 1.0 },
        { fromX = x0, fromZ = z1, toX = x1, toZ = z1, acrossX = 0.0, acrossZ = 1.0 },
        { fromX = x0, fromZ = z0, toX = x0, toZ = z1, acrossX = -1.0, acrossZ = 0.0 },
        { fromX = x1, fromZ = z0, toX = x1, toZ = z1, acrossX = -1.0, acrossZ = 0.0 },
    }

    -- Sample every edge's centre line first so we can fill in missing terrain
    -- before building if needed.
    local samples = self.samples
    local centres = {}
    for _, edge in ipairs(edges) do
        edge.centres = {}
        for sample = 0, samples do
            local ratio = sample / samples
            local centreX = edge.fromX + (edge.toX - edge.fromX) * ratio
            local centreZ = edge.fromZ + (edge.toZ - edge.fromZ) * ratio
            local centre = { x = centreX, z = centreZ, height = mesh:height(centreX, centreZ) }
            edge.centres[#edge.centres + 1] = centre
            centres[#centres + 1] = centre
        end
    end
    if not mesh:fillMissing(centres) then return nil end

    for _, edge in ipairs(edges) do
        local offsetX, offsetZ = edge.acrossX * half, edge.acrossZ * half
        local previous
        for _, centre in ipairs(edge.centres) do
            -- Each side of the line gets a vertex to handle differing
            -- ground heights with line width.
            local leftX, leftZ = centre.x + offsetX, centre.z + offsetZ
            local rightX, rightZ = centre.x - offsetX, centre.z - offsetZ

            local leftHeight = mesh:height(leftX, leftZ) or centre.height
            local rightHeight = mesh:height(rightX, rightZ) or centre.height

            local left = mesh:vertex(leftX, leftHeight + Outline.CLEARANCE, leftZ)
            local right = mesh:vertex(rightX, rightHeight + Outline.CLEARANCE, rightZ)

            -- Build a line segment (quad) connected to the previous one
            if previous ~= nil then
                mesh:quad(previous, previous + 1, right, left)
            end

            previous = left
        end
    end

    return mesh
end

return Outline
