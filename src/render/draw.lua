-- Handles building, and drawing all the requested shapes from overlay.lua.
--
-- The overall process involves building a mesh of vertices, then making a shape
-- using triangles (for use in ShapeData.tris). The triangles are grouped into
-- quads (see mesh.quad in mesh.lua) in all cases. These quads then produce
-- the volumes or boxes shown in game. The buildBox, and buildOutline actually
-- produce the volumes/lines seen in game.
--
-- Note: Lines are also built this way since the lineWidth isn't being handled properly
-- in the existing API methods for some reason (a TODO for later).
--
-- The drawing process has a frame budget that dictates how much sampling we can do per
-- frame as well to try to limit the impact on sudden world shifts. This is handled through
-- the draw cycle: Draw.beginFrame, Draw.chunk, and Draw.endFrame. Overlay.frame
-- handles calling these. That budget is counted within the mesh.lua file.
--
-- The logic that handles the drawing, caching, and rebuilding for a chunk is
-- found in drawShape.

local Chunk = require("src/chunk")
local Mesh = require("src/render/mesh")
local Settings = require("src/settings")

local Draw = {}

local UNITS_PER_LINE_WIDTH = 32.0

-- Clearance given to the box and line so they don't flicker/collide with
-- the terrain. Causes flickering when moving the camera without this.
Draw.BOX_CLEARANCE = 30.0
local LINE_CLEARANCE = Draw.BOX_CLEARANCE + 4.0

-- Every box is built this tall and pushed down by the difference, so we only
-- need to do height translations based on camera movements. The other thing this
-- is needed for is to make sure the grid lines are always visible through the
-- transparent boxes. Otherwise, if the volume creeps up too high, we'll start losing the
-- grid (also why volume has a height limit).
Draw.BOX_REFERENCE_HEIGHT = 1000.0 * Chunk.UNITS_PER_TILE

local shapes = {}
local serial = 0
local frame = 0

-- Budget that we have per frame to sample the map. Needed for things like teleporting
-- or other sudden shifts in the overworld for maintaining performance.
Draw.frameSampleBudget = 4000

-- How long to wait before retrying to build a specific chunk
Draw.retryFrames = 12

local retryAt = {}

-- How often to check whether terrain has loaded under a partially built shape
Draw.recheckFrames = 30

-- Instances replaced by a rebuild this frame
local retiring = {}

---Safe wrapper around the destroy shape call.
local function destroyShape(shape)
    pcall(function() shape:Destroy() end)
end

---Builds a mesh for a box/volume.
---@return table|nil mesh nil when none of the terrain is loaded
local function buildBox(level, chunk)
    local mesh = Mesh.new(level, chunk)
    local samples = Settings.get("boxSamples")
    local lidHeight = Draw.BOX_CLEARANCE + Draw.BOX_REFERENCE_HEIGHT

    -- Build the lid as a grid above some sampled ground then create all the
    -- quads that make up the lid using the mesh vertices.
    local lidStart = mesh.grid(samples, lidHeight)
    if lidStart == nil then return nil end
    local verticesPerRow = samples + 1
    for row = 0, samples - 1 do
        for column = 0, samples - 1 do
            local corner = lidStart + row * verticesPerRow + column
            mesh.quad(corner, corner + 1, corner + verticesPerRow + 1, corner + verticesPerRow)
        end
    end

    -- Build a wall hanging down from the lid to the ground.
    ---@param lidVertexAt fun(i: integer): integer lid vertex at the i-th position along the edge
    local function wall(lidVertexAt)
        local previousBottom, previousLid
        for i = 0, samples do
            local lidVertex = lidVertexAt(i)
            local bottomVertex = mesh.below(lidVertex, Draw.BOX_REFERENCE_HEIGHT)
            if previousBottom ~= nil then
                mesh.quad(previousBottom, bottomVertex, lidVertex, previousLid)
            end
            previousBottom, previousLid = bottomVertex, lidVertex
        end
    end

    -- Build the walls in order: south, north, west, east
    wall(function(i) return lidStart + i end)
    wall(function(i) return lidStart + samples * verticesPerRow + i end)
    wall(function(i) return lidStart + i * verticesPerRow end)
    wall(function(i) return lidStart + i * verticesPerRow + samples end)

    return mesh
end

---Builds an outline of the region using flat quad segments instead of lines.
---
---TODO: Test more with ShapeData.lines, ShapeList.Draw, and ShapeList.DrawLine.
---They all draw, but the line stays thin at any lineWidth settings.
---@param width number ribbon width, in world units
---@return table|nil mesh nil when none of the terrain is loaded
local function buildOutline(level, chunk, width)
    local mesh = Mesh.new(level, chunk)
    local half = width * 0.5
    local x0, z0 = mesh.originX, mesh.originZ
    local x1, z1 = x0 + Chunk.UNITS_PER_CHUNK, z0 + Chunk.UNITS_PER_CHUNK

    -- The four edges of the chunk, each as its two ends and a unit vector
    -- across it for handling the width: south, north, west, east.
    local edges = {
        { fromX = x0, fromZ = z0, toX = x1, toZ = z0, acrossX = 0.0, acrossZ = 1.0 },
        { fromX = x0, fromZ = z1, toX = x1, toZ = z1, acrossX = 0.0, acrossZ = 1.0 },
        { fromX = x0, fromZ = z0, toX = x0, toZ = z1, acrossX = -1.0, acrossZ = 0.0 },
        { fromX = x1, fromZ = z0, toX = x1, toZ = z1, acrossX = -1.0, acrossZ = 0.0 },
    }

    -- Sample every edge's centre line first, so points with no terrain loaded
    -- can borrow the nearest loaded height.
    local samples = Settings.get("lineSamples")
    local centres = {}
    for _, edge in ipairs(edges) do
        edge.centres = {}
        for sample = 0, samples do
            local ratio = sample / samples
            local centreX = edge.fromX + (edge.toX - edge.fromX) * ratio
            local centreZ = edge.fromZ + (edge.toZ - edge.fromZ) * ratio
            local centre = { x = centreX, z = centreZ, height = mesh.height(centreX, centreZ) }
            edge.centres[#edge.centres + 1] = centre
            centres[#centres + 1] = centre
        end
    end
    if not mesh.fillMissing(centres) then return nil end

    for _, edge in ipairs(edges) do
        local offsetX, offsetZ = edge.acrossX * half, edge.acrossZ * half
        local previous
        for _, centre in ipairs(edge.centres) do
            -- One vertex either side of the centre line. Each incorporates the ground
            -- under itself so the line travels with the terrain.
            local leftX, leftZ = centre.x + offsetX, centre.z + offsetZ
            local rightX, rightZ = centre.x - offsetX, centre.z - offsetZ
            local leftHeight = mesh.height(leftX, leftZ) or centre.height
            local rightHeight = mesh.height(rightX, rightZ) or centre.height
            local left = mesh.vertex(leftX, leftHeight + LINE_CLEARANCE, leftZ)
            local right = mesh.vertex(rightX, rightHeight + LINE_CLEARANCE, rightZ)

            -- Build a line segment (quad) connected to the previous one
            if previous ~= nil then
                mesh.quad(previous, previous + 1, right, left)
            end

            previous = left
        end
    end

    return mesh
end

---Brings an existing shape in line with what this frame asks of it and
---marks it as seen so Draw.endFrame keeps it.
---@param entry table
---@param x number
---@param y number
---@param z number
---@param colour integer
local function syncShape(entry, x, y, z, colour)
    local shape = entry.shape
    if entry.colour ~= colour then
        shape.colour = colour
        entry.colour = colour
    end
    if entry.x ~= x or entry.y ~= y or entry.z ~= z then
        shape.translation = Vector3.new(x, y, z)
        entry.x, entry.y, entry.z = x, y, z
    end
    entry.lastSeen = frame
end

---Builds a new instance holding this geometry.
---@param shapeData table
---@return table|nil shape
local function createInstance(shapeData)
    serial = serial + 1
    local shape = ShapeList.CreateInstance(string.format("chunk_borders_%d", serial))
    if shape == nil then return nil end
    if not shape:SetShapeData(shapeData) then
        destroyShape(shape)
        return nil
    end
    shape.ignoreDepth = false
    return shape
end

---Checks if we need to rebuild because new terrain loaded in.
---@param entry table
---@return boolean
local function terrainArrived(entry)
    if entry.recheckAt == nil or frame < entry.recheckAt then return false end
    entry.recheckAt = frame + Draw.recheckFrames
    return entry.mesh.terrainLoaded()
end

---Draws one shape for this frame.
---
---Shows the cached shape when there is one for this signature or when the
---frame budget is spent. Otherwise builds it, sets up a retry if that fails,
---and caches it. Rebuilds draw the new shape first, then retires the
---old shape next frame to prevent blinking.
---
---@param key string
---@param signature string
---@param build fun(): table|nil the mesh, nil when it could not be built
---@param x number translation
---@param y number
---@param z number
---@param colour integer
---@param free boolean true when build() costs no terrain samples, because the geometry already exists
---@return boolean drawn
local function drawShape(key, signature, build, x, y, z, colour, free)
    local entry = shapes[key]

    -- Keep the same shape if terrain loaded hasn't changed
    if entry ~= nil and entry.signature == signature and not terrainArrived(entry) then
        syncShape(entry, x, y, z, colour)
        return true
    end

    -- Don't build/show if the shape was tried but isn't ready for a retry
    if entry == nil and retryAt[key] ~= nil and frame < retryAt[key] then
        return false
    end

    -- If we've exceeded or hit our frame budget, don't rebuild but show it again
    -- with it's previous settings this frame if it exists. Skip this if free is true (built
    -- by a previous shape).
    if Mesh.samplesThisFrame() >= Draw.frameSampleBudget and not free then
        if entry == nil then return false end
        syncShape(entry, x, y, z, colour)
        return true
    end

    local mesh = build()
    local shape = mesh ~= nil and createInstance(mesh.finish()) or nil
    if shape == nil then
        if entry == nil then
            retryAt[key] = frame + Draw.retryFrames
            return false
        end
        -- Keep showing the old build for now
        syncShape(entry, x, y, z, colour)
        return true
    end

    -- Swap the new instance in. The old one draws until the next frame starts.
    if entry ~= nil then retiring[#retiring + 1] = entry.shape end
    entry = { shape = shape, signature = signature, mesh = mesh,
              recheckAt = #mesh.borrowed > 0 and frame + Draw.recheckFrames or nil }
    shapes[key] = entry
    retryAt[key] = nil
    syncShape(entry, x, y, z, colour)
    return true
end

---Marks the start of a frame draw. After this Draw.chunk is called,
---then Draw.endFrame to complete the draw cycle.
function Draw.beginFrame()
    frame = frame + 1
    Mesh.resetSamples()
    for _, shape in ipairs(retiring) do destroyShape(shape) end
    retiring = {}
end

---Draws everything needed in a specific chunk.
---
---The request variable specifies exactly what needs to be built and with
---what paremeters. The drawShape function then handles the actual drawing.
---@param request table {
---           level, chunk,
---           fillRGBA?, fillHeight?,
---           volumeRGBA?, volumeHeight?, outlineRGBA?, lineWidth?
---       }
---@return boolean drewSomething
function Draw.chunk(request)
    local level = request.level
    local chunk = request.chunk
    local originX, originZ = chunk:worldOrigin()
    local drew = false

    ---Used to share the box built between the ground and volume so we
    ---don't sample the ground twice.
    local boxMesh, boxBuilt = nil, false
    local function buildBoxOnce()
        if not boxBuilt then
            boxBuilt = true
            boxMesh = buildBox(level, chunk)
        end
        return boxMesh
    end

    ---Helper for building the box and handling lid height.
    local function box(name, colour, lid)
        if lid > Draw.BOX_REFERENCE_HEIGHT then lid = Draw.BOX_REFERENCE_HEIGHT end
        local key = string.format("%s:%d:%d", name, level, chunk.id)
        drew = drawShape(
            key, "box" .. Settings.get("boxSamples"),
            buildBoxOnce,
            originX, lid - Draw.BOX_REFERENCE_HEIGHT, originZ,
            colour, boxBuilt
        ) or drew
    end

    -- Draw the the ground fill volume/lid.
    if request.fillRGBA ~= nil and request.fillHeight > 0.0 then
        box("fill", request.fillRGBA, request.fillHeight)
    end

    -- Draw the tall volume.
    if request.volumeRGBA ~= nil then
        box("vol", request.volumeRGBA, request.volumeHeight)
    end

    -- Draw the outline, shapes get rebuilt on width changes
    if request.outlineRGBA ~= nil and request.lineWidth > 0.0 then
        local key = string.format("line:%d:%d", level, chunk.id)
        local width = request.lineWidth * UNITS_PER_LINE_WIDTH
        -- The ribbon's width and sampling are geometry, so both are in the signature.
        drew = drawShape(
            key, "w" .. width .. "s" .. Settings.get("lineSamples"),
            function() return buildOutline(level, chunk, width) end,
            originX, 0.0, originZ,
            request.outlineRGBA, false
        ) or drew
    end

    return drew
end

---Concludes the drawing process.
---@return integer reaped
function Draw.endFrame()
    local reaped = 0

    -- Destroy any shapes from previous frame drawings.
    for key, entry in pairs(shapes) do
        if entry.lastSeen ~= frame then
            destroyShape(entry.shape)
            shapes[key] = nil
            reaped = reaped + 1
        end
    end

    -- Get rid of retry timers that have expired.
    for key, at in pairs(retryAt) do
        if at <= frame then retryAt[key] = nil end
    end

    return reaped
end

---Destroy all the shapes and reset the drawing process.
function Draw.reset()
    for _, entry in pairs(shapes) do destroyShape(entry.shape) end
    for _, shape in ipairs(retiring) do destroyShape(shape) end
    shapes = {}
    retiring = {}
    retryAt = {}
    Mesh.resetSamples()
    frame = 0
end

---For testing the number of shapes built.
---@return integer
function Draw.liveCount()
    local count = 0
    for _ in pairs(shapes) do count = count + 1 end
    return count
end

---For testing number of samples we do per frame.
---@return integer
function Draw.samplesThisFrame() return Mesh.samplesThisFrame() end

return Draw
