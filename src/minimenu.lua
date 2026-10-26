-- Modifies the right-click menu to show an unlock/lock chunk option.
--
-- The entry is only shown when the menu was opened in the game view and
-- has a "Walk here" entry in the minimenu.

local Chunk = require("src/chunk")
local Overworld = require("src/overworld")
local Settings = require("src/settings")
local State = require("src/state")
local UI = require("src/ui/init")

local Minimenu = {}

local EVENT_ID = "chunk-borders-minimenu"

local started = false

---Checks if the Shift key is down.
---@return boolean
local function modifiersDown()
    return Keyboard.IsAvailable()
        and not Keyboard.IsBlocked()
        and Keyboard.IsShiftDown()
end

---Returns the cursor coordinate.
---@return table|nil coord
local function cursorCoord()
    if not Mouse.IsAvailable() then return nil end
    local position = Mouse.GetPosition()
    if position == nil then return nil end
    return ScreenConvert.ScreenToCoordGrid(position)
end

---Checks whether the menu was opened in the game view. Checks
---for "Walk here" to be in the menu for this so we don't show
---the option on unrelated interfaces.
---@param miniMenu table
---@return boolean
local function onGameWorld(miniMenu)
    local count = miniMenu.entryCount
    local entries = miniMenu.entries
    if count == nil or entries == nil then return false end

    for i = 1, count do
        local entry = entries[i]
        local entryText = entry and entry.verbText
        if entryText ~= nil and string.find(entryText, "Walk here", 1, true) then
            return true
        end
    end

    return false
end

---Toggles a chunk to either lock/unlock.
---@param chunk table
local function toggleChunk(chunk)
    if State.toggle(chunk) then
        UI.announceUnlock(chunk.id)
    end
end

---Add the lock/unlock entry to the minimenu.
---@param event table the MiniMenuReady event, carrying .miniMenu
local function onReady(event)
    local miniMenu = event.miniMenu
    if miniMenu == nil then return end
    if not modifiersDown() then return end
    if not onGameWorld(miniMenu) then return end

    -- Only chunks that can be locked/unlocked get an entry.
    local coord = cursorCoord()
    if coord == nil then return end
    local chunk = Chunk.atTile(coord)
    if not Overworld.applies(chunk, Settings.get("overworldDetection")) then return end

    local label = State.isUnlockedChunk(chunk)
        and string.format("Lock chunk %d", chunk.id)
        or string.format("Unlock chunk %d", chunk.id)

    miniMenu:Add(label, toggleChunk, chunk)
end

---Starts the minimenu.
function Minimenu.start()
    if started then return end
    started = true
    Event.MiniMenuReady.Subscribe(EVENT_ID, onReady)
end

---Shutsdown the minimenu.
function Minimenu.shutdown()
    if not started then return end
    started = false
    Event.MiniMenuReady.Unsubscribe(EVENT_ID)
end

return Minimenu
