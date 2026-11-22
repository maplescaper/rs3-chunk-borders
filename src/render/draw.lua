-- Turns one chunk's draw request into shapes on screen.
--
-- Here, we take care of actually having those shapes built, caching them, and
-- retrying them if needed. The shapes themselves live in their own classes:
--      box.lua for the grey-out volumes (ground fill and tall volume)
--      outline.lua for the border line
-- Both are built from mesh.lua. The shapes made from them are kept between
-- frames in cache.lua. Shapes whose build failed are stored in retry.lua
-- before another try.
--
-- Note: Within a frame there is a budget of terrain samples to spend on building,
-- so that sudden shifts in the overworld (a teleport) fill in over a few frames
-- instead of one. Mesh counts the samples, and this module makes sure that the
-- building/drawing stays within the sampling budget.

local Box = require("src/render/box")
local Cache = require("src/render/cache")
local Mesh = require("src/render/mesh")
local Outline = require("src/render/outline")
local Retry = require("src/render/retry")

local Draw = {}

-- Budget that we have per frame to sample the map
Draw.frameSampleBudget = 4000

-- How long to wait before retrying build of a specific chunk
Draw.retryFrames = 12

-- How often to check whether terrain has loaded under a partially built shape
Draw.recheckFrames = 30

-- How many frames a retired shape stays to prevent blinking
Draw.retireFrames = 30

local cache = Cache.new()
local retries = Retry.new()
local frame = 0

-- Shapes being retired
local retiring = {}

-- Used for ShapeList instance names
local serial = 0

---Safe wrapper around the destroy shape call.
local function destroyShape(shape)
    pcall(function() shape:Destroy() end)
end

---Destroys the instances of a list of entries.
---@param entries table[]
local function destroyEntries(entries)
    for _, entry in ipairs(entries) do destroyShape(entry.shape) end
end

---Destroys the retiring entries if they're ready
local function destroyRetired()
    local held = {}
    for _, entry in ipairs(retiring) do
        if entry.retireAt <= frame then
            destroyShape(entry.shape)
        else
            held[#held + 1] = entry
        end
    end
    retiring = held
end

---Updates the shape with all settings, and marks it for keeping in the cache.
---@param entry table
---@param x number
---@param y number
---@param z number
---@param colour integer
local function updateAndKeepShape(entry, x, y, z, colour)
    local shape = entry.shape
    if entry.colour ~= colour then
        shape.colour = colour
        entry.colour = colour
    end
    if entry.x ~= x or entry.y ~= y or entry.z ~= z then
        shape.translation = Vector3.new(x, y, z)
        entry.x, entry.y, entry.z = x, y, z
    end
    cache:keep(entry, frame)
end

---Builds a new shape instance holding this geometry.
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
    return entry.mesh:terrainLoaded()
end

---Draws one shape for this frame.
---
---Shows the cached shape when there is one for the geometry's signature or
---when the frame budget is spent. Otherwise builds it, sets up a retry if
---that fails, and caches it. Rebuilds draw the new shape first, then
---retire the old shape.
---
---Note: Signature and key are similar, but signature is used to determine when
---a cached key should be rebuilt, while key holds the existing **built** shape
---for a specific chunk. This allows us to easily keep drawing an existing shape
---while we are waiting for a rebuild if we've already sampled too much.
---
---@param key string
---@param geometry table a Box or Outline: anything with :signature() and :build() -> mesh|nil
---@param x number translation
---@param y number
---@param z number
---@param colour integer
---@param alreadyBuilt boolean true when build() costs no terrain samples, because the geometry already exists
---@return boolean drawn
local function drawShape(key, geometry, x, y, z, colour, alreadyBuilt)
    local entry = cache:get(key)
    local signature = geometry:signature()

    -- Keep the same shape if terrain loaded hasn't changed
    if entry ~= nil and entry.signature == signature and not terrainArrived(entry) then
        updateAndKeepShape(entry, x, y, z, colour)
        return true
    end

    -- Don't build/show if the shape was tried but isn't ready for a retry
    if entry == nil and retries:waiting(key, frame) then
        return false
    end

    -- If we've exceeded or hit our frame budget, don't rebuild but show it again
    -- with it's previous settings this frame if it exists. Skip this if the geometry is
    -- already built (by a previous shape).
    if Mesh.samplesThisFrame() >= Draw.frameSampleBudget and not alreadyBuilt then
        if entry == nil then return false end
        updateAndKeepShape(entry, x, y, z, colour)
        return true
    end

    local mesh = geometry:build()
    local shape = mesh ~= nil and createInstance(mesh:finish()) or nil
    if shape == nil then
        if entry == nil then
            retries:defer(key, frame + Draw.retryFrames)
            return false
        end
        -- Keep showing the old build for now
        updateAndKeepShape(entry, x, y, z, colour)
        return true
    end

    -- Swap the new instance in. The old one keeps drawing for Draw.retireFrames.
    entry = {
        shape = shape, signature = signature, mesh = mesh,
        recheckAt = #mesh.borrowed > 0 and frame + Draw.recheckFrames or nil
    }

    local previous = cache:put(key, entry, frame)
    if previous ~= nil then
        previous.retireAt = frame + Draw.retireFrames
        retiring[#retiring + 1] = previous
    end

    retries:forget(key)
    updateAndKeepShape(entry, x, y, z, colour)

    return true
end

---Marks the start of a frame draw. After this Draw.drawChunk is called,
---then Draw.endFrame to complete the draw cycle.
function Draw.beginFrame()
    frame = frame + 1
    Mesh.resetSamples()
    destroyRetired()
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
function Draw.drawChunk(request)
    local level = request.level
    local chunk = request.chunk
    local originX, originZ = chunk:worldOrigin()
    local drew = false

    -- Build one box for both the ground fill and the tall volume to save on terrain samples
    local box = Box.new(level, chunk)

    -- Draw the the ground fill volume/lid
    if request.fillRGBA ~= nil and request.fillHeight > 0.0 then
        local key = string.format("fill:%d:%d", level, chunk.id)
        local y = Box.translationFor(request.fillHeight)
        local alreadyBuilt = box:built()
        drew = drawShape(key, box, originX, y, originZ, request.fillRGBA, alreadyBuilt) or drew
    end

    -- Draw the tall volume
    if request.volumeRGBA ~= nil then
        local key = string.format("vol:%d:%d", level, chunk.id)
        local y = Box.translationFor(request.volumeHeight)
        local alreadyBuilt = box:built()
        drew = drawShape(key, box, originX, y, originZ, request.volumeRGBA, alreadyBuilt) or drew
    end

    -- Draw the outline, shapes get rebuilt on width changes
    if request.outlineRGBA ~= nil and request.lineWidth > 0.0 then
        local key = string.format("line:%d:%d", level, chunk.id)
        local outline = Outline.new(level, chunk, request.lineWidth)
        drew = drawShape(key, outline, originX, 0.0, originZ, request.outlineRGBA, false) or drew
    end

    return drew
end

---Concludes the drawing process. Destroys shapes no longer needed.
---@return integer reaped
function Draw.endFrame()
    local evicted = cache:evict(frame)
    destroyEntries(evicted)
    retries:expire(frame)
    return #evicted
end

---Destroy all the shapes and reset the drawing process.
function Draw.reset()
    destroyEntries(cache:clear())
    destroyEntries(retiring)
    retiring = {}
    retries = Retry.new()
    Mesh.resetSamples()
    frame = 0
end

---For testing the number of shapes built.
---@return integer
function Draw.liveCount() return cache:count() end

return Draw
