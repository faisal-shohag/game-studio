## Pure Color Cards rules. No nodes, no UI, no network: state is a plain Dictionary, like
## snakes_rules.gd. Hands are secret, so peers and bots only ever see view_for(): the public
## fields plus their own hand. legal() works from such a view, so it serves clients, bots and tests.
##
## Cards are ints 0..107 indexing DECK ([color, kind]); color -1 = wild. Per color: one 0, two
## each of 1-9, Skip, Reverse and +2; plus 4 Wild and 4 Wild +4. Match color, number or symbol;
## wilds always play. +2 stacks on +2 and +4 on +4 (no mixing): the next player stacks or draws the
## whole pile and loses the turn. Otherwise a player who can't (or won't) play draws 1 and may play
## it at once. Play down to one card without calling "last card" and any opponent may catch you
## (+2) until the next player acts. Players who empty their hand leave the rotation; play goes on
## until every place but the last is decided.

const SKIP := 10
const REVERSE := 11
const DRAW2 := 12
const WILD := 13
const WILD4 := 14
const HAND := 7
const PENALTY := 2  # cards for being caught
const SHOWN_DISCARDS := 6  # how much of the discard pile a view carries

static var DECK: Array = _make_deck()


static func _make_deck() -> Array:
	var d := []
	for col in 4:
		d.append([col, 0])
		for k in range(1, DRAW2 + 1):  # 1-9, Skip, Reverse, +2: two of each
			d.append([col, k])
			d.append([col, k])
	for k in [WILD, WILD4]:
		for i in 4:
			d.append([-1, k])
	return d


static func color_of(id: int) -> int:
	return DECK[id][0]


static func kind_of(id: int) -> int:
	return DECK[id][1]


## `order` is the shuffled deck (the host passes a shuffled range(108); tests pass a fixed one).
## Deals 7 each, then flips the first discard, sending non-number cards to the bottom.
static func new_state(colors: Array, order: Array) -> Dictionary:
	var s := {
		"colors": colors.duplicate(),
		"hands": {},
		"pile": order.duplicate(),  # draw pile, top = back
		"discard": [],  # top = back
		"top_color": 0,  # color to match (a wild's chosen color)
		"dir": 1,  # 1 = along `colors`, -1 = reversed
		"turn": colors[0],
		"pending": 0,  # cards stacked by +2s / +4s for the player in turn
		"pending_kind": -1,  # DRAW2 or WILD4 while pending > 0
		"phase": "play",  # play | drawn (may play the drawn card or pass) | over
		"drawn_id": -1,
		"winners": [],
		"called": {},  # color -> said "last card" this turn
		"catchable": -1,  # color that went down to one card without calling, until the next action
	}
	for c in colors:
		s.hands[c] = []
		s.called[c] = false
	for k in HAND:
		for c in colors:
			s.hands[c].append(s.pile.pop_back())
	while kind_of(s.pile.back()) > 9:
		s.pile.push_front(s.pile.pop_back())
	var first: int = s.pile.pop_back()
	s.discard.append(first)
	s.top_color = color_of(first)
	return s


## Whether card `id` may go on the pile now (public info only).
static func can_play(pub: Dictionary, id: int) -> bool:
	var k := kind_of(id)
	if pub.pending > 0:
		return k == pub.pending_kind
	if pub.phase == "drawn" and id != pub.drawn_id:
		return false
	return k >= WILD or color_of(id) == pub.top_color or k == kind_of(pub.discard.back())


## Actions for the player in turn holding `hand`: {"do": "play", "id", "color"} (a wild once per
## color), {"do": "last"}, then {"do": "draw"} or, after drawing a playable card, {"do": "pass"}.
## Works on a state or a view. "catch" isn't listed: it isn't a turn action.
static func legal(pub: Dictionary, hand: Array) -> Array:
	if pub.phase == "over":
		return []
	var acts := []
	for id in hand:
		if can_play(pub, id):
			for col in (range(4) if color_of(id) == -1 else [color_of(id)]):
				acts.append({"do": "play", "id": id, "color": col})
	if not acts.is_empty() and hand.size() == 2 and not pub.called[pub.turn]:
		acts.append({"do": "last"})
	acts.append({"do": "draw"} if pub.phase == "play" else {"do": "pass"})
	return acts


## Player c acts. Returns {} when illegal (untrusted peers), else an event:
##   play  {color, id, top_color, out, skipped, reversed, pending, catchable}
##   draw  {color, ids, n, stack, can_play, reshuffled}   (ids are secret: see event_for)
##   pass  {color}       last {color}
##   catch {color (caught), by, ids, n, reshuffled}
static func apply(s: Dictionary, c: int, a: Dictionary) -> Dictionary:
	if s.phase == "over" or not c in s.colors:
		return {}
	var what = a.get("do")
	if typeof(what) != TYPE_STRING:
		return {}
	if what == "catch":
		return _catch(s, c, a.get("target"))
	if c != s.turn:
		return {}
	var id = a.get("id")
	var col = a.get("color")
	var ok := false
	for l in legal(s, s.hands[c]):
		if l.do == what and (what != "play" or (typeof(id) == TYPE_INT and typeof(col) == TYPE_INT and l.id == id and l.color == col)):
			ok = true
	if not ok:
		return {}
	s.catchable = -1  # the next player acted: too late to catch
	match what:
		"play":
			return _play(s, c, id, col)
		"draw":
			return _draw(s, c)
		"pass":
			s.phase = "play"
			s.drawn_id = -1
			_advance(s, 1)
			return {"do": "pass", "color": c}
		_:
			s.called[c] = true
			return {"do": "last", "color": c}


static func _play(s: Dictionary, c: int, id: int, col: int) -> Dictionary:
	var k := kind_of(id)
	var active := _active(s).size()  # before c may leave
	s.hands[c].erase(id)
	s.discard.append(id)
	s.top_color = col
	s.drawn_id = -1
	var left: int = s.hands[c].size()
	if left == 1 and not s.called[c]:
		s.catchable = c
	s.called[c] = false
	if left == 0:
		s.winners.append(c)
	var steps := 1
	if k == SKIP or (k == REVERSE and active == 2):
		steps = 2
	if k == REVERSE:
		s.dir = -s.dir
	if k == DRAW2 or k == WILD4:
		s.pending += 2 if k == DRAW2 else 4
		s.pending_kind = k
	var ev := {"do": "play", "color": c, "id": id, "top_color": col, "out": left == 0, "skipped": -1,
		"reversed": k == REVERSE, "pending": s.pending, "catchable": s.catchable == c}
	if is_over(s):
		s.phase = "over"
	else:
		s.phase = "play"
		var passed := _advance(s, steps)
		if steps == 2:
			ev.skipped = passed[0]
	return ev


static func _draw(s: Dictionary, c: int) -> Dictionary:
	s.called[c] = false
	var ev := {"do": "draw", "color": c, "stack": s.pending > 0, "can_play": false}
	if s.pending > 0:
		ev.merge(_take(s, c, s.pending))
		s.pending = 0
		s.pending_kind = -1
		_advance(s, 1)
		return ev
	ev.merge(_take(s, c, 1))
	if ev.n == 1:
		s.phase = "drawn"
		s.drawn_id = ev.ids[0]
		ev.can_play = can_play(s, s.drawn_id)
	if not ev.can_play:  # nothing to play: the turn passes by itself
		s.phase = "play"
		s.drawn_id = -1
		_advance(s, 1)
	return ev


static func _catch(s: Dictionary, by: int, target) -> Dictionary:
	if typeof(target) != TYPE_INT or target != s.catchable or target == by:
		return {}
	s.catchable = -1
	var ev := {"do": "catch", "color": target, "by": by}
	ev.merge(_take(s, target, PENALTY))
	return ev


## Moves up to n cards from the pile to c's hand, reshuffling the discards (all but the top) when
## the pile runs out. Returns {ids, n, reshuffled}.
static func _take(s: Dictionary, c: int, n: int) -> Dictionary:
	var ids := []
	var reshuffled := false
	for i in n:
		if s.pile.is_empty():
			if s.discard.size() < 2:
				break  # every card is in someone's hand
			var top: int = s.discard.pop_back()
			s.pile = s.discard
			s.pile.shuffle()
			s.discard = [top]
			reshuffled = true
		ids.append(s.pile.pop_back())
	s.hands[c].append_array(ids)
	return {"ids": ids, "n": ids.size(), "reshuffled": reshuffled}


static func is_over(pub: Dictionary) -> bool:
	return pub.winners.size() >= pub.colors.size() - 1


## Colors still holding cards, in seating order.
static func _active(pub: Dictionary) -> Array:
	return pub.colors.filter(func(c): return not c in pub.winners)


## The player after c in the current direction, skipping those who went out.
static func next_of(pub: Dictionary, c: int) -> int:
	var i: int = pub.colors.find(c)
	var n: int = pub.colors.size()
	for k in n:
		i = posmod(i + pub.dir, n)
		if not pub.colors[i] in pub.winners:
			return pub.colors[i]
	return c


## Moves the turn on `steps` players; returns the players passed over, the last one being in turn.
static func _advance(s: Dictionary, steps: int) -> Array:
	var passed := []
	for k in steps:
		s.turn = next_of(s, s.turn)
		passed.append(s.turn)
	return passed


## Finishing order, then everyone else by fewest cards. Works on a state or a view.
static func ranking(pub: Dictionary) -> Array:
	var count := func(c: int) -> int: return pub.counts[c] if pub.has("counts") else pub.hands[c].size()
	var rest: Array = _active(pub)
	rest.sort_custom(func(a, b): return count.call(a) < count.call(b))
	return pub.winners + rest


## What player c may know: public fields, card counts and c's own hand. Never other hands or the
## pile order, except that once the game is over everyone's leftover cards are shown ("reveal").
## c = -1 gives a spectator view (empty hand).
static func view_for(s: Dictionary, c: int) -> Dictionary:
	var counts := {}
	for col in s.colors:
		counts[col] = s.hands[col].size()
	var v := {
		"colors": s.colors.duplicate(),
		"me": c,
		"hand": s.hands[c].duplicate() if s.hands.has(c) else [],
		"counts": counts,
		"discard": s.discard.slice(maxi(0, s.discard.size() - SHOWN_DISCARDS)),
		"pile_count": s.pile.size(),
		"top_color": s.top_color,
		"dir": s.dir,
		"turn": s.turn,
		"pending": s.pending,
		"pending_kind": s.pending_kind,
		"phase": s.phase,
		"drawn_id": s.drawn_id if c == s.turn else -1,
		"winners": s.winners.duplicate(),
		"called": s.called.duplicate(),
		"catchable": s.catchable,
	}
	if s.phase == "over":
		v.reveal = s.hands.duplicate(true)
	return v


## The event as player c may see it: drawn card ids only for the one who drew them.
static func event_for(ev: Dictionary, c: int) -> Dictionary:
	var e := ev.duplicate(true)
	if e.has("ids") and e.color != c:
		e.ids = []
	return e
