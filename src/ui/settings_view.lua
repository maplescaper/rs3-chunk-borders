-- Used to direct users to the Plugins menu settings and provide
-- some guidance for settings.

local SettingsView = {}

---Builds the basic settings panel.
---@param view table a PrettyUI SimpleView
---@return table handle { refresh = fun(), destroy = fun() }
function SettingsView.build(view)
    view:AddTitle("Chunk Man")
    view:AddText({
        text = "Chunk Man's settings are in its own panel in the Plugins menu.",
    })

    view:AddText()
    view:AddText({
        text = "The current default settings are one recommended way of using the plugin.",
    })
    view:AddText()
    view:AddText({
        text = "Another way (depending on preference), can be by setting the Camera Margin " .. 
               "setting very high (e.g. 9000), then turning off the Tall Volumes. This " ..
               "results in a view where the ground is darkened but the sky isn't.",
    })

    return {
        refresh = function() end,
        destroy = function() end,
    }
end

return SettingsView
