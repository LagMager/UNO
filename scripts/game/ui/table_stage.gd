class_name TableStage
extends Control

## The duel screen: the 3D scene (DuelView) plus the 2D layer on top of it:
## the player's own stickman arms holding their hand, the card the player throws,
## captions and the hit flash. Combat logic stays in Encounter; this only replays
## what changed in a round, step by step, and locks the hand meanwhile.

## True while a round is being replayed; the hand should not accept clicks then.
signal busy_changed(busy: bool)

const DuelViewScript = preload("res://scripts/game/ui/duel_view.gd")
const CardViewScript = preload("res://scripts/game/card_view.gd")
const INK := Color(0.078, 0.063, 0.063)
const HAND_CARD := Vector2(116, 136)

var duel: DuelViewScript
var hand_row: Control  # set by the main UI: the player's cards, for the arms to hold

var _fly: Control
var _caption: Label
var _flash: ColorRect
var _arms: Control
var _fists: Control
var _discard: Array[Card] = []
var _draw_count := 0
var _active := Card.CardColor.RED
var _time := 0.0
var _run := 0
var _animating := false
var _pending: RefCounted
var _rng := RandomNumberGenerator.new()
var _grip_l := Vector2.ZERO
var _grip_r := Vector2.ZERO
var _override_r := Vector2.INF
var _override_l := Vector2.INF
var _jolt := Vector2.ZERO
var _fid_l := Vector2.ZERO
var _fid_r := Vector2.ZERO
var _fear := 0.0
var _fidget_wait := 4.0
var _indicator: Control
var _indicator_card: Card


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rng.randomize()
	duel = DuelViewScript.new()
	duel.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(duel)
	var film := ColorRect.new()
	film.set_anchors_preset(Control.PRESET_FULL_RECT)
	film.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fm := ShaderMaterial.new()
	fm.shader = preload("res://resources/shaders/film_look.gdshader")
	film.material = fm
	add_child(film)
	_arms = _layer()
	_fly = _layer()
	_fists = _layer()
	_caption = Label.new()
	_caption.theme_type_variation = &"HeaderLabel"
	_caption.add_theme_font_size_override("font_size", 22)
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.modulate.a = 0.0
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_caption)
	_flash = ColorRect.new()
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.color = Color(1, 0.35, 0.2, 0)
	add_child(_flash)
	_indicator = Control.new()
	_indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_indicator.draw.connect(_draw_indicator)
	add_child(_indicator)
	resized.connect(_layout)
	_layout()


func _layer() -> Control:
	var c := Control.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(c)
	return c


func _layout() -> void:
	if _caption == null:
		return
	_caption.size = Vector2(size.x, 40)
	if _indicator != null:
		_indicator.position = Vector2(24, 128)
		_indicator.size = Vector2(170, 210)
	_caption.position = Vector2(0, size.y * 0.47)


func _process(delta: float) -> void:
	_time += delta
	_fear = maxf(_fear - delta * 0.6, 0.0) if not _aimed_at else minf(_fear + delta * 3.0, 1.0)
	if not _animating:
		_fidget_wait -= delta
		if _fidget_wait <= 0.0:
			_fidget_wait = randf_range(5.0, 10.0)
			_hand_fidget()
	_update_arms()
	var buttons: Array = []
	if hand_row != null and is_instance_valid(hand_row) and hand_row.is_visible_in_tree():
		for b in hand_row.get_children():
			if b is Button:
				# the button stays for clicks and hover; the 3D card is what you see
				(b as Control).modulate.a = 0.0
				buttons.append(b)
	duel.update_player_hand(buttons, _grip_l, _grip_r)


# ------------------------------------------------------------------ player arms
func _hand_center() -> Vector2:
	if hand_row != null and is_instance_valid(hand_row) and hand_row.is_visible_in_tree() and hand_row.get_child_count() > 0:
		var r := hand_row.get_global_rect()
		return Vector2(r.get_center().x, r.end.y) - global_position
	return Vector2(size.x * 0.5, size.y * 0.9)


func _shoulder(side: int) -> Vector2:
	return Vector2(_hand_center().x + size.y * 0.21 * side, size.y * 1.32)


func _default_grip(side: int) -> Vector2:
	# each fist holds a bottom corner of the fan, thumb over the cards
	if hand_row != null and is_instance_valid(hand_row) and hand_row.get_child_count() > 0:
		var to_local := get_global_transform().affine_inverse()
		var b := hand_row.get_child(0 if side < 0 else hand_row.get_child_count() - 1) as Control
		var xf := to_local * b.get_global_transform()
		if side < 0:
			return xf * Vector2(b.size.x * 0.22, b.size.y * 0.86)
		return xf * Vector2(b.size.x * 0.78, b.size.y * 0.86)
	return _hand_center() + Vector2(46 * side, -40)


func _update_arms() -> void:
	var breath := Vector2(0, sin(_time * TAU / 3.8) * 3.0)
	var shiver := Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _fear * 5.0
	_grip_l = (_default_grip(-1) if _override_l == Vector2.INF else _override_l) + breath + _jolt + _fid_l + shiver
	_grip_r = (_default_grip(1) if _override_r == Vector2.INF else _override_r) + breath * 0.8 + _jolt + _fid_r + shiver * 0.8


func _arm_points(side: int) -> PackedVector2Array:
	var s := _shoulder(side)
	var h := _grip_l if side < 0 else _grip_r
	var seg := size.y * 0.21
	var d := clampf(s.distance_to(h), 1.0, seg * 2.0 - 1.0)
	h = s + (h - s).normalized() * d
	var a := acos(clampf(d / (2.0 * seg), -1.0, 1.0))
	var dir := (h - s).normalized()
	var e := s + dir.rotated(-a * side) * seg
	var ctrl := e * 2.0 - (s + h) * 0.5
	var pts := PackedVector2Array()
	for i: int in range(13):
		var t := i / 12.0
		pts.append(s.lerp(ctrl, t).lerp(ctrl.lerp(h, t), t))
	return pts


func _draw_arms() -> void:
	var w := size.y * 0.036
	for side: int in [-1, 1]:
		var pts := _arm_points(side)
		_arms.draw_polyline(pts, INK, w, true)
		for p: Vector2 in pts:
			_arms.draw_circle(p, w * 0.5, INK, true, -1.0, true)


func _draw_fists() -> void:
	var w := size.y * 0.036
	for side: int in [-1, 1]:
		var pts := _arm_points(side)
		var h := pts[pts.size() - 1]
		var dir := (pts[pts.size() - 1] - pts[pts.size() - 3]).normalized()
		_fists.draw_circle(h, w * 0.78, INK, true, -1.0, true)
		var thumb := h + dir.rotated(-0.9 * side) * w * 0.9
		_fists.draw_line(h, thumb, INK, w * 0.5, true)
		_fists.draw_circle(thumb, w * 0.25, INK, true, -1.0, true)


func _reach(side: int, target: Vector2, dur: float) -> void:
	var t := create_tween()
	var from := _grip_l if side < 0 else _grip_r
	t.tween_method(func(p: Vector2) -> void:
		if side < 0:
			_override_l = p
		else:
			_override_r = p, from, target, dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await t.finished


func _release(side: int) -> void:
	if side < 0:
		_override_l = Vector2.INF
	else:
		_override_r = Vector2.INF


# ------------------------------------------------------------------ state
func snapshot(encounter: RefCounted) -> Dictionary:
	var ids := {}
	for card: Card in encounter.discard_pile:
		ids[card.get_instance_id()] = true
	return {
		"discard_ids": ids,
		"enemy_count": encounter.enemy_hand.size(),
		"player_count": encounter.player_hand.size(),
		"player_hp": encounter.player_health,
		"enemy_hp": encounter.enemy_health,
	}


func sync_now(encounter: RefCounted) -> void:
	if _animating:
		_pending = encounter
		return
	_discard.assign(encounter.discard_pile)
	_draw_count = encounter.draw_pile.size()
	_active = encounter.active_color
	_refresh_table()
	if not _dealing:   # while he gathers his first hand, the deal sets the count
		duel.set_hand_count(encounter.enemy_hand.size())
	var max_hp := 20.0
	duel.set_danger(clampf(1.0 - float(encounter.player_health) / (max_hp * 0.4), 0.0, 1.0))
	_indicator_card = encounter.top_card()
	_indicator.queue_redraw()


func _refresh_table() -> void:
	duel.show_piles(_discard, _draw_count, _active)
	if _indicator != null:
		_indicator_card = _discard.back() if not _discard.is_empty() else null
		_indicator.queue_redraw()


func new_encounter(encounter: RefCounted) -> void:
	_run += 1
	_set_busy(false)
	for child in _fly.get_children():
		child.queue_free()
	_release(-1)
	_release(1)
	# each enemy has his own face: the Aggressor is the Gila (the lizard gunman),
	# the Trickster the traveling dentist, the rest face the card sharp.
	var kinds := {"aggressor": "gila", "trickster": "matasanos"}
	duel.set_rival(kinds.get(encounter.enemy_id, "tahur"))
	duel.rival_reset()
	_caption.modulate.a = 0.0
	sync_now(encounter)
	_deal_rival(encounter.enemy_hand.size())


## At the start of a duel his hand is empty: he takes his cards from the deck, so they
## never pop into his fan out of nowhere.
## It doesn't block the player: if a card is played meanwhile, the rival finishes
## gathering his cards before he answers (play_round waits on _dealing).
var _dealing := false
var _deal_id := 0


func _deal_rival(count: int) -> void:
	if count <= 0:
		return
	_deal_id += 1
	var id := _deal_id
	_dealing = true
	duel.set_hand_count(0)
	await _wait(0.6)
	if id == _deal_id:
		await duel.rival_draw_card(count)
		await duel.rival_settle()
	if id == _deal_id:
		_dealing = false


# ------------------------------------------------------------------ round replay
func play_round(before: Dictionary, encounter: RefCounted, player_card: Card, from_rect: Rect2, player_drew: bool) -> void:
	_run += 1
	var run := _run
	for child in _fly.get_children():
		child.queue_free()
	_set_busy(true)
	_pending = encounter
	var shown: Array[Card] = []
	var new_cards: Array[Card] = []
	for card: Card in encounter.discard_pile:
		if before["discard_ids"].has(card.get_instance_id()):
			shown.append(card)
		else:
			new_cards.append(card)
	_discard = shown.duplicate()
	_refresh_table()
	var enemy_damage: int = before["enemy_hp"] - encounter.enemy_health
	var player_damage: int = before["player_hp"] - encounter.player_health

	if player_card != null:
		new_cards.erase(player_card)
		var start := from_rect if from_rect.size != Vector2.ZERO else Rect2(Vector2(size.x * 0.5 - 58, size.y - 160), HAND_CARD)
		var c := start.get_center()
		var wild := duel.holding_wild()
		if not wild:
			duel.player_pick(player_card)             # the card waits in the fan for the fist
		_reach(1, c + Vector2(0, start.size.y * 0.3), 0.18)  # the fist goes to the card
		await _wait(0.18)
		if run != _run: return
		if not wild:
			duel.player_attach(0.1)                   # ...and closes on it
		_reach(1, c + Vector2(-26, -64), 0.24)        # pull it up out of the fan, cock the wrist
		_nudge(-1, Vector2(-6, 16), 0.6)              # the other hand braces the fan
		await _wait(0.24)
		if run != _run: return
		_reach(1, c.lerp(duel.pile_screen_pos(), 0.7), 0.3)  # the swing...
		await _wait(0.1)                              # ...it lets go mid-swing, with its speed
		if run != _run: return
		duel.focus_pile(0.35)
		await duel.player_throw(player_card, c + Vector2(-26, -64))
		if run != _run: return
		_release_smooth(1, 0.5)
		_land(player_card)
		if enemy_damage > 0:
			duel.rival_hurt()
			_popup("-%d" % enemy_damage, duel.head_screen_pos())
			await _wait(0.9)
		else:
			await _wait(0.3)
	elif player_drew:
		_caption_show("You draw a card")
		if encounter.player_hand.size() > before["player_count"]:
			var drawn: Card = encounter.player_hand[encounter.player_hand.size() - 1]
			duel.hide_hand_card(drawn)               # it is still on the deck
			await _reach(1, duel.deck_screen_pos() + Vector2(0, 20), 0.36)
			if run != _run: return
			duel.player_grab_deck(drawn)              # the fist takes the top card
			await _wait(0.2)
			if run != _run: return
			_release_smooth(1, 0.62)                  # and brings it back to the fan
			await duel.player_bring_to_hand(drawn, 0.62)
			if run != _run: return
		await _wait(0.3)
	if run != _run: return

	if encounter.result == "Victory":
		duel.rival_defeat()
		_finish(run)
		return
	while _dealing:   # he is still gathering his first hand
		await get_tree().process_frame
	if run != _run: return

	# every card that enters his hand is seen coming off the deck: how many he drew this
	# round = what he holds now - what he held + what he played (a draw, a fresh hand
	# after playing his last card, several draws in one round)
	var hand_count: int = before["enemy_count"]
	var to_draw: int = encounter.enemy_hand.size() - hand_count + new_cards.size()
	if new_cards.is_empty():
		if to_draw > 0:
			_caption_show("Rival draws a card" if to_draw == 1 else "Rival draws %d cards" % to_draw)
			await _rival_draws(to_draw)
			if run != _run: return
			to_draw = 0
		else:
			_caption_show("Rival's turn is skipped")
			await _wait(0.8)
	for card: Card in new_cards:
		if run != _run: return
		duel.focus_rival(0.35)
		await duel.rival_play_card(card)
		if run != _run: return
		duel.focus_pile(0.5)
		_caption_show("Rival plays %s" % card.get_label())
		_land(card)
		await duel.rival_settle()
		hand_count -= 1
		if hand_count <= 0 and to_draw > 0:
			# he played his last card: he takes a fresh hand from the deck
			if run != _run: return
			_caption_show("Rival takes a new hand")
			var fresh := mini(to_draw, ENEMY_FRESH_HAND)
			await _rival_draws(fresh)
			hand_count += fresh
			to_draw -= fresh
	if run != _run: return
	if to_draw > 0:
		await _rival_draws(to_draw)
	if run != _run: return

	if player_damage > 0:
		_caption_show(duel.attack_caption(player_damage))
		duel.focus_rival(0.9)
		_aimed_at = true
		await duel.rival_shoot()
		_aimed_at = false
		if run != _run: return
		duel.player_hit(clampf(0.75 + player_damage * 0.25, 0.75, 1.4))
		_shot_hit()
		await duel.rival_settle()
	if encounter.result == "Defeat":
		duel.rival_taunt()
	_finish(run)


## Same as Encounter.STARTING_HAND_SIZE: the hand he gets after playing his last card.
const ENEMY_FRESH_HAND := 5


func _rival_draws(count: int) -> void:
	duel.focus_rival(0.6)
	_draw_count = maxi(_draw_count - count, 0)
	_refresh_table()
	await duel.rival_draw_card(count)
	await duel.rival_settle()


func _finish(run: int) -> void:
	if run != _run:
		return
	_set_busy(false)
	if _pending != null:
		sync_now(_pending)


func _set_busy(value: bool) -> void:
	if _animating != value:
		_animating = value
		busy_changed.emit(value)


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _land(card: Card) -> void:
	_discard.append(card)
	_refresh_table()


func _card_rect(tex: Texture2D) -> TextureRect:
	var r := TextureRect.new()
	r.texture = tex
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## The player's card leaves the hand and shrinks toward the pile on the table.
func _fly_card_to(card: Card, from: Rect2, target_center: Vector2) -> void:
	var r := _card_rect(CardViewScript.face_for(card))
	r.position = from.position
	r.size = from.size
	r.pivot_offset = from.size * 0.5
	_fly.add_child(r)
	var end_size := from.size * 0.42
	var t := create_tween().set_parallel(true)
	t.tween_property(r, "position", target_center - end_size * 0.5, 0.34).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(r, "size", end_size, 0.34).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(r, "pivot_offset", end_size * 0.5, 0.34)
	t.tween_property(r, "rotation", deg_to_rad(_rng.randf_range(-12.0, 12.0)), 0.34)
	t.tween_property(r, "scale:y", 0.45, 0.34).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await t.finished
	if is_instance_valid(r):
		r.queue_free()


## A drawn card comes off the deck, travels to the player's hand and turns over.
func _fly_to_hand(card: Card) -> void:
	var r := _card_rect(CardViewScript.back_texture())
	var from_size := HAND_CARD * 0.4
	r.size = from_size
	r.pivot_offset = from_size * 0.5
	r.position = duel.deck_screen_pos() - from_size * 0.5
	_fly.add_child(r)
	var target := _hand_center() - Vector2(HAND_CARD.x * 0.5, HAND_CARD.y + 10)
	var t := create_tween().set_parallel(true)
	t.tween_property(r, "position", target, 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(r, "size", HAND_CARD, 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(r, "pivot_offset", HAND_CARD * 0.5, 0.55)
	var flip := create_tween()
	flip.tween_interval(0.3)
	flip.tween_property(r, "scale:x", 0.04, 0.12)
	flip.tween_callback(func() -> void: r.texture = CardViewScript.face_for(card))
	flip.tween_property(r, "scale:x", 1.0, 0.13)
	await t.finished
	await get_tree().create_timer(0.05).timeout
	if is_instance_valid(r):
		r.queue_free()


func _caption_show(text: String) -> void:
	_caption.text = text
	var t := create_tween()
	t.tween_property(_caption, "modulate:a", 1.0, 0.12)
	t.tween_interval(1.1)
	t.tween_property(_caption, "modulate:a", 0.0, 0.4)


func _popup(text: String, at: Vector2) -> void:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = &"HeaderLabel"
	l.add_theme_font_size_override("font_size", 38)
	l.add_theme_color_override("font_color", Color("#ffd2c4"))
	l.position = at - Vector2(30, 20)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fly.add_child(l)
	var t := l.create_tween().set_parallel(true)
	t.tween_property(l, "position:y", l.position.y - 70, 0.8).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(l, "modulate:a", 0.0, 0.8).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.chain().tween_callback(l.queue_free)


func _shot_hit() -> void:
	# flinch: hands snap down, hold a beat, ease back up
	var flinch := create_tween()
	flinch.tween_property(self, "_jolt", Vector2(0, 48), 0.06).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	flinch.tween_interval(0.12)
	flinch.tween_property(self, "_jolt", Vector2.ZERO, 0.45).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var t := create_tween()
	t.tween_property(_flash, "color:a", 0.0, 0.01)
	t.tween_property(_flash, "color:a", 0.0, 0.5)
	var shake := create_tween()
	for offset: Vector2 in [Vector2(9, -5), Vector2(-8, 6), Vector2(5, -3), Vector2.ZERO]:
		shake.tween_property(self, "position", offset, 0.04)


const INDICATOR_TINTS := {
	Card.CardColor.RED: Color("#b3261e"),
	Card.CardColor.YELLOW: Color("#c9953a"),
	Card.CardColor.GREEN: Color("#4e8a3e"),
	Card.CardColor.BLUE: Color("#2f5e9e"),
}
const INDICATOR_NAMES := {
	Card.CardColor.RED: "ROJO",
	Card.CardColor.YELLOW: "AMARILLO",
	Card.CardColor.GREEN: "VERDE",
	Card.CardColor.BLUE: "AZUL",
}


## Corner plaque: the card on the pile and the color in play, as a tin badge.
func _draw_indicator() -> void:
	var ci := _indicator
	var font := get_theme_default_font()
	var col: Color = INDICATOR_TINTS.get(_active, Color("#8a7a62"))
	# card on the pile, slightly tilted, with a drop shadow
	if _indicator_card != null:
		var tex := CardViewScript.face_for(_indicator_card)
		if tex != null:
			ci.draw_set_transform(Vector2(58, 78), -0.08, Vector2.ONE)
			ci.draw_rect(Rect2(Vector2(-40, -46) + Vector2(4, 5), Vector2(80, 94)), Color(0, 0, 0, 0.5))
			ci.draw_texture_rect(tex, Rect2(Vector2(-40, -46), Vector2(80, 94)), false, Color(0.86, 0.82, 0.76))
			ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# tin badge with the active color, pinned over the card's corner
	var bc := Vector2(112, 128)
	var pulse := 0.85 + 0.15 * sin(_time * 3.0)
	for k: int in range(12):
		var a := k * TAU / 12.0
		ci.draw_circle(bc + Vector2(cos(a), sin(a)) * 30.0, 5.0, Color("#120d0b"))
	ci.draw_circle(bc, 31.0, Color("#120d0b"))
	ci.draw_circle(bc, 28.0, Color("#6b6258"))
	ci.draw_circle(bc, 23.0, col.darkened(0.3))
	ci.draw_circle(bc, 20.0, col * pulse)
	ci.draw_arc(bc, 20.0, PI * 1.1, PI * 1.6, 10, Color(1, 1, 1, 0.35), 2.0)
	var name: String = INDICATOR_NAMES.get(_active, "")
	if not name.is_empty():
		var w := font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		var p := Vector2(bc.x - w * 0.5, bc.y + 52)
		ci.draw_string_outline(font, p, name, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, 5, Color("#120d0b"))
		ci.draw_string(font, p, name, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, col.lightened(0.35))


var _aimed_at := false


## Eases a hand from where it is back to its grip on the fan (no snap).
func _release_smooth(side: int, dur: float) -> void:
	var from := _grip_l if side < 0 else _grip_r
	var t := create_tween()
	t.tween_method(func(u: float) -> void:
		var p := from.lerp(_default_grip(side), u)
		if side < 0:
			_override_l = p
		else:
			_override_r = p, 0.0, 1.0, dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_callback(func() -> void: _release(side))


## A small push on one hand that springs back.
func _nudge(side: int, offset: Vector2, dur: float) -> void:
	var prop := "_fid_l" if side < 0 else "_fid_r"
	var t := create_tween()
	t.tween_property(self, prop, offset, dur * 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(self, prop, Vector2.ZERO, dur * 0.7).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Idle: the player's hands are restless too.
func _hand_fidget() -> void:
	match randi() % 3:
		0:  # squares the cards: taps their top edge twice
			var t := create_tween()
			for i: int in range(2):
				t.tween_property(self, "_fid_r", Vector2(-18, -34), 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
				t.tween_property(self, "_fid_r", Vector2(-10, -18), 0.09)
			t.tween_property(self, "_fid_r", Vector2.ZERO, 0.25).set_trans(Tween.TRANS_SINE)
		1:  # tilts the fan toward himself to check it
			var t := create_tween().set_parallel(true)
			t.tween_property(self, "_fid_l", Vector2(4, 16), 0.35).set_trans(Tween.TRANS_SINE)
			t.tween_property(self, "_fid_r", Vector2(-4, -14), 0.35).set_trans(Tween.TRANS_SINE)
			t.chain().tween_interval(0.6)
			t.chain().tween_property(self, "_fid_l", Vector2.ZERO, 0.4).set_trans(Tween.TRANS_SINE)
			t.parallel().tween_property(self, "_fid_r", Vector2.ZERO, 0.4).set_trans(Tween.TRANS_SINE)
		_:  # a nervous squeeze: both hands pull in and down
			_nudge(-1, Vector2(10, 10), 0.6)
			_nudge(1, Vector2(-10, 10), 0.6)
