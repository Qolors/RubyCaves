# Ruby Caves (web build)

Turn-based 1v1 dungeon duel in a Doom-style 2.5D view, written in GDScript for **standard (non-.NET) Godot 4.7.2** so it can export to the browser.
This is a port of the C# prototype in `../RubyCaves`. The rules, bot and visuals behave the same.

## Run / test
- **Desktop:** open this folder in `Godot_v4.7.2-stable_win64.exe` (not the mono build) and press F5.
- **Rules test + bot sims:**
  `Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/rules_test.gd`
  Add `-- --quick` to skip the 3000-game soak and the flee-spam A/B sims.
- **Dev flags** (after `--`): `--bot=Top_SW:East[:idle]`, `--botplay=Wait,RetreatThrough`, `--play=MoveForward,Ambush,Attack`, `--shot=C:/path/shot.png`, `--shotmid=0.2`

## Web export
Web export templates for 4.7.2 must be installed (Editor → Manage Export Templates).

```
Godot_v4.7.2-stable_win64_console.exe --headless --path . --export-release "Web" build/web/index.html
```

- **Build size:** about 39 MB uncompressed, mostly the engine's `index.wasm`. Hosts that gzip or brotli-compress bring it to about 9–10 MB. The game data itself (`index.pck`) is about 260 KB.
- **Single-threaded export:** the preset has threads off, so no special COOP/COEP headers are needed and it runs on any static host, including itch.io and GitHub Pages.
- **Renderer:** Compatibility (WebGL 2). It works in current Chrome, Safari (iOS 15+) and Firefox.

### Quick local / same-Wi-Fi test
```
cd build/web
python -m http.server 8060 --bind 0.0.0.0
```
Open `http://localhost:8060` on this PC, or `http://<this PC's LAN IP>:8060` on a phone on the same Wi-Fi. Windows Firewall may ask to allow Python the first time.

### Public link for testers (pick one)
- **itch.io:** zip the *contents* of `build/web`, upload it as an HTML game, and tick "This file will be played in the browser" and "Mobile friendly". Leave SharedArrayBuffer off.
- **Netlify Drop / Cloudflare Pages:** drag the `build/web` folder in.
- **GitHub Pages:** push `build/web` to a `gh-pages` branch.

Any of these can sit behind your own `.io` domain.

## Layout
- `core/`: rules with no rendering: map graph, `DuelState` (turn resolution), `BotBrain`, actions and events. A headless Godot server can run these unchanged for multiplayer later.
- `game/`: `main.gd` (turn loop), `world_view.gd` (3D cells, billboard enemy, shadow vanish), `texture_factory.gd`, `dev_capture.gd`.
- `ui/`: HUD, octagon tabs, FPV sword, debug minimap.
- `data/figure8.json`: the map.
- `assets/sprites/`: generated from `art_src/*.jpg` by `tools/process_sprites.gd`. `art_src/` is excluded from the build.
- `assets/fonts/VT323-Regular.ttf`: the bundled pixel font (SIL OFL, see `OFL.txt`). Browsers can't use system fonts.

## Rules (prototype)
- Each turn lasts 10s. Both players lock in one action, then the actions play out at the same time.
- Moving into a corner rounds it for you automatically. At a T-junction, the forward button splits into `^ L` and `^ R`.
- You can only see straight ahead.
- **Ambush**: you are 1 tile from the enemy and looking at its back or side. The enemy takes 4 damage, its action is cancelled, and a conflict starts.
- **Conflict**: Attack beats Shove, Shove beats Guard, Guard beats Attack. Attack against Attack is a harmless clash. Fleeing (back, left, right or dash past) dodges all of those, but **Pursue** catches a flee. Any flee leaves you **winded** (no fleeing) for 3 turns. A fleer vanishes in shadow, so the direction is hidden.
- **Focus** (3 pips, both sides visible): Attack costs 2, Shove, Pursue and fleeing cost 1, Guard gives 1 back. Out of a conflict it refills 1 per turn. A fighter on 0–1 Focus can't attack, and on 0 can only Guard, so reading Focus tells you what's coming.
- Face-offs always put both fighters on one line. When a conflict breaks, nobody can ambush on the next turn (breakaway).
- Win: +30 rubies. Loss: −15 rubies. Rubies are saved in `user://profile.cfg`, which is browser storage on web.
