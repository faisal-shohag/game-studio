## Color Cards bot: decides from its own view (public info + its hand), like a person would.

const Rules = preload("res://games/cards/cards_rules.gd")
const CALL_CHANCE := 0.85  # remembers to say "last card"
const CATCH_CHANCE := 0.5  # notices an opponent who forgot


static func pick(v: Dictionary) -> Dictionary:
	var acts := Rules.legal(v, v.hand)
	var plays := acts.filter(func(a): return a.do == "play")
	if plays.is_empty():
		return acts.back()  # draw, or pass after drawing
	if acts.any(func(a): return a.do == "last") and randf() < CALL_CHANCE:
		return {"do": "last"}
	var best: Dictionary = plays[0]
	var best_score := -INF
	for a in plays:
		var sc := _score(v, a)
		if sc > best_score:
			best_score = sc
			best = a
	return best


static func wants_catch() -> bool:
	return randf() < CATCH_CHANCE


static func _score(v: Dictionary, a: Dictionary) -> float:
	var k := Rules.kind_of(a.id)
	var sc := randf() * 0.5
	if k >= Rules.WILD:
		sc -= 50.0 if k == Rules.WILD else 60.0  # save wilds for last
		for id in v.hand:  # and pick the color held most
			if id != a.id and Rules.color_of(id) == a.color:
				sc += 3.0
	elif Rules.color_of(a.id) == v.top_color:
		sc += 20.0
	else:
		sc += 10.0
	if k >= Rules.SKIP and k != Rules.WILD and v.counts[Rules.next_of(v, v.me)] <= 2:
		sc += 40.0  # hold back the player about to win
	return sc
