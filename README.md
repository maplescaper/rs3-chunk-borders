# Chunk Man

A Chunk Man plugin for Runescape to grey-out chunks/regions and draw chunk line boundaries in game. Similar functionality to the [Region Locker](https://github.com/slaytostay/region-locker) plugin in OSRS.

## Features

- **Chunk grid.** Border lines are drawn on the terrain along every chunk around the player.
- **Shaded locked chunks.** Chunks outside your unlocked list are tinted.
- **Unlock from the right-click menu.** Hold Shift and right-click a tile in the game world to get an `Unlock chunk` or `Lock chunk` entry for the chunk.
- **Unlock popups.** Unlocking a chunk shows a short achievement popup.
- **Chunk ID readout.** The plugin panel shows the ID of the chunk you are
  standing in and how many chunks are unlocked.
- **Chunk Picker lists.** Paste a list from the [RS3 Chunk Picker](https://source-chunk.github.io/chunk-picker-rs3) straight in.

## Settings

All settings live in the plugin panel in game (not the plugin hub). There are 3 sections in it at the moment:

- **Regions**. This holds settings for the regions unlocked, and settings around that.
- **Environment Looks**. This holds settings for how the shading works.
- **Advanced**. This holds settings that are for advanced use-cases.

See the [the settings file](src/settings.lua) for more information about each setting.

### Recommended Setup

The defaults provided should be enough for most. But depending on personal preferences another approach another approach could be to set it up as follows:

- Setting `Camera Margin` to a very high value like 5000.
- Disable `Tall Volumes`.

This will make the tint only visible on the ground. A drawback to this approach is that buildings/scenery/etc. won't be tinted anymore, but your camera also have a tinted view if you move it into a locked chunk.

There's also a `Volume Gap` setting that can be used to disable the tall volumes on chunks bordering unlocked chunks to prevent the camera tinting. However, this can result in the sky not being tinted at maximum view distances.

### Performance Settings

If you're facing any performance issues while using this plugin, the following settings can be helpful to tweak:

- `Chunk Radius` can be dropped lower (default is 2).
- `Border Samples` can be dropped lower (default is 8). This will have the plugin do less ground height samples when building the boxes that tint the locked chunks. The tint will be less accurate near the ground at lower values.
- `Line Samples` can be dropped lower (default is 64). This will have the plugin do less ground height samples when building the grid lines. At lower values, this will make the grid lines less accurate and potentially result in some clipping with scenery that will cause flickering.

## Requirements

Chunk Man depends on the **PrettyUI** plugin for its settings panel and popups. Enable it before enabling Chunk Man.

## Development

### Installation for Development

Place it under the client's `dev_plugins` directory like this:

```
C:\ProgramData\Jagex\RuneScape-BETA\dev_plugins\chunkman
```

Then enable it from the client's plugin hub menu alongside PrettyUI.

### Overview

Start by going through the [main.lua](src/main.lua) file for a quick understanding of how the plugin starts. From there, the main logic for drawing is found in [draw.lua](src/draw.lua) and is controlled from [overlay.lua](src/overlay.lua). There are descriptions at the top of each file that explain what their purpose is.

### Performance

When adding anything new that involves drawing, make sure that you **keep performance in mind**. If you're sampling anything in the game world (e.g. ground height), keep track of the samples and make sure it's incorporated into the `Draw` cycle like it is for the `Mesh`. Too many samples on fast game-world changes can cause issues. Also, be sure to make use of caching so we don't have to rebuild shapes that can be reused. The `Draw` cycle already has a caching system that can be reused.

### Limitations

The official API only allows us to draw shapes so we are quite limited in terms of what we can draw in game. This means that you will see some graphical oddities when using this plugin that cannot be overcome with what we currently have. While we are looking into improvements, shader support is likely what we will wait for to get us to where we want to be in terms of how tinting works.
