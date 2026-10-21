## Game registry: what the shared menus and the LAN room need to know about each game.
## Keyed by game id ("ludo"), which menus pass along and the LAN room sends to joiners.
## "lan": the game can be played over the LAN room (menus hide "With friends" otherwise).
## "local": friends can pass one phone around (hidden-hand games can't).

const LIST := {
	"ludo": {"title": "LUDO", "name": "Ludo", "scene": "res://games/ludo/ludo_game.tscn", "color": 0, "lan": true, "local": true},
	"snakes": {"title": "SNAKES & LADDERS", "name": "Snakes & Ladders", "scene": "res://games/snakes/snakes_game.tscn", "color": 1, "lan": true, "local": true},
	"cards": {"title": "COLOR CARDS", "name": "Color Cards", "scene": "res://games/cards/cards_game.tscn", "color": 3, "lan": false, "local": false},
}
const BOT_NAMES := ["Bot Rina", "Bot Max", "Bot Zoe", "Bot Leo"]
