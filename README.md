# Plastic Command 0.26.1 — Mac lag patch

Copy these files over your existing **Godot 4.7.2** project (`PlasticCommand`), then export macOS the same way you made 0.26.

This is **not** a full game. Keep your `assets/` folder.

## Download zip

https://github.com/stekbrit/plastic-command-0.26.1-lag-patch/archive/refs/heads/main.zip

## What it changes

- Turns **Balanced** graphics on once (0.26 saved High, which hitchs)
- Regular soldiers no longer cast shadows
- Off-screen units skip animation / dust / flashes
- Distant IK updates less often
- Balanced: no glow, 2 shadow cascades
- Debris cap 80, closer FX culling

Gameplay, armies, saves, LAN protocol 20: unchanged.

## Install

1. Quit the game
2. Copy over `Documents/ChatGPT/Soldier Game/PlasticCommand`:
   - `project.godot`
   - `scripts/battle.gd`
   - `scripts/hud.gd`
   - `scripts/world_view.gd`
   - `scripts/plastic_surfaces.gd`
   - `scripts/plastic_debris.gd`
   - `scripts/combat_fx.gd`
3. Open in Godot 4.7.2 → **Project → Export → macOS**
4. Play **20 vs 20** for the smoother match. FPS is under the clock.

See `HOW TO INSTALL.txt` for the same steps.
