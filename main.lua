local Settings = require("src/settings")
local State = require("src/state")
local Draw = require("src/draw")
local Overlay = require("src/overlay")
local Minimenu = require("src/minimenu")
local UI = require("src/ui/init")

local EVENT_ID = "chunk-borders"

-- Initialize everything starting with the settings and chunk state.
Settings.load()
State.init()

-- Setup the minimenu and UI.
Minimenu.start()
local onSettingChanged = UI.init()

-- Subscribe to events.
Settings.subscribe("*", onSettingChanged)

Event.Draw.Subscribe(EVENT_ID, function()
    -- Draws the actual chunks.
    Overlay.frame()
    UI.tick()
end)

Event.GameStateChanged.Subscribe(EVENT_ID, function(event)
    -- If we're not in game, reset everything.
    if event.newState ~= GameState.GAME then
        Draw.Reset()
        Overlay.resetTracking()
        UI.unmount()
    end
end)

---Handle the plugin shutdown and cleanup.
function PluginShutdown()
    Event.Draw.Unsubscribe(EVENT_ID)
    Event.GameStateChanged.Unsubscribe(EVENT_ID)
    Settings.subscribe("*", nil)
    Minimenu.shutdown()
    UI.shutdown()
    Draw.Reset()
end
