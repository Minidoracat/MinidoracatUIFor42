[h1]🎨 Minidoracat UI Library for B42[/h1]
[h3]By Minidoracat[/h3]

[hr][/hr]

[h2]✨ What is this[/h2]
Shared UI library for the Minidoracat mod series: themed color palettes (dark / light), rounded-corner window skins, shared monochrome icons, floating buttons, toast notifications and other reusable components.

This mod [b]does not add any gameplay content by itself[/b] — it is a base library used by other mods. Its visible effects depend entirely on the mods that use it.

[h2]👥 Who needs this[/h2]
[list]
[*] Subscribe only when another mod lists it under Required Items
[*] If none of your mods depend on it, you can leave it disabled
[/list]

[h2]🧰 What it provides (for mod developers)[/h2]
[list]
[*] [b]Theme system[/b]: token-based palettes with dark / light variants, per-mod overrides
[*] [b]Rounded skin[/b]: engine-native 9-slice rounded rendering with a safe rectangular fallback when textures are missing — windows never fail to open
[*] [b]Shared widgets[/b]: floating button (drag + position memory), toast notifications (shared stack across mods)
[*] [b]Shared painters[/b]: stateless pill, toggle, and slider visuals that dependent mods can compose without replacing their interaction logic; missing textures safely fall back to basic shapes
[*] [b]Shared icons[/b]: 20 monochrome line icons (sidebar, folder, document, expand/collapse, search, layers, pin, globe, lock, close, locate, copy, etc.) plus 13 solid silhouettes (house, skull, paw print, steering wheel and chicken/cow/pig/sheep/deer/rabbit/raccoon/rodent/turkey), tinted to match the active palette; callers fall back to their text markers when an icon asset is missing
[*] [b]Virtual list[/b]: large tables (trading/auction-style UIs) only build visible rows
[*] [b]Versioned API[/b]: dependent mods declare the API revision they need, so library updates never silently break them
[/list]

[h2]⚠️ Load order[/h2]
This mod must load [b]before any mod that depends on it[/b] (place it above them in your mod list).

[h2]🖥️ Multiplayer / Dedicated server[/h2]
Add it to both lines in your server ini:
[list]
[*] [b]Mods=[/b] MinidoracatUIFor42
[*] [b]WorkshopItems=[/b] 3789836701
[/list]

[h2]🔗 Mod series[/h2]
[list]
[*] [url=https://steamcommunity.com/sharedfiles/filedetails/?id=3763913359]Minidoracat MiniMap for B42[/url]
[*] [url=https://steamcommunity.com/sharedfiles/filedetails/?id=3789836823]Minidoracat Notice Board for B42[/url]
[/list]

[h2]📋 Mod info[/h2]
[list]
[*] [b]Workshop ID:[/b] 3789836701
[*] [b]Mod ID:[/b] MinidoracatUIFor42
[*] [b]Supported version:[/b] Build 42.20.1+
[*] [b]Singleplayer / Multiplayer:[/b] both supported
[/list]

[h2]💬 Feedback[/h2]
[list]
[*] [url=https://discord.gg/Gur2V67]Discord community[/url]
[/list]

[h2]☕ Support the author[/h2]
The mod is free and always will be. If you enjoy it, consider buying me a coffee - tips go straight into servers and mod development.
[url=https://ko-fi.com/minidoracat][img]https://raw.githubusercontent.com/Minidoracat/workshop-resources/refs/heads/main/badges/badge_kofi.png[/img][/url]

[b]#Minidoracat[/b]
