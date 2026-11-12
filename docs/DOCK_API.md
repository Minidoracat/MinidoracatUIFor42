# Add your mod to the Minidoracat toolbar

The Minidoracat UI Library (Workshop `3789836701`, Mod ID `MinidoracatUIFor42`) draws one toolbar for all
Minidoracat mods. Any other mod may add an entry to it. You do not need to ask, and you may publish the result.

One entry is one 40 x 40 button with your icon. A click calls your function.

## Minimal example

```lua
local function addToToolbar()
    local UI = MinidoracatUI and MinidoracatUI.v1
    if not (UI and UI.API_MAJOR == 1 and UI.CAPABILITIES.dock and UI.Dock) then return end
    UI.Dock.register({
        id = "YourModID",
        order = 1000,
        label = function() return getText("IGUI_YourMod_Name") end,
        icon = "media/ui/YourMod/icon.png",
        onClick = function() YourMod.toggleWindow() end,
    })
end
Events.OnGameStart.Add(addToToolbar)
```

Put this in a client Lua file (`media/lua/client/`). If the UI Library is not enabled, the function returns
and your mod works as before.

## Required fields

| Field | Type | Meaning |
|---|---|---|
| `id` | string | Use your Mod ID. One id is one entry. If you register the same id again, the new entry replaces the old one. |
| `order` | number | Use 1000 or more. Minidoracat mods use 10 to 100. A lower number is nearer the handle. |
| `label` | function | Returns the name. Players see it in the tooltip and in the toolbar settings. |
| `onClick` | function | Called with your spec table when the player activates the entry (mouse, Enter, or joypad A). Open or close your window here. |
| an icon | | Give `icon`, `iconKey` or `drawIcon`. See below. |

## Icon

The toolbar draws the icon at 28 x 28. Give at least one of these. If you give more, the toolbar uses the
first one that works, in this sequence:

1. `icon` (string): a texture path in your mod, for example `media/ui/YourMod/icon.png`. It keeps its colours.
   A square PNG with a transparent background works best. The toolbar scales it to 28 x 28.
2. `iconKey` (string): the key of an icon that the UI Library supplies. It takes the colour of the theme text.
3. `drawIcon(element, x, y, size, alpha)` (function): you draw the icon yourself, on `element`, in the square
   at `x`, `y` with side `size`. Multiply your alpha by `alpha`. API revision 26 and earlier pass no `alpha`:
   use `alpha or 1`. The toolbar settings window calls the same function with a smaller `size`, so always
   use the `x`, `y` and `size` that you get.

## Optional fields

| Field | Type | Meaning |
|---|---|---|
| `getStatus` | function | Returns a string for the second line of the tooltip. It can have more than one line. |
| `getBadge` | function | Returns a number. More than 0 shows the number on the entry. `-1` shows a red dot. |
| `getState` | function | Returns `nil`, `"on"` (accent frame) or `"warn"` (red frame). |
| `isActive` | function | Returns `true` while your window is open. The entry shows as selected. |
| `isAvailable` | function | Returns `false` to remove the entry for now, for example when the server disables your feature. |
| `onRightClick` | function | Called with your spec table when the player right-clicks the entry. |
| `bind` | string | The name of your key binding. The tooltip shows the key. |

The toolbar can call these functions on each frame. Keep them fast: read a cached value, and do not create
tables. The toolbar catches errors in them. A field with the wrong type makes `register` fail.

## When register returns false

`register` does not throw. It returns `true`, or `false` when the spec is not valid. From API revision 27 it
also returns the reason:

```lua
local ok, why = UI.Dock.register(spec)
if not ok then print("[YourMod] toolbar: " .. tostring(why)) end
```

## Players stay in control

From API revision 27 (`UI.CAPABILITIES.dockPrefs`), players select the entries that the toolbar shows:
right-click the toolbar handle, then select "Toolbar settings...". The UI Library saves this selection.
You do not need an option of your own to hide your entry.

`UI.Dock.isDocked(id)` stays `true` for an entry that the player hides there. If you show a button of
your own when `isDocked` is `false`, that button does not come back.

## Dependency and load order

- Without `require=`: use the example as it is. `OnGameStart` runs after all mods have loaded, so the load
  order does not matter.
- With `require=MinidoracatUIFor42` in your `mod.info`: the game loads the UI Library first, and you can call
  `register` when your file loads. Add the UI Library to the Required Items of your Workshop page, and do not
  set your `versionMin` lower than the `versionMin` of the UI Library.

## Other functions

| Function | Meaning |
|---|---|
| `UI.Dock.unregister(id)` | Removes your entry. |
| `UI.Dock.refresh()` | Makes the toolbar read `isAvailable` again immediately. It also reads it 4 times each second. |
| `UI.Dock.isDocked(id)` | `true` when your entry is registered and available, and the toolbar exists. |

## Compatibility

The API is versioned. Within `API_MAJOR == 1` the UI Library only adds things: an entry that works today
continues to work. Do not read or change other fields of `MinidoracatUI`; they can change.

Questions and problems: https://github.com/Minidoracat/MinidoracatUIFor42/issues
