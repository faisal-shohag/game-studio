## Run: godot --headless --path . --script tests/test_cards_rules.gd
extends SceneTree

const Rules = preload("res://games/cards/cards_rules.gd")
const Ai = preload("res://games/cards/cards_ai.gd")
const R := 0
const G := 1
const Y := 2
const B := 3

var fails := 0


func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		printerr("FAIL: ", what)


## The nth physical card of this color and kind (color -1 for wilds).
func card(col: int, kind: int, nth := 0) -> int:
	for id in Rules.DECK.size():
		if Rules.DECK[id] == [col, kind]:
			if nth == 0:
				return id
			nth -= 1
	return -1


## A game with chosen hands and top card; the pile holds `pile` (top = back) or the default rest.
func table(colors: Array, top: int, hands: Dictionary, pile = null) -> Dictionary:
	var s := Rules.new_state(colors, range(108))
	for c in hands:
		s.hands[c] = hands[c].duplicate()
	s.discard = [top]
	s.top_color = Rules.color_of(top)
	if pile != null:
		s.pile = pile.duplicate()
	return s


func plays(s: Dictionary) -> Array:
	return Rules.legal(s, s.hands[s.turn]).filter(func(a): return a.do == "play").map(func(a): return a.id)


func act(s: Dictionary, c: int, what: String, id := -1, col := -1) -> Dictionary:
	if what == "play" and col == -1:
		col = Rules.color_of(id)
	return Rules.apply(s, c, {"do": what, "id": id, "color": col})


func total(s: Dictionary) -> int:
	var n: int = s.pile.size() + s.discard.size()
	for c in s.colors:
		n += s.hands[c].size()
	return n


func _init() -> void:
	# --- deck and deal ---
	check(Rules.DECK.size() == 108, "108 cards")
	for col in 4:
		check(Rules.DECK.count([col, 0]) == 1, "one 0 per color")
		for k in range(1, Rules.WILD):
			check(Rules.DECK.count([col, k]) == 2, "two of kind %d in color %d" % [k, col])
	check(Rules.DECK.count([-1, Rules.WILD]) == 4 and Rules.DECK.count([-1, Rules.WILD4]) == 4, "4 wilds, 4 wild +4s")

	var order := range(108)
	order.shuffle()
	var s := Rules.new_state([0, 1, 2, 3], order)
	check(s.colors.all(func(c): return s.hands[c].size() == 7), "7 cards each")
	check(s.discard.size() == 1 and Rules.kind_of(s.discard[0]) <= 9, "first discard is a number")
	check(s.top_color == Rules.color_of(s.discard[0]) and s.turn == 0 and s.phase == "play", "start state")
	check(total(s) == 108 and s.pile.size() == 108 - 28 - 1, "deal keeps every card")

	order = range(108)  # 2 players deal 14 off the back; then a +4 and a +2 come up
	order[93] = card(-1, Rules.WILD4)
	order[order.find(card(-1, Rules.WILD4), 94)] = 93
	order[92] = card(R, Rules.DRAW2)
	order[card(R, Rules.DRAW2)] = 92
	s = Rules.new_state([0, 2], order)
	check(s.discard == [91] and s.pile[0] == card(R, Rules.DRAW2) and s.pile[1] == card(-1, Rules.WILD4), "action cards re-flipped to the bottom")

	# --- matching ---
	var red5 := card(R, 5)
	s = table([0, 1], red5, {0: [card(G, 5), card(R, 2), card(B, 7), card(-1, Rules.WILD)]})
	var p := plays(s)
	check(card(G, 5) in p and card(R, 2) in p and not card(B, 7) in p, "match color or number")
	check(p.count(card(-1, Rules.WILD)) == 4, "a wild is offered once per color")
	var ev := act(s, 0, "play", card(-1, Rules.WILD), B)
	check(ev.top_color == B and s.top_color == B and s.turn == 1, "wild sets the color")
	s.hands[1] = [card(B, 9), card(R, 5, 1)]
	check(plays(s) == [card(B, 9)], "must follow the wild's color")

	s = table([0, 1], card(R, Rules.SKIP), {0: [card(G, Rules.SKIP), card(G, 3)]})
	check(plays(s) == [card(G, Rules.SKIP)], "symbols match symbols")

	# --- skip and reverse ---
	s = table([0, 1, 2], red5, {0: [card(R, Rules.SKIP), card(G, 1)]})
	ev = act(s, 0, "play", card(R, Rules.SKIP))
	check(ev.skipped == 1 and s.turn == 2, "skip")
	s = table([0, 1, 2], red5, {0: [card(R, Rules.REVERSE), card(G, 1)]})
	ev = act(s, 0, "play", card(R, Rules.REVERSE))
	check(ev.reversed and s.dir == -1 and s.turn == 2, "reverse")
	s.hands[2] = [card(R, 1), card(G, 2)]
	act(s, 2, "play", card(R, 1))
	check(s.turn == 1, "play goes on backwards")
	s = table([0, 1], red5, {0: [card(R, Rules.REVERSE), card(G, 1)]})
	ev = act(s, 0, "play", card(R, Rules.REVERSE))
	check(s.turn == 0 and ev.skipped == 1, "2 players: reverse acts as skip")

	# --- +2 / +4 stacking ---
	s = table([0, 1, 2], red5, {0: [card(R, Rules.DRAW2), card(G, 1)],
		1: [card(G, Rules.DRAW2), card(R, 2), card(-1, Rules.WILD)],
		2: [card(-1, Rules.WILD4), card(Y, Rules.DRAW2, 1), card(R, 3)]})
	act(s, 0, "play", card(R, Rules.DRAW2))
	check(s.pending == 2 and s.turn == 1, "+2 stacks up")
	check(plays(s) == [card(G, Rules.DRAW2)], "under a +2 only a +2 plays")
	act(s, 1, "play", card(G, Rules.DRAW2))
	check(s.pending == 4 and s.turn == 2, "+2 on +2")
	check(act(s, 2, "play", card(-1, Rules.WILD4), R).is_empty(), "no +4 on a +2")
	ev = act(s, 2, "play", card(Y, Rules.DRAW2, 1))
	check(not ev.is_empty() and s.pending == 6 and s.turn == 0, "any color +2 stacks")
	var before: int = s.hands[0].size()
	ev = act(s, 0, "draw")
	check(ev.stack and ev.n == 6 and s.hands[0].size() == before + 6, "draw takes the whole stack")
	check(s.pending == 0 and s.turn == 1 and s.phase == "play", "and loses the turn")

	s = table([0, 1], red5, {0: [card(-1, Rules.WILD4), card(G, 1)],
		1: [card(-1, Rules.WILD4, 1), card(R, Rules.DRAW2), card(R, 1)]})
	act(s, 0, "play", card(-1, Rules.WILD4), G)
	check(plays(s).all(func(id): return id == card(-1, Rules.WILD4, 1)), "under a +4 only a +4 plays")
	act(s, 1, "play", card(-1, Rules.WILD4, 1), Y)
	check(s.pending == 8 and s.pending_kind == Rules.WILD4 and s.top_color == Y, "+4 on +4")

	# --- draw 1, may play it ---
	s = table([0, 1], red5, {0: [card(B, 7), card(G, 1)]}, [card(B, 2), card(R, 8)])
	check(plays(s).is_empty(), "nothing to play")
	ev = act(s, 0, "draw")
	check(ev.n == 1 and ev.can_play and s.phase == "drawn" and s.turn == 0, "drew a playable card")
	check(plays(s) == [card(R, 8)] and Rules.legal(s, s.hands[0]).back().do == "pass", "may play it or pass")
	check(act(s, 0, "draw").is_empty() and act(s, 0, "play", card(B, 7)).is_empty(), "no second draw, no other card")
	act(s, 0, "play", card(R, 8))
	check(s.turn == 1 and s.phase == "play" and s.hands[0].size() == 2, "played the drawn card")

	s = table([0, 1], red5, {0: [card(B, 7), card(G, 1)]}, [card(B, 2), card(R, 8)])
	act(s, 0, "draw")
	ev = act(s, 0, "pass")
	check(ev.do == "pass" and s.turn == 1 and s.hands[0].size() == 3, "pass keeps the drawn card")

	s = table([0, 1], red5, {0: [card(B, 7), card(G, 1)]}, [card(B, 2), card(G, 8)])
	ev = act(s, 0, "draw")
	check(not ev.can_play and s.turn == 1 and s.phase == "play", "unplayable draw passes by itself")

	s = table([0, 1], red5, {0: [card(R, 1), card(G, 1)]}, [card(B, 2), card(G, 8)])
	act(s, 0, "draw")
	check(s.turn == 1, "may draw while holding a playable card")

	# --- illegal actions ---
	s = table([0, 1, 2], red5, {0: [card(R, 1), card(B, 1), card(-1, Rules.WILD)], 1: [card(R, 2)]})
	check(act(s, 1, "play", card(R, 2)).is_empty(), "wrong turn")
	check(act(s, 0, "play", card(R, 2)).is_empty(), "card not in hand")
	check(act(s, 0, "play", card(B, 1)).is_empty(), "card that doesn't match")
	check(act(s, 0, "pass").is_empty(), "pass before drawing")
	check(act(s, 0, "play", card(-1, Rules.WILD), 7).is_empty(), "wild with a bad color")
	check(act(s, 0, "play", card(R, 1), B).is_empty(), "number card can't change color")
	check(act(s, 3, "draw").is_empty(), "seat not in the game")
	check(Rules.apply(s, 0, {"do": "play", "id": "1", "color": 0}).is_empty(), "junk id")
	check(Rules.apply(s, 0, {"do": 5}).is_empty() and Rules.apply(s, 0, {}).is_empty(), "junk action")
	check(Rules.apply(s, 1, {"do": "catch", "target": 0}).is_empty(), "catch with nobody to catch")
	check(s.turn == 0 and s.hands[0].size() == 3 and s.discard.size() == 1, "rejects change nothing")

	# --- last card and catching ---
	s = table([0, 1, 2], red5, {0: [card(R, 1), card(G, 1)], 1: [card(R, 3), card(G, 3), card(B, 3)]})
	check(Rules.legal(s, s.hands[0]).any(func(a): return a.do == "last"), "LAST CARD offered at 2 cards")
	act(s, 0, "last")
	check(s.called[0] and s.turn == 0, "calling keeps the turn")
	check(not Rules.legal(s, s.hands[0]).any(func(a): return a.do == "last"), "only once")
	ev = act(s, 0, "play", card(R, 1))
	check(not ev.catchable and s.catchable == -1, "called: safe")
	check(Rules.apply(s, 1, {"do": "catch", "target": 0}).is_empty(), "can't catch a player who called")

	s = table([0, 1, 2], red5, {0: [card(R, 1), card(G, 1)], 1: [card(R, 3), card(G, 3), card(B, 3)]})
	ev = act(s, 0, "play", card(R, 1))
	check(ev.catchable and s.catchable == 0, "forgot to call: catchable")
	check(Rules.apply(s, 0, {"do": "catch", "target": 0}).is_empty(), "can't catch yourself")
	ev = Rules.apply(s, 2, {"do": "catch", "target": 0})
	check(ev.by == 2 and ev.color == 0 and ev.n == 2 and s.hands[0].size() == 3, "caught: +2")
	check(s.catchable == -1 and s.turn == 1, "caught once, turn unchanged")
	check(Rules.apply(s, 1, {"do": "catch", "target": 0}).is_empty(), "no second catch")

	s = table([0, 1, 2], red5, {0: [card(R, 1), card(G, 1)], 1: [card(R, 3), card(G, 3), card(B, 3)]})
	act(s, 0, "play", card(R, 1))
	act(s, 1, "play", card(R, 3))
	check(s.catchable == -1 and Rules.apply(s, 2, {"do": "catch", "target": 0}).is_empty(), "window closes when the next player acts")

	s = table([0, 1, 2], red5, {0: [card(R, 1), card(G, 1)], 1: [card(R, 3), card(G, 3)]})
	act(s, 0, "play", card(R, 1))
	act(s, 1, "last")
	check(s.catchable == -1, "next player's call closes it too")

	# --- reshuffle ---
	s = table([0, 1], red5, {0: [card(B, 7)]}, [])
	s.discard = [card(G, 1), card(G, 2), card(G, 3), card(G, 4), red5]
	ev = act(s, 0, "draw")
	check(ev.reshuffled and s.discard == [red5] and s.pile.size() == 3 and s.hands[0].size() == 2, "empty pile: reshuffle discards, keep the top")
	s = table([0, 1], red5, {0: [card(B, 7)], 1: [card(B, 8)]}, [card(G, 9)])
	s.pending = 4
	s.pending_kind = Rules.WILD4
	s.discard = [card(G, 1), card(G, 2), card(-1, Rules.WILD4)]
	ev = act(s, 0, "draw")
	check(ev.n == 3 and s.pile.is_empty() and s.discard == [card(-1, Rules.WILD4)], "short stack when every card is out")

	# --- places and game over ---
	s = table([0, 1, 2], red5, {0: [card(R, 1)], 1: [card(R, 2), card(G, 9)], 2: [card(R, 3), card(G, 2), card(B, 2)]})
	ev = act(s, 0, "play", card(R, 1))
	check(ev.out and s.winners == [0] and s.turn == 1 and s.phase == "play", "1st place, play goes on")
	s.pile = [card(B, 8)]
	act(s, 1, "draw")
	check(s.turn == 2, "finished players leave the rotation")
	s.hands[2] = [card(G, 3)]
	s.top_color = G
	act(s, 2, "play", card(G, 3))
	check(s.winners == [0, 2] and s.phase == "over", "game over when 2nd place is decided")
	check(Rules.ranking(s) == [0, 2, 1], "ranking")
	var end := Rules.view_for(s, 0)
	check(end.reveal == {0: [], 1: s.hands[1], 2: []}, "game over reveals every leftover hand")
	check(act(s, 1, "draw").is_empty(), "nothing after game over")

	s = table([0, 1, 2, 3], red5, {0: [card(R, 4)], 1: [card(R, 2)], 2: [card(B, 2), card(G, 2)], 3: [card(B, 3)]})
	s.winners = [1]
	act(s, 0, "play", card(R, 4))
	check(s.phase == "play" and s.turn == 2, "4 players: on for 3rd")
	check(Rules.ranking(s) == [1, 0, 3, 2], "the rest ranked by fewest cards")

	s = table([0, 1, 2], red5, {0: [card(R, Rules.SKIP)], 1: [card(R, 2)], 2: [card(R, 3), card(G, 2)]})
	ev = act(s, 0, "play", card(R, Rules.SKIP))
	check(ev.out and ev.skipped == 1 and s.turn == 2, "going out on a skip still skips")

	# --- secrets ---
	order = range(108)
	order.shuffle()
	s = Rules.new_state([0, 1, 3], order)
	var v := Rules.view_for(s, 1)
	var keys := v.keys()
	keys.sort()
	check(keys == ["called", "catchable", "colors", "counts", "dir", "discard", "drawn_id", "hand", "me", "pending",
		"pending_kind", "phase", "pile_count", "top_color", "turn", "winners"], "view fields: %s" % [keys])
	check(v.hand == s.hands[1] and v.counts == {0: 7, 1: 7, 3: 7}, "own hand and counts")
	var other := s.duplicate(true)  # same counts, different secret cards
	for c in [0, 3]:
		for k in 7:
			var swap: int = other.pile[k + 7 * c]
			other.pile[k + 7 * c] = other.hands[c][k]
			other.hands[c][k] = swap
	other.pile.shuffle()
	check(Rules.view_for(other, 1) == v, "view doesn't depend on other hands or the pile")
	check(Rules.view_for(s, -1).hand.is_empty(), "spectator sees no hand")
	check(not v.has("reveal"), "nothing revealed during play")
	s.pile.append(card(B, 0))
	ev = act(s, 0, "draw")
	check(Rules.view_for(s, 1).drawn_id == -1, "others don't see the drawn card")
	check(Rules.event_for(ev, 1).ids.is_empty() and Rules.event_for(ev, 1).n == 1, "others see how many, not which")
	check(Rules.event_for(ev, 0).ids == [card(B, 0)] and ev.ids == [card(B, 0)], "the drawer sees the card")

	# --- random bot games ---
	var actions := 0
	for game in 500:
		order = range(108)
		order.shuffle()
		s = Rules.new_state([[0, 1, 2, 3], [1, 3], [0, 2, 3]][game % 3], order)
		var n := 0
		while s.phase != "over" and n < 5000:
			if s.catchable != -1 and Ai.wants_catch():
				var by: int = s.colors.filter(func(c): return c != s.catchable).pick_random()
				check(not Rules.apply(s, by, {"do": "catch", "target": s.catchable}).is_empty(), "bot catch accepted")
			var a := Ai.pick(Rules.view_for(s, s.turn))
			if Rules.apply(s, s.turn, a).is_empty():
				check(false, "bot picked an illegal action %s" % a)
				break
			n += 1
			if total(s) != 108:
				check(false, "game %d lost cards" % game)
				break
		actions += n
		check(s.phase == "over" and s.winners.size() == s.colors.size() - 1, "random game %d finished" % game)

	print("cards rules: ", "OK" if fails == 0 else "%d failed" % fails, " (avg %d actions/game)" % (actions / 500))
	quit(1 if fails else 0)
