-- Sets up everything for the two UI components in the plugin hub, and 
-- the plugin menu. Wrapped with pcall's to better handle failures.

local ContentView = require("src/ui/content_view")
local Library = require("src/ui/prettyui")
local Overlay = require("src/overlay")
local Settings = require("src/settings")
local SettingsView = require("src/ui/settings_view")

local UI = {}

local EVENT_ID = "chunkman-ui"
local SETTINGS_EVENT = "SettingsLayerReady"
local CONTENT_EVENT = "ContentLayerReady"

local mounted = {
    settings = nil,
    content = nil,
}
local lastChunkID = nil

---Releases/destroys a mounted component (slot).
---@param slot table|nil
local function release(slot)
    if slot == nil then return end
    if slot.handle then pcall(slot.handle.destroy) end
    if slot.view then pcall(function() slot.view:Destroy() end) end
end

---Mounts a UI component.
---@param name string "settings" | "content"
---@param component table
---@param build fun(view: table, component: table): table
local function mount(name, component, build)
    -- Destroy anything that was already in mounted
    release(mounted[name])
    mounted[name] = nil

    local ok = pcall(function()
        local view = Library.get().SimpleView.new(component, {
            width = component.width,
            height = component.height,
            scrollable = true,
            layout = {
                startY = 10,
                paddingLeft = 12,
                paddingRight = 12,
                rowGap = 8,
            },
        })
        mounted[name] = { view = view, handle = build(view, component) }
    end)

    if not ok then
        release(mounted[name])
        mounted[name] = nil
    end
end

---Handles refreshing each mounted component.
function UI.refresh()
    for _, slot in pairs(mounted) do
        if slot ~= nil and slot.handle ~= nil then
            pcall(slot.handle.refresh)
        end
    end
end

---Only touches the UI when the player's chunk actually changed.
function UI.tick()
    if mounted.content == nil then return end
    local id = Overlay.currentChunkID()
    if id == lastChunkID then return end
    lastChunkID = id
    UI.refresh()
end

---The unlock celebration, for a chunk unlocked in game with Shift +
---right-click.
---@param id integer
function UI.announceUnlock(id)
    if Settings.get("showPopups") ~= true then return end
    if not Library.available() then return end
    pcall(function()
        Library.get().AchievementPopup.show({
            title = "Chunk unlocked",
            text = string.format("Chunk %d is now open.", id),
        })
    end)
end

---Refresh the UI when a setting changed.
local function onSettingChanged()
    UI.refresh()
end

---Initialize the UI for the settings in the panel hub (settings)
---and the plugin menu (content).
function UI.init()
    Event[SETTINGS_EVENT].Subscribe(EVENT_ID, function(event)
        mount("settings", event.component, SettingsView.build)
    end)
    Event[CONTENT_EVENT].Subscribe(EVENT_ID, function(event)
        mount("content", event.component, ContentView.build)
        lastChunkID = Overlay.currentChunkID()
    end)

    return onSettingChanged
end

---Destroy all the components.
function UI.unmount()
    for name, slot in pairs(mounted) do
        release(slot)
        mounted[name] = nil
    end
    lastChunkID = nil
end

---Handles destroying the UI.
function UI.shutdown()
    Event[SETTINGS_EVENT].Unsubscribe(EVENT_ID)
    Event[CONTENT_EVENT].Unsubscribe(EVENT_ID)
    UI.unmount()
end

---@return boolean settingsMounted, boolean contentMounted, boolean dependencyReady
function UI.state()
    return mounted.settings ~= nil, mounted.content ~= nil, Library.available()
end

return UI
