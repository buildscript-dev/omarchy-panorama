# Panorama for Omarchy

Panorama is a native Omarchy window overview for Hyprland. It presents live,
aspect-correct previews from the current workspace or from every workspace in a
compact, keyboard-friendly layout.

If you have used macOS Exposé or Mission Control, GNOME's Activities Overview,
or Windows Task View, Panorama provides the same kind of at-a-glance window
switching for Omarchy. It is an independent project and is not affiliated with
Apple, GNOME, or Microsoft.

It follows the active Omarchy theme, highlights the selected window with the
theme accent colour, dims and blurs every monitor, and switches workspaces when
you select a window elsewhere.

## Features

- Current-workspace and all-workspaces views
- Live window previews that preserve their real proportions
- Size-aware layout that gives larger windows more room
- Mouse and spatial keyboard navigation
- Application icons and workspace-aware labels
- Theme-derived colours, typography, spacing, and selection outline
- Multi-monitor dimming and blur
- Direct activation of windows on other workspaces

## Requirements

- Omarchy 4 with the `omarchy-shell` plugin system
- Quickshell 0.3 or newer
- Hyprland with toplevel-export support

Current Omarchy installations provide these components.

## Installation

Clone the repository into the user plugin directory, then validate and enable
it:

```bash
git clone https://github.com/aastrand/omarchy-panorama.git \
  ~/.config/omarchy/plugins/io.github.aastrand.panorama
omarchy plugin validate ~/.config/omarchy/plugins/io.github.aastrand.panorama
omarchy plugin enable io.github.aastrand.panorama
```

Until the upstream repository exists, copy this folder to the same destination
instead.

## Keybindings

Add the following to `~/.config/hypr/bindings.lua`:

```lua
o.bind("CTRL + UP", "Panorama all workspaces", "omarchy-shell shell toggle io.github.aastrand.panorama all")
o.bind("CTRL + DOWN", "Panorama current workspace", "omarchy-shell shell toggle io.github.aastrand.panorama current")
```

- `Ctrl+Up` shows windows from every workspace.
- `Ctrl+Down` shows windows from the current workspace.

You can also open either view directly:

```bash
omarchy-shell shell summon io.github.aastrand.panorama all
omarchy-shell shell summon io.github.aastrand.panorama current
```

## Background blur

Add this layer rule to `~/.config/hypr/hyprland.lua`. The active Omarchy theme
continues to control the blur strength:

```lua
hl.layer_rule({
  name = "panorama-background-blur",
  match = { namespace = "^io[.]github[.]aastrand[.]panorama([.]backdrop)?$" },
  blur = true,
  ignore_alpha = 0.1,
})
```

Reload Hyprland after changing the configuration:

```bash
hyprctl reload
hyprctl configerrors
```

## Controls

- Click a preview to activate that window.
- Use the arrow keys or `h`, `j`, `k`, and `l` to move the selection.
- Press `Enter` to activate the selected window.
- Press `Esc` or click the background to close Panorama.

## How it works

Panorama runs inside the existing `omarchy-shell` process. It uses Quickshell's
Hyprland model to enumerate windows and `ScreencopyView` to request live
per-window previews through Hyprland's toplevel-export protocol.

Capture is best-effort. If a client does not provide a capture handle, Panorama
keeps the window selectable using its application ID and title. It does not
write screenshots or preview caches to disk.

## Development

Validate the manifest after making changes:

```bash
omarchy plugin validate .
```

An installed plugin normally reloads automatically. To force rediscovery, run:

```bash
omarchy-shell shell rescanPlugins
```

Useful API references:

- [Omarchy shell plugins](https://github.com/basecamp/omarchy/blob/quattro/docs/omarchy-shell.md)
- [Quickshell HyprlandToplevel](https://master.quickshell.org/docs/types/Quickshell.Hyprland/HyprlandToplevel/)
- [Quickshell HyprlandWorkspace](https://master.quickshell.org/docs/types/Quickshell.Hyprland/HyprlandWorkspace/)
- [Quickshell ScreencopyView](https://master.quickshell.org/docs/types/Quickshell.Wayland/ScreencopyView/)

Exposé and Mission Control are trademarks of Apple Inc. Windows is a trademark
of Microsoft Corporation. Other names may be trademarks of their respective
owners.
