## Game registry: what the shared menus and the LAN room need to know about each game.
## Keyed by game id ("ludo"), which menus pass along and the LAN room sends to joiners.
## "lan": the game can be played over the LAN room (menus hide "With friends" otherwise).

const LIST := {
	"ludo": {"title": "LUDO", "scene": "res://games/ludo/ludo_game.tscn", "color": 0, "lan": true},
	"snakes": {"title": "SNAKES & LADDERS", "scene": "res://games/snakes/snakes_game.tscn", "color": 1, "lan": false},
}
const BOT_NAMES := ["Bot Rina", "Bot Max", "Bot Zoe", "Bot Leo"]
