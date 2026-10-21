## Game registry: what the shared menus and the LAN room need to know about each game.
## Keyed by game id ("ludo"), which menus pass along and the LAN room sends to joiners.
## "lan": the game can be played over the LAN room (menus hide "With friends" otherwise).
## "local": friends can pass one phone around (hidden-hand games can't).
## "faces": players are shown as cartoon faces, not pawns, and you don't pick a color.
## "variants": rule sets picked on a menu before the player count; the game gets `variant`.
## "rounds": match lengths offered on the rules menu (1 round, best of 3); the game gets `rounds`.

const LIST := {
	"ludo": {"title": "LUDO", "name": "Ludo", "scene": "res://games/ludo/ludo_game.tscn", "color": 0, "lan": true, "local": true, "faces": false},
	"snakes": {"title": "SNAKES & LADDERS", "name": "Snakes & Ladders", "scene": "res://games/snakes/snakes_game.tscn", "color": 1, "lan": true, "local": true, "faces": false},
	"cards": {"title": "COLOR CARDS", "name": "Color Cards", "scene": "res://games/cards/cards_game.tscn", "color": 3, "lan": true, "local": false, "faces": true},
	"carrom": {"title": "CARROM", "name": "Carrom", "scene": "res://games/carrom/carrom_game.tscn", "color": 2, "lan": true, "local": true, "faces": true, "variants": ["classic", "freestyle"]},
	"penfight": {"title": "PEN FIGHT", "name": "Pen Fight", "scene": "res://games/penfight/penfight_game.tscn", "color": 0, "lan": false, "local": true, "faces": true, "variants": ["turns", "realtime"], "rounds": [1, 3]},
}
const BOT_NAMES := ["Bot Rina", "Bot Max", "Bot Zoe", "Bot Leo"]
