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
-- the draw cycle: Draw.BeginFrame, Draw.Chunk, and Draw.EndFrame. Overlay.frame
-- handles calling these. That budget is counted within the mesh.lua file.
--
-- The logic that handles the drawing, caching, and rebuilding for a chunk is
-- found in drawShape.

local Chunk = require("src/chunk")
local Mesh = require("src/mesh")
local Settings = require("src/settings")

local Draw = {}

local UNITS_PER_LINE_WIDTH = 32.0

-- Clearance given to the box and line so they don't flicker/collide with
-- the terrain. Causes flickering when moving the camera without this.
local BOX_CLEARANCE = 30.0
local LINE_CLEARANCE = BOX_CLEARANCE + 4.0

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

---Safe wrapper around the destroy shape call.
local function destroyShape(shape)
    pcall(function() shape:Destroy() end)
end

---Builds a mesh for a box/volume.
---@return table|nil mesh, whose finish() gives a new ShapeData each call
local function buildBox(level, chunk)
    local mesh = Mesh.new(level, chunk)
    local samples = Settings.get("boxSamples")
    local lidHeight = BOX_CLEARANCE + Draw.BOX_REFERENCE_HEIGHT

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
---@return table|nil
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

    for _, edge in ipairs(edges) do
        local offsetX, offsetZ = edge.acrossX * half, edge.acrossZ * half
        local previous
        local samples = Settings.get("lineSamples")
        for sample = 0, samples do
            local ratio = sample / samples
            local centreX = edge.fromX + (edge.toX - edge.fromX) * ratio
            local centreZ = edge.fromZ + (edge.toZ - edge.fromZ) * ratio
            local centreHeight = mesh.height(centreX, centreZ)
            if centreHeight == nil then return nil end

            -- One vertex either side of the centre line. Each incorporates the ground
            -- under itself so the line travels with the terrain.
            local leftX, leftZ = centreX + offsetX, centreZ + offsetZ
            local rightX, rightZ = centreX - offsetX, centreZ - offsetZ
            local leftHeight = mesh.height(leftX, leftZ) or centreHeight
            local rightHeight = mesh.height(rightX, rightZ) or centreHeight
            local left = mesh.vertex(leftX, leftHeight + LINE_CLEARANCE, leftZ)
            local right = mesh.vertex(rightX, rightHeight + LINE_CLEARANCE, rightZ)

            -- Build a line segment (quad) connected to the previous one
            if previous ~= nil then
                mesh.quad(previous, previous + 1, right, left)
            end

            previous = left
        end
    end

    return mesh.finish()
end

---Brings an existing shape in line with what this frame asks of it and
---marks it as seen so EndFrame keeps it.
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

---Draws one shape for this frame.
---
---Handles the full process. This includes skipping the build if the shape
---is in the cache, or if we've exceeded the frame budget. In that case, we
---show a previous build if it exists.
---
---Then we try building it, setup a retry if it fails, and finally cache the
---build so we can reuse it later. The syncShape method above handles both
---setting up a new build's parameters and updating an existing build.
---
---@param key string
---@param signature string
---@param build fun(): table|nil
---@param x number translation
---@param y number
---@param z number
---@param colour integer
---@param free (fun(): boolean)|nil true when build() costs no terrain samples
---@return boolean drawn
local function drawShape(key, signature, build, x, y, z, colour, free)
    local entry = shapes[key]

    -- If the shape already exists, show it again instead of building it
    if entry ~= nil and entry.signature == signature then
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
    if Mesh.samplesThisFrame() >= Draw.frameSampleBudget and not (free ~= nil and free()) then
        if entry == nil then return false end
        syncShape(entry, x, y, z, colour)
        return true
    end

    -- Build the shape now
    local shapeData = build()

    -- If the shape didn't get built
    if shapeData == nil then

        -- Setup up the retry if it's never been built
        if entry == nil then
            retryAt[key] = frame + Draw.retryFrames
            return false
        end

        -- Or show what it was before the rebuild for now
        syncShape(entry, x, y, z, colour)

        return true
    end

    -- Make an instance and cache for the shape if it doesn't have one yet.
    if entry == nil then
        serial = serial + 1
        local shape = ShapeList.CreateInstance(string.format("chunk_borders_%d", serial))
        if shape == nil then return false end
        entry = { shape = shape }
        shapes[key] = entry
    end

    -- Give it the new geometry.
    if not entry.shape:SetShapeData(shapeData) then
        destroyShape(entry.shape)
        shapes[key] = nil
        return false
    end

    -- Clear the entry settings to force syncShape to rewrite them with new settings.
    entry.shape.ignoreDepth = false
    entry.colour, entry.x, entry.y, entry.z = nil, nil, nil, nil

    -- The shape is current now, so sync it like any other.
    retryAt[key] = nil
    entry.signature = signature
    syncShape(entry, x, y, z, colour)

    return true
end

---Marks the start of a frame draw. After this Draw.Chunk is called,
---then Draw.EndFrame to complete the draw cycle.
function Draw.BeginFrame()
    frame = frame + 1
    Mesh.resetSamples()
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
function Draw.Chunk(request)
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
        if boxMesh == nil then return nil end
        return boxMesh.finish()
    end

    ---Helper for building the box and handling lid height.
    local function box(name, colour, lid)
        if lid > Draw.BOX_REFERENCE_HEIGHT then lid = Draw.BOX_REFERENCE_HEIGHT end
        local key = string.format("%s:%d:%d", name, level, chunk.id)
        drew = drawShape(
            key, "box" .. Settings.get("boxSamples"),
            buildBoxOnce,
            originX, lid - Draw.BOX_REFERENCE_HEIGHT, originZ,
            colour, function() return boxBuilt end
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
            request.outlineRGBA, nil
        ) or drew
    end

    return drew
end

---Concludes the drawing process.
---@return integer reaped
function Draw.EndFrame()
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
function Draw.Reset()
    for _, entry in pairs(shapes) do destroyShape(entry.shape) end
    shapes = {}
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
