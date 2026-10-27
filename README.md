# Ruby Caves (web build)

Turn-based 1v1 dungeon duel in a Doom-style 2.5D view, written in GDScript for **standard (non-.NET) Godot 4.7.2** so it can export to the browser.
This is a port of the C# prototype in `../RubyCaves`. The rules, bot and visuals behave the same.

## Run / test
- **Desktop:** open this folder in `Godot_v4.7.2-stable_win64.exe` (not the mono build) and press F5.
- **Rules test + bot sims:**
  `Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/rules_test.gd`
  Add `-- --quick` to skip the 3000-game soak and the flee-spam / Footing A/B sims.
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
- `assets/sprites/`: enemy idle strips (front, rear, left, right; 8 frames each), packed from `art_src/Enemy/<dir>/frame_*.png` by `tools/process_sprites.gd`. `art_src/` is excluded from the build.
- `assets/fonts/VT323-Regular.ttf`: the bundled pixel font (SIL OFL, see `OFL.txt`). Browsers can't use system fonts.

## Rules (prototype)
- Each turn lasts 10s. Both players lock in one action, then the actions play out at the same time.
- Moving into a corner rounds it for you automatically. At a T-junction, the forward button splits into `^ L` and `^ R`.
- You can only see straight ahead.
- **Ambush**: you are 1 tile from the enemy and looking at its back or side. The enemy takes 4 damage, its action is cancelled, and a conflict starts.
- **Conflict**: Attack beats Shove, Shove beats Guard, Guard beats Attack. Fleeing (back, left, right or dash past) dodges Guard and Shove, but an **Attack catches a flee**: the attacker follows, hits, and the fight goes on. Any flee leaves you **winded** (no fleeing) for 3 turns. A fleer vanishes in shadow, so the direction is hidden.
- **Initiative**: landing an ambush or winning an exchange (a hit, a block, a shove that lands, catching a flee) gives you the initiative. In Attack vs Attack the holder wins; with nobody holding it they clash harmlessly. A stalemate (Guard/Guard, Shove/Shove, a clash) or the end of the conflict clears it, so a neutral meeting starts with nobody holding it.
- **Footing** (0-3 pips, both sides visible): Attack, Shove and fleeing cost 1. Guard gives 1 back; guarding a real attack gives 2 and strips 1 from the attacker. A Shove that lands on a Guard refunds its pip. Out of a conflict, standing still or turning recovers 2, moving recovers 1. Shove and fleeing need the pip to pay for them.
- **Exhausted** (0 Footing): your Attack is Telegraphed (half damage, and a Guard punishes it for 1 chip damage). Your Guard has a 50% chance to shatter under a normal attack: you take half damage and are stunned.
- **Guard**: when it holds (not shattered, not shoved), your next action costs 0 Footing. When sharing a tile you can also guard with a reposition (`< GUARD` / `GUARD >`): you turn 90 degrees that way and the enemy squares up opposite, putting its back where you're now facing.
- **Shove**: deals 1. If there's a wall behind the enemy, it is pinned and stunned for a turn and the fight stays in the tile. If there's room, it is shoved into the next tile and the conflict breaks. Shoving an already-stunned enemy can't stun it again.
- Face-offs always put both fighters on one line. When a conflict breaks, nobody can ambush on the next turn (breakaway).
- Win: +30 rubies. Loss: −15 rubies. Rubies are saved in `user://profile.cfg`, which is browser storage on web.
