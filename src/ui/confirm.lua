-- Used to show confirmation prompt when resetting the chunks.

local Library = require("src/ui/prettyui")

local Confirm = {}

local WIDTH = 416
local BUTTON_WIDTH = 184
local TEXT_HEIGHT = 48
local START_Y = 10
local PADDING = 12
local ROW_GAP = 8
local TITLE_HEIGHT = 32
local BORDER = 8
local BUTTON_HEIGHT = 27

-- Precomputed height to make everything fit in the prompt nicely
local HEIGHT = TITLE_HEIGHT + START_Y + TEXT_HEIGHT + ROW_GAP + BUTTON_HEIGHT + PADDING + BORDER

local PROMPT_LAYER = "TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP"

local prompt = nil

---Closes the prompt if one is open.
function Confirm.close()
    local open = prompt
    prompt = nil
    if open ~= nil and open.root ~= nil then open:Close() end
end

---Opens a centered prompt with the given options.
---@param options { title: string, text: string, confirmLabel: string, onConfirm: fun() }
function Confirm.show(options)
    -- Overwrite existing prompt with the new one
    if prompt ~= nil then
        Confirm.close()
    end

    -- Get the parent for the confirm prompt
    local componentID = id.Component[PROMPT_LAYER]
    local layer = componentID and ui.Interfaces:GetComponent(componentID)
    if layer == nil then
        return
    end

    -- Build the prompt
    local window
    window = Library.get().Window.new(layer, {
        title = options.title,
        x = -math.floor(WIDTH / 2),
        y = -math.floor(HEIGHT / 2),
        xAnchor = 0.5,
        yAnchor = 0.5,
        width = WIDTH,
        height = HEIGHT,
        minWidth = WIDTH,
        minHeight = HEIGHT,
        maxWidth = WIDTH,
        maxHeight = HEIGHT,
        destroyOnClose = true,
        onClose = function()
            if prompt == window then prompt = nil end
        end,
        layout = {
            startY = START_Y,
            paddingLeft = PADDING,
            paddingRight = PADDING,
            paddingBottom = PADDING,
            rowGap = ROW_GAP,
        },
    })
    prompt = window

    window:AddText({ text = options.text, height = TEXT_HEIGHT, maxLines = 2 })

    window:AddFancyButton(options.confirmLabel, function()
        Confirm.close()
        options.onConfirm()
    end, { width = BUTTON_WIDTH, variant = "negative" })

    window:AddFancyButton("Cancel", function()
        Confirm.close()
    end, { width = BUTTON_WIDTH, inline = true })
end

return Confirm
