-- Builds the panel for settings in the Plugin menu.
--
-- Most of the building for all the settings happens in settings_form.lua.

local Overlay = require("src/overlay")
local SettingsForm = require("src/ui/settings_form")
local State = require("src/state")

local ContentView = {}

local LABEL_WIDTH = 300
local LABEL_HEIGHT = 24
local VIEW_PADDING = 24
local SCROLLBAR_WIDTH = 16

---String for the current chunk as its Chunk Picker ID.
---@return string
local function chunkText()
    local chunk = Overlay.currentChunk()
    if chunk == nil then return "Current chunk: unavailable" end
    return string.format("Current chunk: %d", chunk:pickerID())
end

---String for the current number of chunks unlocked.
---@return string
local function countText()
    local count = State.count()
    if count == 1 then return "1 chunk unlocked" end
    return string.format("%d chunks unlocked", count)
end

---Builds the full settings panel in the Plugins menu (not plugin hub). Adds
---the basic info, then populates the rest of the menu with the settings.
---@param view table a PrettyUI SimpleView
---@param component table|nil the layer component the view was mounted into
---@return table handle { refresh = fun() }
function ContentView.build(view, component)
    view:AddTitle("Chunk Borders")

    -- The scroll bar is drawn over the content so a row sized to the padding
    -- runs underneath it and loses its right edge. Handle this hear by adjusting
    -- the width a bit.
    local contentWidth = component and component.width
        and component.width - VIEW_PADDING - SCROLLBAR_WIDTH or nil

    local chunkLabel = view:AddText({
        text = chunkText(),
        width = contentWidth or LABEL_WIDTH,
        height = LABEL_HEIGHT,
        maxLines = 1,
    })
    local countLabel = view:AddText({
        text = countText(),
        width = contentWidth or LABEL_WIDTH,
        height = LABEL_HEIGHT,
        maxLines = 1,
    })

    view:AddText({
        text = "Shift + right-click a chunk to unlock or lock it.",
        colour = 0xFFFFFFFF,
    })

    local handle = {}

    local form = SettingsForm.build(view, contentWidth)

    function handle.refresh()
        chunkLabel.content = chunkText()
        countLabel.content = countText()
        form.refresh()
    end

    return handle
end

return ContentView
