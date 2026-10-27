-- Sets up everything for the two UI components in the plugin hub, and 
-- the plugin menu. Wrapped with pcall's to better handle failures.
--
-- When resizing the settings panel, some significant lag started happening.
-- It looks like there's a leak somewhere in PrettyUI causing this and it's
-- more visible here because of the number of components we have. As a
-- workaround, we stop drawing the settings panel while the plugin menu is
-- being resized. An issue was filed on the PrettyUI repo about this.

local Confirm = require("src/ui/confirm")
local ContentView = require("src/ui/content_view")
local Library = require("src/ui/prettyui")
local Overlay = require("src/overlay")
local Settings = require("src/settings")
local SettingsView = require("src/ui/settings_view")

local UI = {}

local EVENT_ID = "chunk-borders-ui"
local SETTINGS_EVENT = "SettingsLayerReady"
local CONTENT_EVENT = "ContentLayerReady"

-- Draw subscription id used to defer content rebuilds.
local MOUNT_EVENT_ID = "chunk-borders-ui-mount"

local mounted = {
    settings = nil,
    content = nil,
}
local lastChunk = nil

-- Number of frames with no resize before we start drawing the settings again.
local QUIET_FRAMES = 10

local pendingContent = nil
local quietFrames = 0

---Releases/destroys a mounted component (slot).
---@param slot table|nil
local function release(slot)
    if slot == nil then return end
    if slot.view then slot.view:Destroy() end
end

---Mounts a UI component.
---@param name string "settings" | "content"
---@param component table
---@param build fun(view: table, component: table): table
local function mount(name, component, build)
    -- Destroy anything that was already in mounted
    release(mounted[name])
    mounted[name] = nil

    local view
    local ok, err = pcall(function()
        view = Library.get().SimpleView.new(component, {
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
        mounted[name] = nil
        if view then view:Destroy() end
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
    local chunk = Overlay.currentChunk()
    if chunk == lastChunk then return end
    lastChunk = chunk
    UI.refresh()
end

---The unlock celebration, for a chunk unlocked in game with Shift +
---right-click (uses the Chunk Picker ID).
---@param chunk table
function UI.announceUnlock(chunk)
    if Settings.get("showPopups") ~= true then return end
    if not Library.available() then return end
    pcall(function()
        Library.get().AchievementPopup.show({
            title = "Chunk unlocked",
            text = string.format("Chunk %d is now open.", chunk:pickerID()),
        })
    end)
end

---Refresh the UI when a setting changed.
local function onSettingChanged()
    UI.refresh()
end

---Runs each draw frame while a content rebuild is pending. It waits for the
---ContentLayerReady events to stop for a bit, then rebuilds.
---See note at the top of the file for more info about why.
local function onMountFrame()
    quietFrames = quietFrames + 1
    if quietFrames < QUIET_FRAMES then return end

    local component = pendingContent
    pendingContent = nil
    quietFrames = 0
    Event.Draw.Unsubscribe(MOUNT_EVENT_ID)

    mount("content", component, ContentView.build)
    lastChunk = Overlay.currentChunk()
end

---Schedules a component mount (to handle resizing issues). Resets quiet
---frames to 0 during resizes if there's a mount in progress.
---@param component table
local function scheduleContentMount(component)
    local alreadyWaiting = pendingContent ~= nil
    pendingContent = component
    quietFrames = 0
    if not alreadyWaiting then
        Event.Draw.Subscribe(MOUNT_EVENT_ID, onMountFrame)
    end
end

---Initialize the UI for the settings in the panel hub (settings)
---and the plugin menu (content).
function UI.init()
    Event[SETTINGS_EVENT].Subscribe(EVENT_ID, function(event)
        mount("settings", event.component, SettingsView.build)
    end)
    Event[CONTENT_EVENT].Subscribe(EVENT_ID, function(event)
        scheduleContentMount(event.component)
    end)

    return onSettingChanged
end

---Destroy all the components. Prompt stays open if we don't close it here
---as well.
function UI.unmount()
    -- Close any open prompt
    Confirm.close()

    -- Cancel any pending mount
    if pendingContent ~= nil then
        pendingContent = nil
        Event.Draw.Unsubscribe(MOUNT_EVENT_ID)
    end
    quietFrames = 0

    -- Destroy mounted components
    for name, slot in pairs(mounted) do
        release(slot)
        mounted[name] = nil
    end

    lastChunk = nil
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
