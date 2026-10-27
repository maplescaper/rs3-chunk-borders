-- This builds the settings panel in the Plugins menu. The 
-- Settings are gathered from the groupings in settings.lua.

local Settings = require("src/settings")
local State = require("src/state")

local SettingsForm = {}

local FALLBACK_WIDTH = 220
local LABEL_HEIGHT = 24
local PICKER_SIZE = 32
local PICKER_WIDTH = PICKER_SIZE + 8
local RESET_WIDTH = 160
local STEP_WIDTH = 30
local COLUMN_GAP = 6
local NUMBER_LENGTH = 12
local TOOLTIP_WIDTH = 180

---Helper to format numbers.
---@param entry table
---@param value number
---@return string
local function numberText(entry, value)
    if entry.type == "int" then
        return string.format("%d", math.floor(value))
    end
    return string.format("%.2f", value)
end

---What a text field shows. The unlocked list is held as in-game chunk IDs
---but shown as Chunk Picker IDs, see state.lua.
---@param key string
---@return string
local function fieldText(key)
    if key == "unlockedChunkIds" then return State.pickerList() end
    return Settings.get(key)
end

---Use to prevent a value from exceeding requested max/mins.
---@param entry table
---@param value number
---@return number
local function clamp(entry, value)
    if entry.type == "int" then value = math.floor(value + 0.5) end
    if entry.min and value < entry.min then value = entry.min end
    if entry.max and value > entry.max then value = entry.max end
    return value
end

---Goes through the settings and builds the panel view for them.
---@param view table a PrettyUI SimpleView
---@param panelWidth number|nil
---@return table handle { refresh = fun() }
function SettingsForm.build(view, panelWidth)
    local labelWidth = panelWidth or FALLBACK_WIDTH
    local checkboxes = {}
    local numbers = {}
    local fields = {}
    local pickers = {}

    for _, group in ipairs(Settings.groups) do
        view:AddDivider()
        view:AddTitle(group.name)

        for _, entry in ipairs(group.entries) do
            local key = entry.key

            if entry.type == "bool" then
                -- Add simple boolean options as a checkbox
                checkboxes[key] = view:AddCheckboxButton({
                    {
                        text = entry.name,
                        value = key,
                        selected = Settings.get(key) == true,
                    },
                }, {
                    onChange = function(_, _, changed, selected)
                        Settings.set(changed, selected == true)
                    end,
                })
                checkboxes[key]:SetOptionTooltip(key, { text = entry.tooltip, maxWidth = TOOLTIP_WIDTH })

            elseif entry.type == "int" or entry.type == "float" then
                -- Add a text of the name with a selector for the value
                -- below it. In this case it's an input text field with +/-
                -- buttons on either side.
                view:AddText({
                    text = entry.name,
                    width = labelWidth,
                    height = LABEL_HEIGHT,
                    maxLines = 1,
                })

                local box
                local function apply(value)
                    Settings.set(key, clamp(entry, value))
                    box:SetText(numberText(entry, Settings.get(key)), false)
                end

                local step = entry.step or 1
                local boxWidth = labelWidth - 2 * (STEP_WIDTH + COLUMN_GAP)

                -- Make the - button
                view:AddSimpleButton("-", function()
                    apply(Settings.get(key) - step)
                end, { width = STEP_WIDTH, columnGap = COLUMN_GAP })

                -- Make the text input field
                box = view:AddTextField({
                    text = numberText(entry, Settings.get(key)),
                    width = boxWidth,
                    maxLength = NUMBER_LENGTH,
                    inline = true,
                    columnGap = COLUMN_GAP,
                    onSubmit = function(_, content)
                        local typed = tonumber(tostring(content or ""))
                        -- Anything that is not a number puts the stored value
                        -- back, rather than being taken as zero.
                        if typed == nil then
                            box:SetText(numberText(entry, Settings.get(key)), false)
                            return
                        end
                        apply(typed)
                    end,
                })
                box:SetTooltip({ text = entry.tooltip, maxWidth = TOOLTIP_WIDTH })

                -- Make the + button
                view:AddSimpleButton("+", function()
                    apply(Settings.get(key) + step)
                end, { width = STEP_WIDTH, inline = true })

                numbers[key] = { field = box, entry = entry }

            elseif entry.type == "text" then
                -- Add a text field that can be written in.
                view:AddText({
                    text = entry.name,
                    width = labelWidth,
                    height = LABEL_HEIGHT,
                    maxLines = 1,
                })

                -- Chunk IDs are typed as Chunk Picker IDs and need converting
                -- before being committed into the Settings.
                local commit = function(content)
                    if key == "unlockedChunkIds" then
                        State.commitList(content)
                    elseif key == "pasteChunkIds" then
                        State.pasteList(content)
                    else
                        Settings.set(key, tostring(content or ""))
                    end
                end

                fields[key] = view:AddTextField({
                    text = fieldText(key),
                    placeholder = entry.placeholder,
                    maxLength = entry.maxLength,
                    onSubmit = function(field, content)
                        commit(content)
                        field:SetText(fieldText(key), false)
                    end,
                })
                fields[key]:SetTooltip({ text = entry.tooltip, maxWidth = TOOLTIP_WIDTH })

            elseif entry.type == "colour" then
                -- Add text describing the colour to change with the colour picker inline
                -- at the right-end of the setting.
                view:AddText({
                    text = entry.name,
                    width = labelWidth - PICKER_WIDTH - COLUMN_GAP,
                    height = PICKER_SIZE,
                    maxLines = 1,
                    columnGap = COLUMN_GAP,
                })
                pickers[key] = view:AddColourPicker({
                    inline = true,
                    width = PICKER_WIDTH,
                    height = PICKER_SIZE,
                    value = Settings.get(key),
                    alphaSlider = true,
                    windowTitle = entry.name,
                    tooltip = { text = entry.tooltip, maxWidth = TOOLTIP_WIDTH },
                    onChange = function(_, colour)
                        Settings.set(key, colour)
                    end,
                })
            end
        end
    end

    local handle = {}

    view:AddDivider()
    local reset = view:AddSimpleButton("Reset to defaults", function()
        Settings.reset()
        handle.refresh()
    end, { width = RESET_WIDTH })
    reset:SetTooltip({ text = "Put every setting back to its default value.", maxWidth = TOOLTIP_WIDTH })

    -- Do refreshes here to update settings that may have been changed
    -- from elsewhere. Don't need callbacks in those cases.
    function handle.refresh()
        for key, widget in pairs(checkboxes) do
            widget:SetSelected(key, Settings.get(key) == true, false)
        end
        for key, number in pairs(numbers) do
            number.field:SetText(numberText(number.entry, Settings.get(key)), false)
        end
        for key, field in pairs(fields) do
            field:SetText(fieldText(key), false)
        end
        for key, picker in pairs(pickers) do
            picker:SetValue(Settings.get(key), false)
        end
    end

    return handle
end

return SettingsForm
