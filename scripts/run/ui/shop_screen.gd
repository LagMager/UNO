class_name ShopScreen
extends Control

## The shop screen: the 3D ShopView plus the few things written on top of it
## (prices, the player's gold and health). Purchases go through the
## NodeInteractionView, which keeps the shop's rules; ShopView acts them out.

const ShopViewScript = preload("res://scripts/run/ui/shop_view.gd")
const RewardSystem = preload("res://scripts/game/reward_system.gd")
const CREAM := Color("#e8dcc0")
const DIM := Color("#9c8f78")
const SHORT := Color("#c4584a")
const INK := Color("#120d0b")

var view: ShopViewScript
var _iv: NodeInteractionView
var _busy := false
var _dirty := false
var _time := 0.0
var _prices := {}           # item index -> Label
var _purse_label: Label
var _hp_label: Label
var _caption: Label
var _leave: Button


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	view = ShopViewScript.new()
	view.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(view)
	var film := ColorRect.new()
	film.set_anchors_preset(Control.PRESET_FULL_RECT)
	film.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fm := ShaderMaterial.new()
	fm.shader = preload("res://resources/shaders/film_look.gdshader")
	film.material = fm
	add_child(film)
	_purse_label = _label(22)
	_hp_label = _label(18)
	_caption = _label(20)
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.modulate.a = 0.0
	_leave = Button.new()
	_leave.text = "Leave"
	_leave.custom_minimum_size = Vector2(120, 42)
	_leave.pressed.connect(leave)
	add_child(_leave)
	_build_clip_buttons()
	visibility_changed.connect(_on_visibility)


## Test buttons: one per shopkeeper animation, top left (to review them one by one).
func _build_clip_buttons() -> void:
	var box := VBoxContainer.new()
	box.position = Vector2(12, 12)
	box.add_theme_constant_override("separation", 2)
	add_child(box)
	var title := Label.new()
	title.text = "Animaciones"
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", CREAM)
	box.add_child(title)
	for clip: String in view.clip_names():
		var b := Button.new()
		b.text = clip
		b.custom_minimum_size = Vector2(110, 24)
		b.add_theme_font_size_override("font_size", 13)
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func() -> void: view.debug_play(clip))
		box.add_child(b)


func _label(font_size: int) -> Label:
	var l := Label.new()
	l.theme_type_variation = &"HeaderLabel"
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", CREAM)
	l.add_theme_color_override("font_outline_color", INK)
	l.add_theme_constant_override("outline_size", 6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


func _on_visibility() -> void:
	if view != null and view.viewport != null:
		view.viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if visible else SubViewport.UPDATE_DISABLED


## Shows the shop that the interaction view has just opened.
func open(iv: NodeInteractionView) -> void:
	_iv = iv
	if not iv.shop_changed.is_connected(_sync):
		iv.shop_changed.connect(_sync)
	_busy = false
	view.clear_items()
	view.rival_reset()
	visible = true
	_sync()


func close() -> void:
	visible = false
	_busy = false


func leave() -> void:
	if _busy or _iv == null:
		return
	_iv.finish_interaction()


# ------------------------------------------------------------------ state
func _sync() -> void:
	if _iv == null or not _iv.is_shop_open() or not is_inside_tree():
		return
	if _busy:
		_dirty = true
		return
	var cards := _iv.get_shop_cards()
	var sold := []
	for i: int in range(cards.size()):
		if _iv.is_shop_card_sold(i):
			sold.append(i)
	view.set_items(cards, sold)
	var state := _iv.get_run_state()
	var data := _iv.get_shop_data()
	view.set_gold(state.gold)
	view.set_bottle_enabled(data.heal_amount > 0 and state.current_health < state.max_health)
	for l in _prices.values():
		(l as Node).queue_free()
	_prices.clear()
	for i: int in range(cards.size()):
		if not sold.has(i):
			_prices[i] = _price_label(data.base_card_price)
	if data.heal_amount > 0:
		_prices[view.bottle_index] = _price_label(data.heal_price)
	_purse_label.text = str(state.gold)
	_hp_label.text = "HP  %d / %d" % [maxi(state.current_health, 0), state.max_health]


func _price_label(price: int) -> Label:
	var l := _label(18)
	l.text = str(price)
	l.set_meta("price", price)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size = Vector2(80, 30)
	return l


func _price(i: int) -> int:
	var data := _iv.get_shop_data()
	return data.heal_price if i == view.bottle_index else data.base_card_price


# ------------------------------------------------------------------ per frame
func _process(delta: float) -> void:
	if not visible or _iv == null:
		return
	_time += delta
	var state := _iv.get_run_state()
	var hover := view.hover
	for i: int in _prices.keys():
		var l := _prices[i] as Label
		# a card's price goes with the card; the bottle's stays (dim when it can't be used)
		l.visible = view.has_item(i) or i == view.bottle_index
		l.position = view.price_screen_pos(i) - l.size * 0.5
		var price: int = l.get_meta("price")
		var col := CREAM if state.gold >= price else SHORT
		if i == view.bottle_index and not view.has_item(i):
			col = DIM
		l.modulate = Color(1, 1, 1, 1.0 if i == hover else 0.62)
		l.add_theme_color_override("font_color", col)
	_purse_label.size = Vector2(80, 30)
	_purse_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_purse_label.position = view.purse_screen_pos() - _purse_label.size * 0.5
	_hp_label.position = Vector2(28, 24)
	_leave.position = Vector2(size.x - _leave.size.x - 28, 22)
	_caption.size = Vector2(size.x, 34)
	_caption.position = Vector2(0, size.y * 0.6)


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _show_caption(text: String) -> void:
	if _caption.text == text and _caption.modulate.a > 0.5:
		return
	_caption.text = text
	var t := create_tween()
	t.tween_property(_caption, "modulate:a", 1.0 if not text.is_empty() else 0.0, 0.15)


# ------------------------------------------------------------------ input
func _gui_input(event: InputEvent) -> void:
	if _iv == null or not _iv.is_shop_open():
		return
	if event is InputEventMouseMotion:
		var h := -1 if _busy else view.pick(event.position)
		if h != view.hover:
			view.hover = h
			_show_caption(_describe(h))
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var h := view.pick(event.position)
		if h >= 0:
			buy(h)
			accept_event()


func _describe(i: int) -> String:
	if i < 0:
		return ""
	if i == view.bottle_index:
		return "Whisky · +%d HP" % _iv.get_shop_data().heal_amount
	var cards := _iv.get_shop_cards()
	return RewardSystem.describe_card(cards[i]) if i < cards.size() else ""


## Buys a card (0..n-1) or a drink (the bottle): one hand pays, the other takes it.
func buy(i: int) -> void:
	if _busy or _iv == null or not view.has_item(i):
		return
	var price := _price(i)
	view.hover = -1
	_show_caption("")
	_busy = true   # before buying: the stock must not refresh under the hand
	if not _iv.select_option_index(i):
		_busy = false
		_dirty = false
		view.refuse()
		_purse_shake()
		return
	view.pay(price)
	if i == view.bottle_index:
		await view.buy_drink()
	else:
		await view.buy_card(i)
	_busy = false
	_dirty = false
	_sync()


func _purse_shake() -> void:
	var base := _purse_label.scale
	_purse_label.pivot_offset = _purse_label.size * 0.5
	var t := create_tween()
	t.tween_property(_purse_label, "scale", base * 1.25, 0.06)
	t.tween_property(_purse_label, "scale", base, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
