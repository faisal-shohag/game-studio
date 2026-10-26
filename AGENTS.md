# Repository Guidelines

## Project Structure & Module Organization

Game Studio is a portrait-oriented Godot project targeting Android; `project.godot` declares Godot 4.7. The entry scene is `ui/boot.tscn`.

- `core/`: shared services, game registry, avatars, QR utilities, and the `UI` and `Sfx` autoloads.
- `games/`: Ludo, Snakes, Cards, Carrom, and Pen Fight modules. Keep rules, AI, physics, scenes, and rendering within the relevant game directory; reusable game widgets belong in `games/shared/`.
- `ui/`: navigation, screens, icons, and boot logic.
- `assets/`: branding, fonts, and sound effects.
- `tests/`: rule tests, scene smoke tests, and LAN integration scripts.
- `build/`: ignored export output; `.godot/` is generated editor data.

## Build, Test, and Development Commands

Run these from the repository root with the matching Godot executable available as `godot`:

- `godot --editor --path .`: open the project and import assets.
- `godot --path .`: launch the application.
- `godot --headless --path . --script tests/test_pen_rules.gd`: run standalone rule and physics checks.
- `godot --headless --path . tests/run.tscn -- tests/smoke_penfight_game.gd`: run scene tests with autoloads initialized.
- `godot --headless --path . --export-debug "Android" build/game-studio.apk`: export a debug APK after configuring Android SDK paths and Godot export templates.

## Coding Style & Naming Conventions

Follow existing GDScript: tabs for indentation, `snake_case` filenames and functions, `UPPER_SNAKE_CASE` constants, and explicit types where useful. Use `res://` resource paths. Keep game rules independent of UI and networking, using plain state dictionaries. Preserve associated `.gd.uid` files. No dedicated formatter or linter configuration is present.

## Testing Guidelines

Tests use custom Godot assertions/check helpers, without an external framework or configured coverage threshold. Name standalone checks `test_*.gd` and scene checks `smoke_*_game.gd`; follow each script's usage header. Run affected rules and scene tests. For LAN changes, run `tests/net_game.gd host <game>` and `join <game>` through `tests/run.tscn` in separate processes; compare `FINAL` output and confirm `RESTARTED true`.

## Commit & Pull Request Guidelines

History uses short, descriptive subjects such as `Pen Fight: Turns mode offline`. Follow that feature-oriented style. PRs should explain behavior changes, identify affected modes, list validation commands and results, link relevant issues, and include screenshots or recordings for visual changes. Exclude generated caches and exported builds.