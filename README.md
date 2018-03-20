# :gun: GLeague MatchMaking System - CS:GO
![Language: Sourcepawn](https://img.shields.io/badge/language-sourcepawn-green.svg) ![Sourcemod Plugin](https://img.shields.io/badge/sourcemod-plugin-green.svg)  ![Game: CS:GO](https://img.shields.io/badge/game-cs:go-green.svg) 

## Installation
Copy **translations** and **scripting** folders inside `\csgo\addons\sourcemod\`

**Dependencies:**
* **[Sourcemod 1.8+](https://www.sourcemod.net/downloads.php?branch=stable)**
* **[Metamod 1.10+](https://www.sourcemm.net/downloads.php?branch=stable)**

## How to use
Start your dedicated server with additional console argument `match_id`

**Example**
```
srcds.exe -game csgo -console -usercon -tickrate 128 -maxplayers_override 10 +game_type 0 +game_mode 1 +map de_dust2 -port 27015 -autoupdate +ip 0.0.0.0 +net_public_adr 0.0.0.0 +sv_lan 0 +sv_setsteamaccount "STEAM_TOKEN" +sv_region 3 match_id 1
```
