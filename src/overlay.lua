-- Entry point for all the drawing. Handles all the settings and how they interact
-- with each other as well as setting up what needs to be drawn.
--
-- See draw.lua for more information on how the building and drawing happens.

local Chunk = require("src/chunk")
local Draw = require("src/draw")
local Overworld = require("src/overworld")
local Settings = require("src/settings")
local State = require("src/state")

local Overlay = {}

-- How big of a ring to grey out around the player
local VOLUME_RADIUS = 2

-- How low the ground lid can go underneath the camera
local FILL_MIN_LID = 0.5 * Chunk.UNITS_PER_TILE

---Helper to get the player's coords.
---@return table|nil
local function playerCoord()
    if not Player.IsAvailable() then return nil end
    local entity = Player.GetEntity()
    if entity == nil or entity.isValid == false then return nil end
    return entity.coordGrid
end

---Return the camera height if it's available.
---@return number|nil
local function cameraHeight()
    if not Camera.IsAvailable() then return nil end
    return Camera.GetPosition().y
end

---Helper to get ground height at a specific coord.
---@param coord table CoordGrid-like (absolute tile .x/.z, plus .level)
---@return number|nil
local function groundUnder(coord)
    local height, available = World.GetGroundHeight(
        coord.level or 0, coord.x * Chunk.UNITS_PER_TILE, coord.z * Chunk.UNITS_PER_TILE
    )
    if not available then return nil end
    return height
end

---Handles the height of the lid (or ground volume) underneath the camera. It's
---height changes according to the camera height.
---@param coord table the player's coordinate
---@param margin number how far below the camera to hold the lid, in world units
---@return number height, boolean tracking
local function fillHeightFor(coord, margin)
    local eye = cameraHeight()
    if eye == nil then return FILL_MIN_LID, false end
    local ground = groundUnder(coord)
    if ground == nil then return FILL_MIN_LID, false end

    -- Determine the height based on the settings and min/maxs
    local wanted = eye - ground - margin
    if wanted > Draw.BOX_REFERENCE_HEIGHT then wanted = Draw.BOX_REFERENCE_HEIGHT end
    if wanted < FILL_MIN_LID then wanted = FILL_MIN_LID end

    return wanted, true
end

---Absolute alpha rather than a multiplier of the colour's own, so that a
---strength of 1.0 means fully opaque.
---@param packedColour integer RGBA
---@param alpha number 0..1
---@return integer
local function atAlpha(packedColour, alpha)
    local scaled = math.floor(255 * alpha + 0.5)
    if scaled < 0 then scaled = 0 elseif scaled > 255 then scaled = 255 end
    return (packedColour & 0xFFFFFF00) | scaled
end

---Scales the colour's own alpha by the given opacity.
---@param packedColour integer RGBA
---@param alpha number 0..1
---@return integer
local function withOpacity(packedColour, alpha)
    return (packedColour & 0xFFFFFF00) | math.floor((packedColour & 0xFF) * alpha + 0.5)
end

-- When moving between areas like an underground and overworld area, multiple
-- checks can retun values that make the game seem fine but isn't. Using the
-- ground height under the camera we can tell if this is the case and trigger
-- a reset of all the shapes. Otherwise, we risk building the shapes for an
-- un-initialized world.
local STALE_RESET_FRAMES = 60
local staleFrames = 0
Overlay.staleResets = 0

function Overlay.resetTracking()
    staleFrames = 0
end

---Everything that happens inside one frame. Delegates the building and
---drawing to the draw.lua code. The summary is used for testing.
---@param summary table
---@return string|nil why nothing was drawn, or nil when the frame drew
local function drawFrame(summary)
    local markLocked = Settings.get("greyLocked")
    local showLines = Settings.get("showRegionLines")

    -- Nothing to draw if none of the draw settings are enabled
    if not markLocked and not showLines then return "nothing-enabled" end

    -- Nothing to draw if the player coordinate is unavailable
    local coord = playerCoord()
    if coord == nil then return "no-player" end

    -- Nothing to draw if we're not in the overworld
    local centre = Chunk.atTile(coord)
    if not Overworld.applies(centre, Settings.get("overworldDetection")) then
        return "off-map"
    end

    -- If the ground height under the camera is unavailable for some time, reset all the shapes.
    -- Used to prevent making shapes based on bad world data that then don't get displayed.
    if groundUnder(coord) == nil then
        staleFrames = staleFrames + 1
        if staleFrames % STALE_RESET_FRAMES == 0 then
            Draw.reset()
            Overlay.staleResets = Overlay.staleResets + 1
        end
    else
        staleFrames = 0
    end

    local level = coord.level or 0
    local radius = Settings.get("regionRadius")
    local opacity = Settings.get("lineOpacity")
    local lineWidth = Settings.get("lineThickness")

    local asVolume = Settings.get("lockedVolume")
    local volumeHeight = Settings.get("lockedVolumeTiles") * Chunk.UNITS_PER_TILE
    local strength = Settings.get("lockedVolumeOpacity")

    -- The ground volume lid always follows the camera height so that a locked
    -- chunk is greyed out under it. Otherwise if we end up inside the volume
    -- with the camera it looks like the chunk is unlocked.
    local fillHeight, tracking = fillHeightFor(
        coord, Settings.get("fillCameraMargin") * Chunk.UNITS_PER_TILE
    )
    summary.trackingCamera = tracking
    summary.fillHeight = fillHeight

    -- All the volumes we build use the same tint/alpha setting
    local tint = atAlpha(Settings.get("lockedColour"), strength)
    local outline = showLines
        and withOpacity(Settings.get("regionColour"), opacity) or nil

    -- When moving the camera into a locked chunk, the tall volume tints the
    -- full game view. This can be disabled with the Volume Gap setting to only
    -- have the the tall volumes drawn on chunks that don't border unlocked chunks.
    -- Here we check if the volume is allowed if the setting is enabled.
    local skipBordering = Settings.get("lockedVolumeSkipBorder")
    local function volumeAllowed(chunk, ring)
        if ring > 1 or not skipBordering then return true end
        for dx = -1, 1 do
            for dz = -1, 1 do
                if (dx ~= 0 or dz ~= 0) and State.isUnlockedChunk(chunk:neighbour(dx, dz)) then
                    return false
                end
            end
        end
        return true
    end

    -- Builds a request for everything a chunk needs drawn, then draws it. Handles all
    -- three parts of the drawing: ground fill/lid, tall volume, and grid lines.
    local function drawChunk(chunk, ring)
        -- Skip any unlocked chunks.
        local locked = markLocked and not State.isUnlockedChunk(chunk)
        if not locked and outline == nil then return end

        local request = { level = level, chunk = chunk }

        -- Specify the grey-out boxes
        if locked then
            request.fillRGBA = tint
            request.fillHeight = fillHeight
            if asVolume and ring <= VOLUME_RADIUS and volumeAllowed(chunk, ring) then
                -- Builds the tall volume above the ground fill/lid.
                request.volumeRGBA = tint
                request.volumeHeight = volumeHeight
            end
        end

        -- Specify the outline requested
        if outline ~= nil then
            request.outlineRGBA = outline
            request.lineWidth = lineWidth
        end

        -- Draw everything that was requested
        if Draw.chunk(request) then
            summary.drawn = summary.drawn + 1
            if locked then summary.filled = summary.filled + 1 end
        end
    end

    -- Nearest first, ring by ring. Because of the deferred draws from
    -- the frame budget, this lets us draw everything closest first.
    for ring = 0, radius do
        for dx = -ring, ring do
            for dz = -ring, ring do
                if math.max(math.abs(dx), math.abs(dz)) == ring then
                    drawChunk(centre:neighbour(dx, dz), ring)
                end
            end
        end
    end

    return nil
end

---Handles a single frame from start to finish. The return value is used for testing.
---@return table summary { drawn, filled, skipped, fillHeight, trackingCamera }
function Overlay.frame()
    local summary = { drawn = 0, filled = 0 }
    Draw.beginFrame()
    summary.skipped = drawFrame(summary)
    Draw.endFrame()
    return summary
end

---The chunk the player is standing in.
---@return table|nil chunk
function Overlay.currentChunk()
    local coord = playerCoord()
    if coord == nil then return nil end
    return Chunk.atTile(coord)
end

return Overlay
