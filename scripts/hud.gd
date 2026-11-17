extends CanvasLayer
## The on-screen interface, built in code: small frosted-glass pieces that hug
## the edges of the window, so the town in the middle stays in view.
##   Centre:        the New city dialog (pick a difficulty), when a game starts
##   Top left:      the game menu (New city, Save, Load, How to play, Day and
##                  night), city name, date and clock, speed (pause, play, fast)
##   Top centre:    advisors' ticker: the most urgent tip and a count; click the
##                  count for the full list
##   Top right:     the status strip: money (and last month), people, happiness,
##                  four small meters (power, water, services, rubbish) and demand
##                  (homes, shops, industry). Click it for the City panel: budget, loans,
##                  tax rate, happiness, services, housing and growth in full
##   Bottom left:   the Build dock: a rail of categories (Bulldoze at its foot) and
##                  a flyout of items with pictures, names and prices (M hides it)
##   Bottom centre: the tool in use, what's under the mouse and what building
##                  there costs; messages pop up above it
##   Bottom right:  map views as a row of icons, with the colour key above them
## It only displays things and reports button presses; the game decides what they do.

signal tool_chosen(tool_id: int)            # (the Bulldoze button)
signal build_item_chosen(id: String)       # an item picked in the Build menu
signal speed_chosen(speed: int)
signal tax_changed(step: float)
signal tech_tax_changed(step: float)
signal new_city_pressed                      # New city in the game menu (the game then opens the dialog)
signal new_city_chosen(level: int)          # Start in the New city dialog (Settings.DIFFICULTIES index)
signal new_city_cancelled
signal borrow_pressed(amount: int)
signal repay_pressed(amount: int)           # -1 = everything owed
signal save_pressed
signal undo_pressed
signal load_pressed
signal example_chosen(id: String)           # a ready-made city picked in the game menu (Settings.EXAMPLES)
signal day_cycle_toggled(on: bool)
signal overlay_chosen(kind: int)
signal service_filter_chosen(service: int)  # the Services view's chips: -1 all, 0-3 police, fire, school, hospital
signal funding_changed(step: float)

const Settings = preload("res://scripts/settings.gd")
const Icons = preload("res://scripts/icons.gd")
const GLASS_SHADER = preload("res://shaders/glass.gdshader")
const BULLDOZE_TOOL := 4                   # (game3d.gd's Tool.BULLDOZE)
const ADVICE_URGENT := 3                   # (advisors.gd's URGENT; WARNING is 2, ADVICE 1)
const ADVICE_ROWS := 8                     # most tips the list can show
const ADVICE_REFLASH_MONTHS := 12          # an urgent tip flashes at most once a year

# Layout, on a 4-pixel grid.
const EDGE := 12.0                         # gap between the window edge and the glass
const GAP := 8.0                           # gap between pieces of glass
const ISLAND_H := 56.0                     # height of the pieces along the top
const SHADOW_PAD := 14.0                   # room round each panel for its shadow
const ROW_H := 60.0                        # a Build menu row
const FLYOUT_W := 336.0
const TICKER_MAX := 520.0

const ACCENT := Color(0.29, 0.58, 0.98)
const TEXT := Color(0.95, 0.96, 0.98)
const TEXT_DIM := Color(0.72, 0.76, 0.82)
const TEXT_FAINT := Color(0.58, 0.62, 0.69)
const GOOD := Color(0.47, 0.88, 0.60)
const BAD := Color(1.0, 0.48, 0.45)
const WARN := Color(1.0, 0.80, 0.38)
const HINT := Color(0.55, 0.75, 1.0)
const OVERLAY_NAMES := ["Normal", "Land value", "Power", "Roads", "Growth", "Services", "Water", "Districts", "Pollution",
	"Traffic"]
const OVERLAY_TIPS := ["The normal view",
	"What land is worth: the sea, parks and shops raise it; industry and power plants lower it",
	"Which plots have electricity, and what carries it",
	"How far each plot is from a road (zones need one within 2 tiles)",
	"Why each zone is or isn't growing",
	"How many of police, fire, schools and hospitals cover each area. Pick one to see where it's missing",
	"Which plots have water (anything bigger than a first-level plot needs it)",
	"CBD (skyscrapers allowed), Tech zones (their own tax rate) and conservation areas (low-rise only)",
	"Where the air is dirty: industry, coal and gas power, landfill and the harbour pollute; parks and woodland help",
	"How busy each road is with people driving to work and the shops. Busy roads need another way round, or buses"]
const OVERLAY_ICONS := ["eye", "value", "power", "roads", "growth", "services", "utilities", "districts", "pollution",
	"traffic"]
const SERVICES_VIEW := 5                   # (world3d.gd's Overlay.SERVICES)
# The Services view's chips: [service (-1 = all four), icon, label].
const SERVICE_CHIPS := [[-1, "services", "All"], [0, "police", "Police"], [1, "fire", "Fire"],
	[2, "school", "Schools"], [3, "hospital", "Hospitals"]]
const SERVICE_SHORT := ["Police", "Fire", "School", "Hospital"]   # the hover card's row

var _root: Control
var _bold: Font
var _icon_cache := {}
var _tweens := {}                          # Control -> Tween (fading in or out)
var _sim                                   # read for the demand bars
var _demand_colours := {}

# Top left: menu, date, speed.
var _left_island: PanelContainer
var _menu_button: Button
var _menu_panel: PanelContainer
var example_buttons: Dictionary = {}       # example id -> its row in the game menu
var _day_button: Button
var speed_buttons := {}
var undo_button: Button
var date_label: Label
var clock_label: Label

# Top right: the status strip, and the City panel behind it.
var _status_island: PanelContainer
var _city_button: Button
var city_panel: PanelContainer
var _city_scroll: ScrollContainer
var money_label: Label
var _net_label: Label
var _people_big: Label
var _jobs_small: Label
var _happy_big: Label
var _happy_small: Label
var _happy_icon: TextureRect
var _meters: Array[Control] = []           # power, water, services, rubbish
var _meter_value: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _meter_colour: Array[Color] = [TEXT_DIM, TEXT_DIM, TEXT_DIM, TEXT_DIM]
var demand_box: Control
var budget_label: Label                    # (City panel from here down)
var _budget_caption: Label
var _income_label: Label
var _upkeep_label: Label
var _loan_label: Label                     # loan payments last month
var _net_full_label: Label
var _debt_label: Label                     # Loans: what's owed...
var _loan_pay_label: Label                 # ...next month's payment
var _loan_note: Label
var borrow_buttons: Array[Button] = []     # one per Settings.BORROW_STEPS
var repay_button: Button
var repay_all_button: Button
var tax_label: Label
var tech_tax_label: Label            # the Tech zone's own tax rate (City panel)
var happiness_label: Label
var _happy_bar: Control
var _happy_value := 0.0
var people_label: Label
var housing_label: Label
var power_label: Label
var utility_label: Label                   # water
var services_label: Label
var rubbish_label: Label
var traffic_label: Label
var growth_label: Label

# Top centre: advisors.
var advice_panel: PanelContainer           # the ticker
var _ticker: Button
var _advice_count: Button
var _advice_list: PanelContainer
var _advice_title: Label
var _advice_rows: Array[Button] = []
var _advice_more: Label
var _advice_tips: Array[Dictionary] = []
var _advice_flashed := {}                  # tip id -> month it last flashed

# Bottom left: the Build dock.
var build_panel: PanelContainer
var _flyout: VBoxContainer
var _build_open := true
var bulldoze_button: Button
var _rail_buttons := {}                    # category id -> Button
var _rail_marks := {}                      # category id -> the little bar showing the tool in use
var _rows := {}                            # item id -> {button, name, desc, price, price_icon, pic, cat}
var _category := "all"
var _category_names := {}
var _selected_id := ""
var _list_title: Label
var _list_box: VBoxContainer
var _scroll: ScrollContainer
var funding_row: HBoxContainer
var funding_label: Label

# Bottom centre: what's under the mouse, and messages.
var _info_panel: PanelContainer
var _tool_pic: TextureRect
var _info_title: Label
var _info_ground: Label
var info_label: Label
var _info_action_row: HBoxContainer
var _info_action_icon: TextureRect
var _info_action: Label
var service_marks: HFlowContainer          # the hover card's row: police, fire, school, hospital, ticked or crossed
var _service_mark_icons: Array[TextureRect] = []
var _service_mark_labels: Array[Label] = []
var _toast: PanelContainer
var message_label: Label
var _message_time := 0.0

# Bottom right: map views.
var _overlay_panel: PanelContainer
var overlay_buttons := {}
var _overlay_caption: Label
var _legend_section: VBoxContainer
var _legend_title: Label
var _legend_tip: Label
var legend_box: VBoxContainer
var legend_note: Label                     # a line under the key (the Services view: how much one service reaches)
var service_chips := {}                    # service (-1 = all) -> Button, in the Services view
var _chip_row: HBoxContainer
var _overlay_kind := 0                     # the map view that's on
var _service_filter := -1                  # the service the Services view is showing (-1 = all)

var help_panel: PanelContainer
var _help_scroll: ScrollContainer
var _help_columns: HBoxContainer

# The New city dialog: pick a difficulty (centre, over a dimmed town).
var new_city_panel: PanelContainer
var _new_dim: ColorRect
var new_city_cards: Array[PanelContainer] = []
var _new_radios: Array[TextureRect] = []
var _new_level := Settings.DEFAULT_DIFFICULTY   # the card picked
var _new_hover := -1                           # the card under the mouse
var _new_warning: HBoxContainer
var new_city_start: Button
var new_city_cancel: Button
var _card_styles: Array[StyleBoxFlat] = []    # normal, hover, picked


func build(categories: Array, demand_colours: Dictionary, sim) -> void:
	# categories: [[id, name], ...] for the Build menu's side rail.
	_sim = sim
	_demand_colours = demand_colours
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = _make_theme()
	add_child(_root)
	_build_top_left()
	_build_status()
	_build_city_panel()
	_build_advice()
	_build_build_menu(categories)
	_build_info()
	_build_overlays()
	_build_help()
	_build_game_menu()
	_build_new_city()


func _process(delta: float) -> void:
	if _root == null:
		return
	if _message_time > 0.0:
		_message_time -= delta
		if _message_time <= 0.0:
			message_label.text = ""
	_toast.visible = message_label.text != ""
	_toast.modulate.a = clampf(_message_time / 0.35, 0.0, 1.0) if _message_time > 0.0 else 1.0
	_layout()


func _input(event: InputEvent) -> void:
	# While the New city dialog is open it takes every key: 1-3 or the arrows pick,
	# Enter starts, Esc cancels. Nothing reaches the game behind it.
	if is_modal() and event is InputEventKey:
		get_viewport().set_input_as_handled()
		var k := event as InputEventKey
		if k.pressed and not k.echo:
			_new_city_key(k.keycode)
		return
	# A click anywhere outside the game menu closes it (the click still goes through).
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed or _menu_panel == null or not _menu_panel.visible:
		return
	if not _menu_panel.get_global_rect().has_point(mb.position) \
			and not _menu_button.get_global_rect().has_point(mb.position):
		_close_menu()


# ------------------------------------------------------------------ layout

func _layout() -> void:
	# Place the pieces whose position depends on the others. Cheap, so it runs
	# every frame: it follows window resizes and panels changing size.
	var view := _root.size
	# Top centre: the ticker sits in the space between the two top pieces.
	var left_end := _left_island.position.x + _left_island.size.x
	var room := _status_island.position.x - left_end - GAP * 2.0
	advice_panel.visible = not _advice_tips.is_empty() and room >= 64.0
	if advice_panel.visible:
		_ticker.visible = room >= 150.0
		var w := minf(room, TICKER_MAX) if _ticker.visible else 0.0
		advice_panel.custom_minimum_size.x = w
		advice_panel.size = Vector2(w, ISLAND_H)
		advice_panel.position = Vector2(left_end + GAP + (room - advice_panel.size.x) * 0.5, EDGE)
	elif _advice_list.visible:
		_advice_count.button_pressed = false
	if _advice_list.visible:
		var lw := minf(maxf(advice_panel.size.x, 460.0), view.x - EDGE * 2.0)
		_advice_list.custom_minimum_size.x = lw
		_advice_list.size = Vector2(lw, 0.0)
		var cx := advice_panel.position.x + advice_panel.size.x * 0.5
		_advice_list.position = Vector2(clampf(cx - lw * 0.5, EDGE, view.x - EDGE - lw), EDGE + ISLAND_H + GAP)
	# Drop-downs under their buttons.
	if _menu_panel.visible:
		_menu_panel.position = Vector2(EDGE, EDGE + ISLAND_H + GAP)
	if city_panel.visible:
		# (It scrolls if the window is too short for it to clear the map views.)
		var overhead := city_panel.get_combined_minimum_size().y - _city_scroll.custom_minimum_size.y
		var room_h := _overlay_panel.position.y - GAP - (EDGE + ISLAND_H + GAP) - overhead
		var want_h := (_city_scroll.get_child(0) as Control).get_combined_minimum_size().y
		var h := minf(want_h, maxf(room_h, 120.0))
		if absf(_city_scroll.custom_minimum_size.y - h) > 0.5:
			_city_scroll.custom_minimum_size = Vector2(312.0, h)
		var pad := _city_scroll.get_child(0) as MarginContainer
		var gap := 10 if want_h > h + 0.5 else 0
		if pad.get_theme_constant("margin_right") != gap:
			pad.add_theme_constant_override("margin_right", gap)
		city_panel.size = Vector2(city_panel.custom_minimum_size.x, 0.0)
		city_panel.position = Vector2(view.x - EDGE - city_panel.size.x, EDGE + ISLAND_H + GAP)
	# Bottom centre: the info card fills the space between the Build dock and the
	# map views, up to a comfortable reading width.
	var dock_end := build_panel.position.x + build_panel.size.x
	var gap_w := _overlay_panel.position.x - dock_end - GAP * 2.0
	var card_w := clampf(gap_w, 260.0, 600.0)
	if _info_panel.custom_minimum_size.x != card_w:
		_info_panel.custom_minimum_size.x = card_w
		info_label.custom_minimum_size.x = card_w - 92.0
	_info_panel.size = Vector2(card_w, 0.0)
	_info_panel.position = Vector2(dock_end + GAP + (gap_w - card_w) * 0.5, view.y - EDGE - _info_panel.size.y)
	if _toast.visible:
		_toast.size = Vector2.ZERO
		_toast.position = Vector2(_info_panel.position.x + (card_w - _toast.size.x) * 0.5,
			_info_panel.position.y - GAP - _toast.size.y)
	# The New city dialog: centred.
	if new_city_panel.visible:
		new_city_panel.size = Vector2.ZERO
		new_city_panel.position = ((view - new_city_panel.size) * 0.5).floor()
	# Help: centred, and never taller than the window.
	if help_panel.visible:
		var want := _help_columns.get_combined_minimum_size()
		_help_scroll.custom_minimum_size = Vector2(minf(want.x + 16.0, view.x - EDGE * 2.0 - 28.0),
			minf(want.y, view.y - 220.0))
		help_panel.size = Vector2.ZERO
		help_panel.position = ((view - help_panel.size) * 0.5).floor()


func _build_top_left() -> void:
	_left_island = _panel(_root)
	_left_island.theme_type_variation = "Island"
	_left_island.position = Vector2(EDGE, EDGE)
	_left_island.custom_minimum_size.y = ISLAND_H
	var row := _hbox(_left_island, 10)

	_menu_button = _icon_button("menu", "Game menu: new city, save, load, help, day and night", true)
	_menu_button.toggled.connect(func(on: bool): _open(_menu_panel, on))
	row.add_child(_menu_button)

	var words := _stack(row)
	words.add_child(_label("Troon", 16, TEXT, true))
	var when := _hbox(words, 6)
	date_label = _label("", 12, TEXT_DIM)
	when.add_child(date_label)
	clock_label = _label("", 12, TEXT_FAINT)
	clock_label.custom_minimum_size = Vector2(36, 0)
	when.add_child(clock_label)

	row.add_child(_vline())
	var speeds := _hbox(row, 2)
	for s: int in [0, 1, Settings.FAST_SPEED]:
		var icon_id: String = {0: "pause", 1: "play", Settings.FAST_SPEED: "fast"}[s]
		var tip: String = {0: "Pause (Space)", 1: "Play (Space)", Settings.FAST_SPEED: "Fast (F)"}[s]
		var b := _icon_button(icon_id, tip, true)
		b.theme_type_variation = "Pause" if s == 0 else "Segment"
		b.pressed.connect(func(): speed_chosen.emit(s))
		speeds.add_child(b)
		speed_buttons[s] = b

	row.add_child(_vline())
	undo_button = _icon_button("undo", "Nothing to undo", false)
	undo_button.pressed.connect(func(): undo_pressed.emit())
	undo_button.disabled = true
	row.add_child(undo_button)


func _build_game_menu() -> void:
	# The drop-down under the menu button.
	_menu_panel = _panel(_root)
	_menu_panel.theme_type_variation = "Card"
	_menu_panel.visible = false
	var box := _vbox(_menu_panel, 2)
	for item: Array in [["new", "New city", "Clear the map and start again, picking how much money you start with"],
			["save", "Save", "Save the city (Ctrl or Cmd + S)"],
			["load", "Load", "Load the saved city (Ctrl or Cmd + L)"],
			["help", "How to play", "Controls and how the town works (H)"]]:
		var id: String = item[0]
		var b := _menu_row(id, item[1])
		b.tooltip_text = item[2]
		b.pressed.connect(func(): _menu_chosen(id))
		box.add_child(b)
	# Ready-made cities to load and carry on with.
	box.add_child(_divider())
	var head := _label("Example cities", 12, TEXT_FAINT)
	box.add_child(head)
	for item: Dictionary in Settings.EXAMPLES:
		var example: String = item["id"]
		var e := _menu_row("load", String(item["name"]))
		e.tooltip_text = "%s. Replaces the city on the map" % String(item["about"])
		e.pressed.connect(func():
			_close_menu()
			example_chosen.emit(example))
		box.add_child(e)
		example_buttons[example] = e
	box.add_child(_divider())
	_day_button = _menu_row("sun", "Day and night: on")
	_day_button.toggle_mode = true
	_day_button.button_pressed = true
	_day_button.tooltip_text = "Turn off to keep it daytime"
	_day_button.toggled.connect(func(on: bool):
		_day_button.text = "Day and night: %s" % ("on" if on else "off")
		day_cycle_toggled.emit(on))
	box.add_child(_day_button)


func _menu_chosen(id: String) -> void:
	_close_menu()
	match id:
		"new":
			new_city_pressed.emit()
		"save":
			save_pressed.emit()
		"load":
			load_pressed.emit()
		"help":
			help_panel.visible = not help_panel.visible


func _close_menu() -> void:
	_open(_menu_panel, false)
	_menu_button.set_pressed_no_signal(false)


func _menu_row(icon_id: String, text: String) -> Button:
	var b := Button.new()
	b.theme_type_variation = "MenuRow"
	b.text = text
	b.icon = _line_icon(icon_id, 18)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(200, 0)
	return b


# ------------------------------------------------------------ status strip

func _build_status() -> void:
	_status_island = _panel(_root)
	_status_island.theme_type_variation = "Island"
	_status_island.anchor_left = 1.0
	_status_island.anchor_right = 1.0
	_status_island.offset_left = -EDGE
	_status_island.offset_right = -EDGE
	_status_island.offset_top = EDGE
	_status_island.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_status_island.custom_minimum_size.y = ISLAND_H
	_status_island.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_status_island.tooltip_text = "Click for the City panel: budget, taxes, happiness and services"
	_status_island.gui_input.connect(func(e: InputEvent):
		var mb := e as InputEventMouseButton
		if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_city_button.button_pressed = not _city_button.button_pressed)
	var row := _hbox(_status_island, 14)

	# Money, and how it went last month.
	var money := _stack(row)
	money_label = _label("", 19, TEXT, true)
	money.add_child(money_label)
	_net_label = _label("", 12, TEXT_DIM)
	money.add_child(_net_label)
	row.add_child(_vline())

	# People and jobs.
	var people := _hbox(row, 7)
	people.add_child(_icon_rect("people", 20, TEXT_DIM))
	var pstack := _stack(people)
	_people_big = _label("", 16, TEXT, true)
	pstack.add_child(_people_big)
	_jobs_small = _label("", 12, TEXT_DIM)
	pstack.add_child(_jobs_small)

	# Happiness.
	var happy := _hbox(row, 7)
	_happy_icon = _icon_rect("smile", 20, GOOD)
	happy.add_child(_happy_icon)
	var hstack := _stack(happy)
	_happy_big = _label("", 16, TEXT, true)
	hstack.add_child(_happy_big)
	_happy_small = _label("", 12, TEXT_DIM)
	hstack.add_child(_happy_small)
	row.add_child(_vline())

	# Power, water, services, rubbish: an icon each with a little bar.
	var meters := _hbox(row, 2)
	for n: int in 4:
		var m := Control.new()
		m.custom_minimum_size = Vector2(28, 34)
		m.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		m.mouse_filter = Control.MOUSE_FILTER_PASS
		var icon_id: String = ["power", "utilities", "services", "bin"][n]
		m.draw.connect(func(): _draw_meter(m, n, icon_id))
		meters.add_child(m)
		_meters.append(m)
	row.add_child(_vline())

	# Demand for homes, shops, offices and industry.
	demand_box = Control.new()
	demand_box.custom_minimum_size = Vector2(84, 38)
	demand_box.mouse_filter = Control.MOUSE_FILTER_PASS
	demand_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	demand_box.draw.connect(_draw_demand)
	row.add_child(demand_box)

	_city_button = _icon_button("chevron", "City panel: budget, taxes, happiness and services", true)
	_city_button.theme_type_variation = "Flat"
	_city_button.custom_minimum_size = Vector2(28, 34)
	_city_button.toggled.connect(func(on: bool): _open(city_panel, on))
	row.add_child(_city_button)


func _build_city_panel() -> void:
	# Everything behind the status strip, one click away.
	city_panel = _panel(_root)
	city_panel.custom_minimum_size.x = 340
	city_panel.visible = false
	var outer := _vbox(city_panel, 6)
	var head := _hbox(outer, 8)
	var title := _label("City", 16, TEXT, true)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := _icon_button("close", "Close", false)
	close.theme_type_variation = "Flat"
	close.custom_minimum_size = Vector2(28, 28)
	close.pressed.connect(func(): _city_button.button_pressed = false)
	head.add_child(close)
	_city_scroll = ScrollContainer.new()
	_city_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(_city_scroll)
	# (A gap on the right when it scrolls, so the figures don't touch the scroll bar.)
	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_city_scroll.add_child(pad)
	var box := _vbox(pad, 6)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_budget_caption = _caption("Budget")
	_budget_caption.mouse_filter = Control.MOUSE_FILTER_PASS
	box.add_child(_budget_caption)
	_income_label = _pair(box, "Taxes last month")
	_upkeep_label = _pair(box, "Upkeep last month")
	_loan_label = _pair(box, "Loan payments last month")
	_net_full_label = _pair(box, "Balance last month")
	budget_label = _label("", 12, TEXT_FAINT)       # (the old one-line summary, kept but not shown)
	budget_label.visible = false
	box.add_child(budget_label)
	var tax_row := _hbox(box, 6)
	tax_label = _label("", 14, TEXT)
	tax_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tax_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tax_row.add_child(tax_label)
	tax_row.add_child(_small_button("–", "Lower taxes by 1%", func(): tax_changed.emit(-0.01)))
	tax_row.add_child(_small_button("+", "Raise taxes by 1%", func(): tax_changed.emit(0.01)))
	var tech_row := _hbox(box, 6)
	tech_tax_label = _label("", 13, TEXT)
	tech_tax_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tech_tax_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tech_tax_label.mouse_filter = Control.MOUSE_FILTER_PASS
	tech_tax_label.tooltip_text = "Offices and industry in a Tech zone pay this instead of the town's rate. " \
		+ "Below the town's, firms come from outside to fill the zone."
	tech_row.add_child(tech_tax_label)
	tech_row.add_child(_small_button("–", "Lower the Tech zone's tax by 1%", func(): tech_tax_changed.emit(-0.01)))
	tech_row.add_child(_small_button("+", "Raise the Tech zone's tax by 1%", func(): tech_tax_changed.emit(0.01)))

	# Loans: borrow when money is short; paid back a little each month.
	box.add_child(_divider())
	box.add_child(_caption("Loans"))
	_debt_label = _pair(box, "Owed")
	_loan_pay_label = _pair(box, "Monthly payment")
	_loan_note = _label("", 12, TEXT_FAINT)
	_loan_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_loan_note)
	var borrow_row := _hbox(box, 6)
	for step: int in Settings.BORROW_STEPS:
		var b := _wide_button("Borrow %s" % money_text(step), func(): borrow_pressed.emit(step))
		borrow_row.add_child(b)
		borrow_buttons.append(b)
	var repay_row := _hbox(box, 6)
	repay_button = _wide_button("Repay %s" % money_text(Settings.REPAY_STEP),
		func(): repay_pressed.emit(Settings.REPAY_STEP))
	repay_row.add_child(repay_button)
	repay_all_button = _wide_button("Repay all", func(): repay_pressed.emit(-1))
	repay_row.add_child(repay_all_button)

	box.add_child(_divider())
	box.add_child(_caption("Happiness"))
	_happy_bar = Control.new()
	_happy_bar.custom_minimum_size = Vector2(0, 8)
	_happy_bar.tooltip_text = "Below 50% nobody moves in; below 33% people leave"
	_happy_bar.draw.connect(_draw_happy_bar)
	box.add_child(_happy_bar)
	happiness_label = _label("", 13, TEXT)
	happiness_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(happiness_label)

	box.add_child(_divider())
	box.add_child(_caption("Services"))
	power_label = _service_row(box, "power")
	utility_label = _service_row(box, "utilities")
	services_label = _service_row(box, "services")
	rubbish_label = _service_row(box, "bin")
	traffic_label = _service_row(box, "traffic")

	box.add_child(_divider())
	box.add_child(_caption("Town"))
	people_label = _service_row(box, "people")
	housing_label = _service_row(box, "zones")
	growth_label = _service_row(box, "growth")


func _pair(box: VBoxContainer, key: String) -> Label:
	# "Key ........ value" on one line; returns the value label.
	var row := _hbox(box, 8)
	var k := _label(key, 13, TEXT_DIM)
	k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(k)
	var v := _label("", 14, TEXT, true)
	row.add_child(v)
	return v


func _service_row(box: VBoxContainer, icon_id: String) -> Label:
	# An icon and a line of text; the icon takes the row's colour (see _set_row_colour).
	var row := _hbox(box, 8)
	var icon := _icon_rect(icon_id, 16, TEXT_DIM)
	icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(icon)
	var text := _label("", 13, TEXT_DIM)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)
	return text


func _wide_button(text: String, action: Callable) -> Button:
	# A button that shares its row equally with the others.
	var b := _button(text, false)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(0, 32)
	b.add_theme_font_size_override("font_size", 13)
	b.pressed.connect(action)
	return b


func _small_button(text: String, tip: String, action: Callable) -> Button:
	var b := _button(text, false)
	b.tooltip_text = tip
	b.custom_minimum_size = Vector2(32, 30)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(action)
	return b


# ------------------------------------------------------------------ Build dock

func _build_build_menu(categories: Array) -> void:
	# A frosted dock, bottom left: a rail of category icons, and beside it a
	# flyout with the chosen category's items (picture, name, one line, price).
	build_panel = _panel(_root)
	build_panel.theme_type_variation = "Dock"
	build_panel.anchor_top = 1.0
	build_panel.anchor_bottom = 1.0
	build_panel.offset_left = EDGE
	build_panel.offset_top = -EDGE
	build_panel.offset_bottom = -EDGE
	build_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var row := _hbox(build_panel, 8)

	var rail := _vbox(row, 2)
	rail.size_flags_vertical = Control.SIZE_SHRINK_END
	for c: Array in categories:
		var id: String = c[0]
		var cat_name: String = c[1]
		_category_names[id] = cat_name
		var b := _rail_button(cat_name, id)
		b.tooltip_text = "Everything you can build" if id == "all" else "%s: what you can build" % cat_name
		b.pressed.connect(func(): _category_clicked(id))
		rail.add_child(b)
		_rail_buttons[id] = b
		_rail_marks[id] = b.get_child(0)
	rail.add_child(_divider())
	bulldoze_button = _rail_button("Bulldoze", "bulldoze")
	bulldoze_button.theme_type_variation = "Bulldoze"
	bulldoze_button.tooltip_text = "Bulldoze: clear anything you drag over (5 or B)"
	bulldoze_button.pressed.connect(func(): tool_chosen.emit(BULLDOZE_TOOL))
	rail.add_child(bulldoze_button)

	_flyout = _vbox(row, 6)
	_flyout.custom_minimum_size = Vector2(FLYOUT_W, 0)
	_flyout.size_flags_vertical = Control.SIZE_FILL    # as tall as the rail
	var head := _hbox(_flyout, 6)
	_list_title = _label("", 11, TEXT_DIM, true)
	_list_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_list_title)
	var close := _icon_button("close", "Hide the Build menu (M)", false)
	close.theme_type_variation = "Flat"
	close.custom_minimum_size = Vector2(28, 28)
	close.pressed.connect(func(): set_build_open(false))
	head.add_child(close)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.custom_minimum_size = Vector2(FLYOUT_W, ROW_H * 2)
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_flyout.add_child(_scroll)
	_list_box = _vbox(null, 2)
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_list_box)

	# Funding for the chosen service, under the list.
	funding_row = _hbox(_flyout, 6)
	funding_label = _label("", 12, TEXT)
	funding_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	funding_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	funding_row.add_child(funding_label)
	funding_row.add_child(_small_button("–", "Less funding: cheaper, but reaches less far (0% closes it)",
		func(): funding_changed.emit(-0.1)))
	funding_row.add_child(_small_button("+", "More funding: costs more, reaches further (up to 150%)",
		func(): funding_changed.emit(0.1)))
	funding_row.visible = false
	_show_category("all")


func _rail_button(text: String, icon_id: String) -> Button:
	# An icon with a small name under it. (Drawn by hand rather than with the
	# button's own icon and text, which pads them far apart.)
	var b := Button.new()
	b.theme_type_variation = "RailButton"
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(60, 44)
	# A small accent bar on the left marks the category of the tool in use.
	var mark := Panel.new()
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mark.add_theme_stylebox_override("panel", _soft_box(ACCENT, 2))
	mark.position = Vector2(0, 12)
	mark.size = Vector2(3, 20)
	mark.visible = false
	b.add_child(mark)
	var box := _vbox(b, 1)
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	var icon := _icon_rect(icon_id, 20, Color(1, 1, 1, 0.75))
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(icon)
	var label := _label(text, 11, TEXT_DIM)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(label)
	b.toggled.connect(func(_on: bool): _rail_look(b))
	b.mouse_entered.connect(func(): _rail_look(b, true))
	b.mouse_exited.connect(func(): _rail_look(b))
	return b


func _rail_look(b: Button, hovered: bool = false) -> void:
	# Brighter icon and name when it's open (or hovered).
	var box := b.get_child(1)
	var lit := b.button_pressed or hovered
	(box.get_child(0) as CanvasItem).modulate = Color.WHITE if lit else Color(1, 1, 1, 0.75)
	(box.get_child(1) as Label).add_theme_color_override("font_color", Color.WHITE if lit else TEXT_DIM)


func _rail_pressed(b: Button, on: bool) -> void:
	b.set_pressed_no_signal(on)
	_rail_look(b)


func _category_clicked(id: String) -> void:
	# Click a category to open it; click it again to fold the menu away.
	if _build_open and _category == id:
		set_build_open(false)
		return
	_show_category(id)
	set_build_open(true)


func set_build_open(on: bool) -> void:
	# The rail always shows; this opens or folds away the list of items.
	_build_open = on
	_open(_flyout, on)
	for k: String in _rail_buttons:
		_rail_pressed(_rail_buttons[k], on and k == _category)


func toggle_build_menu() -> void:
	set_build_open(not _build_open)


func set_items(items: Array) -> void:
	# items: [{id, cat, name, desc, about, price, locked}, ...]. Makes the rows the
	# first time, then just updates their text (prices and locks change as the
	# town grows).
	var first_time := _rows.is_empty()
	for item: Dictionary in items:
		var id: String = item["id"]
		if not _rows.has(id):
			_rows[id] = _make_row(item)
		var r: Dictionary = _rows[id]
		var locked: bool = item["locked"]
		(r["name"] as Label).text = item["name"]
		(r["name"] as Label).add_theme_color_override("font_color", TEXT_DIM if locked else TEXT)
		(r["desc"] as Label).text = item["desc"]
		(r["desc"] as Label).add_theme_color_override("font_color", WARN if locked else TEXT_DIM)
		(r["price"] as Label).text = item["price"]
		(r["price"] as Label).add_theme_color_override("font_color", TEXT_DIM if locked else TEXT)
		(r["price_icon"] as TextureRect).visible = locked
		(r["pic"] as Control).modulate = Color(1, 1, 1, 0.45 if locked else 1.0)
		(r["button"] as Button).tooltip_text = item["about"]
	if first_time:
		_show_category(_category)


func _make_row(item: Dictionary) -> Dictionary:
	var id: String = item["id"]
	var b := Button.new()
	b.theme_type_variation = "ItemRow"
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(FLYOUT_W - 12, ROW_H)
	b.pressed.connect(func(): build_item_chosen.emit(id))
	_list_box.add_child(b)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 6)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 5)
	margin.add_theme_constant_override("margin_bottom", 5)
	b.add_child(margin)
	var line := _hbox(margin, 12)
	# The picture, on a dark rounded tile.
	var tile := PanelContainer.new()
	tile.theme_type_variation = "IconTile"
	tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.custom_minimum_size = Vector2(48, 48)
	tile.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(tile)
	var pic := TextureRect.new()
	pic.texture = _item_icon(id)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.custom_minimum_size = Vector2(46, 46)
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(pic)
	# Name and one-line description.
	var words := _stack(line)
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name_label := _label("", 14, TEXT)
	words.add_child(name_label)
	var desc := _label("", 12, TEXT_DIM)
	desc.clip_text = true
	desc.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	desc.custom_minimum_size = Vector2(120, 0)
	words.add_child(desc)
	# Price (with a padlock while it's locked).
	var lock := _icon_rect("lock", 14, WARN)
	line.add_child(lock)
	var price := _label("", 14, TEXT, true)
	price.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(price)
	return {"button": b, "name": name_label, "desc": desc, "price": price, "price_icon": lock,
		"pic": tile, "cat": String(item["cat"])}


func _show_category(cat: String) -> void:
	_category = cat
	for k: String in _rail_buttons:
		_rail_pressed(_rail_buttons[k], _build_open and k == cat)
	var shown := 0
	for id: String in _rows:
		var r: Dictionary = _rows[id]
		var on: bool = cat == "all" or r["cat"] == cat
		(r["button"] as Button).visible = on
		if on:
			shown += 1
	var title: String = _category_names.get(cat, "")
	_list_title.text = ("Everything" if cat == "all" else title).to_upper() + "  ·  %d" % shown
	_scroll.scroll_vertical = 0


func set_selected(id: String) -> void:
	# Highlight the item being built. Only when the choice changes (a key, or the
	# Bulldoze button) does the menu jump to its category: the game refreshes this
	# every month, and that mustn't pull you away from a category you're browsing.
	var changed := id != _selected_id
	_selected_id = id
	for k: String in _rows:
		(_rows[k]["button"] as Button).set_pressed_no_signal(k == id)
	_rail_pressed(bulldoze_button, id == "bulldoze")
	var cat := ""
	if _rows.has(id) and id != "bulldoze":
		cat = _rows[id]["cat"]
	for k: String in _rail_marks:
		(_rail_marks[k] as Control).visible = k == cat
	_tool_pic.texture = _item_icon(id) if id != "" else null
	if _rows.has(id):
		_tool_pic.tooltip_text = "Building: %s" % (_rows[id]["name"] as Label).text
	if changed and _rows.has(id):
		var r: Dictionary = _rows[id]
		if _category != "all" and r["cat"] != _category:
			_show_category(r["cat"])
		_scroll.ensure_control_visible.call_deferred(r["button"])


func set_funding(text: String) -> void:
	funding_row.visible = text != ""
	funding_label.text = text


func _item_icon(id: String) -> Texture2D:
	# A picture rendered from the game's own models (tools/make_menu_pictures.py),
	# or the simple drawn icon if it's missing.
	var key := "item:" + id
	if not _icon_cache.has(key):
		var path := "res://assets/icons/%s.png" % id
		var picture: Texture2D = load(path) if ResourceLoader.exists(path) else null
		_icon_cache[key] = picture if picture else _svg(Icons.ITEMS.get(id, Icons.ITEMS["normal"]), 2.0)
	return _icon_cache[key]


func _line_icon(id: String, px: int) -> Texture2D:
	var key := "line:%s:%d" % [id, px]
	if not _icon_cache.has(key):
		_icon_cache[key] = _svg(Icons.LINES.get(id, Icons.LINES["all"]), px / 24.0)
	return _icon_cache[key]


func _svg(text: String, scale: float) -> Texture2D:
	var img := Image.new()
	img.load_svg_from_string(text, scale)
	return ImageTexture.create_from_image(img)


# ------------------------------------------------------------ info card

func _build_info() -> void:
	# Bottom centre: the tool in use (its picture), then what's under the mouse
	# and what building there would cost. Placed by _layout().
	_info_panel = _panel(_root)
	_info_panel.theme_type_variation = "Card"
	var row := _hbox(_info_panel, 12)
	var tile := PanelContainer.new()
	tile.theme_type_variation = "IconTile"
	tile.custom_minimum_size = Vector2(52, 52)
	tile.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(tile)
	_tool_pic = TextureRect.new()
	_tool_pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_tool_pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_tool_pic.custom_minimum_size = Vector2(50, 50)
	tile.add_child(_tool_pic)

	var box := _stack(row)
	box.add_theme_constant_override("separation", 3)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var head := _hbox(box, 10)
	_info_title = _label("", 14, TEXT, true)
	_info_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_info_title)
	_info_ground = _label("", 12, TEXT_FAINT)
	_info_ground.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	head.add_child(_info_ground)
	info_label = _label("", 13, TEXT_DIM)
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_label.custom_minimum_size = Vector2(300, 0)
	box.add_child(info_label)
	# Which services reach a zone plot: a tick or a cross each (red when the plot needs it).
	service_marks = HFlowContainer.new()
	service_marks.add_theme_constant_override("h_separation", 14)
	service_marks.add_theme_constant_override("v_separation", 2)
	service_marks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(service_marks)
	for s: int in 4:
		var cell := _hbox(service_marks, 3)
		var mark := _icon_rect("tick", 13, GOOD)
		cell.add_child(mark)
		var word := _label(SERVICE_SHORT[s], 12, TEXT)
		cell.add_child(word)
		_service_mark_icons.append(mark)
		_service_mark_labels.append(word)
	service_marks.visible = false
	_info_action_row = _hbox(box, 6)
	_info_action_icon = _icon_rect("value", 14, TEXT)
	_info_action_row.add_child(_info_action_icon)
	_info_action = _label("", 13, TEXT, true)
	_info_action.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_action.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_info_action_row.add_child(_info_action)

	# Messages pop up just above the card, then fade.
	_toast = _panel(_root)
	_toast.theme_type_variation = "Toast"
	_toast.visible = false
	message_label = _label("", 14, WARN, true)
	_toast.add_child(message_label)


func show_info(text: String) -> void:
	# A plain line: the drag preview with its cost, or "point at the map".
	_info_title.visible = false
	_info_ground.text = ""
	info_label.text = text
	info_label.visible = true
	info_label.add_theme_color_override("font_color", TEXT)
	_info_action_row.visible = false
	service_marks.visible = false


func show_query(text: String, ground: String, action: String, state: int, services: Array = []) -> void:
	# What's under the mouse. text: its first line is the title, the rest the
	# details; ground: the height (or "Sea"); action: what the tool would do there.
	# state: 0 = it can be built (and costs this), 1 = it can't (the reason), 2 = nothing to do.
	# services: for a zone plot, police, fire, school and hospital: 2 = covered,
	# 1 = not covered, 0 = not covered and the plot needs it ([] = no row).
	service_marks.visible = services.size() == 4
	for s: int in services.size():
		var v: int = services[s]
		var colour: Color = [BAD, TEXT_FAINT, GOOD][clampi(v, 0, 2)]
		_service_mark_icons[s].texture = _line_icon("tick" if v == 2 else "cross", 26)
		_service_mark_icons[s].modulate = colour
		_service_mark_labels[s].add_theme_color_override("font_color", TEXT if v == 2 else colour)
	var lines := text.split("\n")
	_info_title.visible = true
	_info_title.text = lines[0]
	_info_ground.text = ground
	lines.remove_at(0)
	info_label.text = "\n".join(lines)
	info_label.visible = not lines.is_empty()
	info_label.add_theme_color_override("font_color", TEXT_DIM)
	_info_action_row.visible = action != ""
	_info_action.text = action
	var colour: Color = [GOOD, BAD, TEXT_DIM][clampi(state, 0, 2)]
	_info_action.add_theme_color_override("font_color", colour)
	_info_action_icon.visible = state != 2
	_info_action_icon.texture = _line_icon("value" if state == 0 else "alert", 28)
	_info_action_icon.modulate = colour


func flash(text: String) -> void:
	message_label.text = text
	_message_time = 3.0


# ------------------------------------------------------------ map views

func _build_overlays() -> void:
	_overlay_panel = _panel(_root)
	_overlay_panel.theme_type_variation = "Card"
	_overlay_panel.anchor_left = 1.0
	_overlay_panel.anchor_right = 1.0
	_overlay_panel.anchor_top = 1.0
	_overlay_panel.anchor_bottom = 1.0
	_overlay_panel.offset_left = -EDGE
	_overlay_panel.offset_right = -EDGE
	_overlay_panel.offset_top = -EDGE
	_overlay_panel.offset_bottom = -EDGE
	_overlay_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_overlay_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var box := _vbox(_overlay_panel, 6)

	# The colour key for the view that's on (hidden for the normal view).
	_legend_section = _vbox(box, 4)
	_legend_section.visible = false
	_legend_title = _label("", 14, TEXT, true)
	_legend_section.add_child(_legend_title)
	_legend_tip = _label("", 12, TEXT_DIM)
	_legend_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_legend_tip.custom_minimum_size = Vector2(300, 0)
	_legend_section.add_child(_legend_tip)
	# The Services view: all four services, or one at a time (C cycles them).
	_chip_row = _hbox(_legend_section, 2)
	_chip_row.visible = false
	for chip: Array in SERVICE_CHIPS:
		var s: int = chip[0]
		var b := Button.new()
		b.theme_type_variation = "Chip"
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.text = chip[2]
		b.icon = _line_icon(chip[1], 28)
		b.expand_icon = false
		b.tooltip_text = "How many of the four services cover each spot (C: the next one)" if s < 0 \
			else "%s only: where it reaches and which plots still need it (C: the next one)" % String(chip[2])
		b.pressed.connect(func(): service_filter_chosen.emit(s))
		_chip_row.add_child(b)
		service_chips[s] = b
	legend_box = _vbox(_legend_section, 3)
	legend_note = _label("", 12, TEXT)
	legend_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	legend_note.custom_minimum_size = Vector2(300, 0)
	legend_note.visible = false
	_legend_section.add_child(legend_note)
	_legend_section.add_child(_divider())

	_overlay_caption = _label("", 11, TEXT_DIM, true)
	_overlay_caption.mouse_filter = Control.MOUSE_FILTER_PASS
	_overlay_caption.tooltip_text = "Map views: O switches to the next one"
	box.add_child(_overlay_caption)
	var chips := _hbox(box, 2)
	for kind: int in OVERLAY_NAMES.size():
		var b := _icon_button(OVERLAY_ICONS[kind], "%s: %s" % [OVERLAY_NAMES[kind], OVERLAY_TIPS[kind]], true)
		b.theme_type_variation = "Segment"
		b.pressed.connect(func(): overlay_chosen.emit(kind))
		chips.add_child(b)
		overlay_buttons[kind] = b


func set_overlay(kind: int, legend: Array, filter: int = -1, title: String = "", tip: String = "",
		note: String = "") -> void:
	# Highlight the chosen view and show its colour key. The Services view also
	# shows its chips (filter: the service it's showing, -1 = all); title, tip and
	# note replace the view's own name and line, and add a line under the key.
	_overlay_kind = kind
	_service_filter = filter if kind == SERVICES_VIEW else -1
	for k: int in overlay_buttons:
		(overlay_buttons[k] as Button).set_pressed_no_signal(k == kind)
	_chip_row.visible = kind == SERVICES_VIEW
	for s: int in service_chips:
		(service_chips[s] as Button).set_pressed_no_signal(s == _service_filter)
	var view: String = OVERLAY_NAMES[kind]
	_overlay_caption.text = "MAP VIEW  ·  %s" % view.to_upper()
	_legend_title.text = title if title != "" else view
	_legend_tip.text = tip if tip != "" else String(OVERLAY_TIPS[kind])
	legend_note.text = note
	legend_note.visible = note != ""
	for child: Node in legend_box.get_children():
		child.queue_free()
	for entry: Array in legend:
		var row := _hbox(legend_box, 8)
		var swatch := Panel.new()
		swatch.add_theme_stylebox_override("panel", _soft_box(entry[0], 3))
		swatch.custom_minimum_size = Vector2(12, 12)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(swatch)
		var text := _label(entry[1], 13, TEXT)
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(text)
	var on := kind != 0 and not legend.is_empty()
	# (Also while it's fading: switching views twice in a moment must leave it right.)
	if on != _legend_section.visible or _tweens.has(_legend_section):
		_open(_legend_section, on)


# ------------------------------------------------------------------ help

func _build_help() -> void:
	help_panel = _panel(_root)
	help_panel.visible = false
	var box := _vbox(help_panel, 10)
	var head := _hbox(box, 8)
	var title := _label("How to play", 20, TEXT, true)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := _icon_button("close", "Close (H)", false)
	close.theme_type_variation = "Flat"
	close.pressed.connect(func(): help_panel.visible = false)
	head.add_child(close)

	_help_scroll = ScrollContainer.new()
	_help_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(_help_scroll)
	_help_columns = _hbox(null, 28)
	_help_scroll.add_child(_help_columns)

	# Left: the controls, as a key / what-it-does table.
	var left := _vbox(_help_columns, 6)
	left.add_child(_caption("Controls"))
	var keys := GridContainer.new()
	keys.columns = 2
	keys.add_theme_constant_override("h_separation", 14)
	keys.add_theme_constant_override("v_separation", 5)
	left.add_child(keys)
	for pair: Array in [
			["Build", "Press, drag to see a preview and the cost, release to build (Esc cancels)"],
			["Roads", "Roads and power lines run straight and can turn one corner"],
			["Zones", "Zones, parks and woodland: drag a box. Start the drag ON a road to zone both sides of every road in the box, two plots deep"],
			["9", "Street grid: drag a box to lay streets with 100 m blocks"],
			["Tab", "Low, medium or high density for homes and shops; the next building in Power, Utilities, Leisure and Transport"],
			["1-0, -, =", "Tools (5 or B bulldozes, Z paints districts)"],
			["M", "Show or hide the Build menu"],
			["Space, F", "Pause or play; fast"],
			["O", "Next map view"],
			["C", "Services view: all four services, then police, fire, schools and hospitals one at a time"],
			["T", "Cars and people on the streets on or off"],
			["H", "This help"],
			["Ctrl/Cmd S, L", "Save, load"],
			["Ctrl/Cmd Z", "Undo the last build (up to 20, for a year); you get the money back"],
			["Move", "Two-finger scroll, middle-drag, or WASD"],
			["Turn", "Right-drag, or Q / E (rotate and tilt)"],
			["Zoom", "Pinch or scroll wheel"]]:
		var k := _label(pair[0], 13, TEXT, true)
		k.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		keys.add_child(k)
		var v := _label(pair[1], 13, TEXT_DIM)
		v.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.custom_minimum_size = Vector2(290, 0)
		keys.add_child(v)

	# Right: how the town works.
	var right := _vbox(_help_columns, 8)
	right.add_child(_caption("How the town works"))
	for para: String in [
			"Pick what to build in the Build menu, bottom left: categories down its side, the items beside them. Homes and shops come in low, medium and high density.",
			"Zones grow when a road is within %d tiles and they have power. Red icon = no road nearby; yellow lightning = no power. Power travels through roads, buildings and power lines that share an edge." % Settings.ROAD_REACH,
			"Power (6), Utilities (7), Leisure (-) and Transport (=) each have several buildings: pick one with Tab. Anything bigger than a first-level plot needs water (pumps and towers; it travels like power). Towns over 400 people need rubbish collected. Some buildings unlock as the town grows.",
			"Services (0): police, fire stations, schools and hospitals cover the area around them. They need a road and power. Bigger towns grow slowly without them; fires break out where there's no fire station. Funding (- / + under the Services list) changes how far they reach. While you place one, the map shows how far it would reach.",
			"Services view: the chips (or C) show one service at a time: green where it reaches, red where plots are held back without it, orange where it's missing but not holding them back yet. Pointing at a plot shows which services reach it.",
			"Taxes: people accept higher taxes when they get good services for them. High taxes with poor services stop growth, and eventually people leave (worst-served areas first). Change them in the City panel: click the strip, top right.",
			"Money: a new city starts Easy (%s), Normal (%s) or Hard (%s); harder levels also cost more to run and pay more interest. Short of money? Borrow in the City panel. Loans are paid back a little each month over about %d years, with interest; repay early to save interest. With no money left you can't build until taxes bring some in." % [
				money_text(_level_money(0)), money_text(_level_money(1)), money_text(_level_money(2)),
				roundi(Settings.LOAN_MONTHS / 12.0)],
			"Happiness (top right) sums it all up: taxes, services, jobs, homes, rubbish, power, water, polluted air and leisure. Below 50% people stop moving in; below 33% they leave.",
			"Advisors (top centre) point out what needs attention, most urgent first. Click a tip to see the problem on the map (click again to go back to the normal view).",
			"Map views (bottom right, or O): land value, power, roads, growth, services, water, districts, pollution and traffic, each with a colour key. They're always shown in daylight, so the colours read at night too.",
			"Districts (Z): paint a CBD where high-density plots can become skyscrapers (8,000 people and a station or bus depot nearby), a Tech zone whose offices and industry pay their own tax rate (set it in the City panel; below the town's draws firms in), or a conservation area kept low-rise.",
			"Low density grows villas and terraces; medium up to tenements, and mansion flats when space runs short; high density builds upwards to towers on valuable land. Land is worth more by the sea, near parks and shops, and less near industry and power plants. Scarce homes push prices up."]:
		var p := _label(para, 13, TEXT_DIM)
		p.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		p.custom_minimum_size = Vector2(400, 0)
		right.add_child(p)

	var ok := _button("Got it", false)
	ok.size_flags_horizontal = Control.SIZE_SHRINK_END
	ok.pressed.connect(func(): help_panel.visible = false)
	box.add_child(ok)


# ------------------------------------------------------------- New city dialog

func _build_new_city() -> void:
	# Three cards, one per difficulty (Settings.DIFFICULTIES): its name, a line
	# about it, the starting money, upkeep and loans. Over a dimmed town.
	_new_dim = ColorRect.new()
	_new_dim.color = Color(0.02, 0.03, 0.05, 0.45)
	_new_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_new_dim.mouse_filter = Control.MOUSE_FILTER_STOP     # (the map behind can't be clicked)
	_new_dim.visible = false
	_root.add_child(_new_dim)

	var normal := _soft_box(Color(1, 1, 1, 0.05), 12)
	normal.border_color = Color(1, 1, 1, 0.12)
	normal.set_border_width_all(1)
	normal.set_content_margin_all(14)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(1, 1, 1, 0.10)
	hover.border_color = Color(1, 1, 1, 0.22)
	var picked := normal.duplicate() as StyleBoxFlat
	picked.bg_color = Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.24)
	picked.border_color = ACCENT
	picked.set_border_width_all(2)
	_card_styles = [normal, hover, picked]

	new_city_panel = _panel(_root, 18.0)
	new_city_panel.visible = false
	var box := _vbox(new_city_panel, 14)
	var head := _vbox(box, 4)
	head.add_child(_label("New city", 20, TEXT, true))
	var sub := _label("Pick how much money you start with. Only money changes: the town grows the same way at every level.",
		13, TEXT_DIM)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.custom_minimum_size = Vector2(560, 0)
	head.add_child(sub)

	var cards := _hbox(box, 10)
	for level: int in Settings.DIFFICULTIES.size():
		cards.add_child(_difficulty_card(level))

	var foot := _hbox(box, 8)
	var left := _vbox(foot, 2)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.alignment = BoxContainer.ALIGNMENT_CENTER
	_new_warning = _hbox(left, 6)
	_new_warning.add_child(_icon_rect("alert", 14, WARN))
	_new_warning.add_child(_label("This clears everything you've built.", 12, WARN))
	left.add_child(_label("1, 2, 3 or arrow keys to pick  ·  Enter to start  ·  Esc to cancel", 12, TEXT_FAINT))
	new_city_cancel = _button("Cancel", false)
	new_city_cancel.custom_minimum_size = Vector2(96, 36)
	new_city_cancel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	new_city_cancel.pressed.connect(func(): _close_new_city(false))
	foot.add_child(new_city_cancel)
	new_city_start = _button("Start", false)
	new_city_start.theme_type_variation = "Primary"
	new_city_start.custom_minimum_size = Vector2(112, 36)
	new_city_start.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	new_city_start.pressed.connect(func(): _close_new_city(true))
	foot.add_child(new_city_start)


func _difficulty_card(level: int) -> PanelContainer:
	var info: Dictionary = Settings.DIFFICULTIES[level]
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(196, 0)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.gui_input.connect(func(e: InputEvent):
		var mb := e as InputEventMouseButton
		if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.double_click:
				_pick_level(level)
				_close_new_city(true)
			else:
				_pick_level(level))
	card.mouse_entered.connect(func():
		_new_hover = level
		_card_looks())
	card.mouse_exited.connect(func():
		if _new_hover == level:
			_new_hover = -1
		_card_looks())
	new_city_cards.append(card)
	var box := _vbox(card, 2)

	var top := _hbox(box, 8)
	var title := _label(String(info["name"]), 17, TEXT, true)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	var radio := TextureRect.new()
	radio.custom_minimum_size = Vector2(18, 18)
	radio.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	radio.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	radio.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	radio.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(radio)
	_new_radios.append(radio)
	var about := _label(String(info["about"]), 12, TEXT_DIM)
	about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	about.custom_minimum_size = Vector2(166, 34)
	box.add_child(about)

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 8)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(gap)
	box.add_child(_label(money_text(_level_money(level)), 24, TEXT, true))
	box.add_child(_label("to start with", 12, TEXT_FAINT))
	box.add_child(_divider())
	var upkeep: float = info["upkeep"]
	var rate: float = info["loan_rate"]
	var limit: int = info["loan_limit"]
	for pair: Array in [["Upkeep", upkeep_words(upkeep)], ["Loan interest", "%d%% a year" % roundi(rate * 100.0)],
			["Borrow up to", money_text(limit)]]:
		var row := _hbox(box, 8)
		var k := _label(pair[0], 12, TEXT_DIM)
		k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(k)
		row.add_child(_label(pair[1], 13, TEXT, true))
	return card


func _level_money(level: int) -> int:
	var info: Dictionary = Settings.DIFFICULTIES[level]
	var amount: int = info["money"]
	return amount


func open_new_city(first: bool) -> void:
	# first: the game has just opened (Cancel then just starts on Normal), so
	# there's nothing to clear. The game pauses itself while this is open.
	_new_level = Settings.DEFAULT_DIFFICULTY
	_new_hover = -1
	_new_warning.visible = not first
	new_city_cancel.tooltip_text = "Start on Normal" if first else "Keep the city you have"
	_close_menu()
	help_panel.visible = false
	_card_looks()
	_open(_new_dim, true)
	_open(new_city_panel, true)


func is_modal() -> bool:
	return new_city_panel != null and new_city_panel.visible


func new_city_level() -> int:
	return _new_level


func _pick_level(level: int) -> void:
	_new_level = clampi(level, 0, Settings.DIFFICULTIES.size() - 1)
	_card_looks()


func _card_looks() -> void:
	for n: int in new_city_cards.size():
		var style := 2 if n == _new_level else (1 if n == _new_hover else 0)
		new_city_cards[n].add_theme_stylebox_override("panel", _card_styles[style])
		_new_radios[n].texture = _radio_icon(n == _new_level)
	new_city_start.text = "Start on %s" % String(Settings.DIFFICULTIES[_new_level]["name"])


func _new_city_key(code: Key) -> void:
	match code:
		KEY_1, KEY_KP_1:
			_pick_level(0)
		KEY_2, KEY_KP_2:
			_pick_level(1)
		KEY_3, KEY_KP_3:
			_pick_level(2)
		KEY_LEFT, KEY_UP:
			_pick_level(_new_level - 1)
		KEY_RIGHT, KEY_DOWN:
			_pick_level(_new_level + 1)
		KEY_TAB:
			_pick_level((_new_level + 1) % Settings.DIFFICULTIES.size())
		KEY_ENTER, KEY_KP_ENTER:
			_close_new_city(true)
		KEY_ESCAPE:
			_close_new_city(false)


func _close_new_city(start: bool) -> void:
	if not is_modal():
		return
	for c: Control in [_new_dim, new_city_panel]:
		if _tweens.has(c):
			(_tweens[c] as Tween).kill()
			_tweens.erase(c)
		c.visible = false
		c.modulate.a = 1.0
	if start:
		new_city_chosen.emit(_new_level)
	else:
		new_city_cancelled.emit()


func _radio_icon(on: bool) -> Texture2D:
	var key := "radio:%s" % on
	if not _icon_cache.has(key):
		var svg := "<svg xmlns='http://www.w3.org/2000/svg' width='18' height='18'>"
		if on:
			svg += "<circle cx='9' cy='9' r='8' fill='#%s'/><circle cx='9' cy='9' r='3.5' fill='#ffffff'/>" % ACCENT.to_html(false)
		else:
			svg += "<circle cx='9' cy='9' r='7.25' fill='none' stroke='#ffffff' stroke-opacity='0.4' stroke-width='1.5'/>"
		_icon_cache[key] = _svg(svg + "</svg>", 2.0)
	return _icon_cache[key]


# ----------------------------------------------------------------- updates

func set_speed(speed: int) -> void:
	for k: int in speed_buttons:
		(speed_buttons[k] as Button).set_pressed_no_signal(k == speed)
	clock_label.add_theme_color_override("font_color", WARN if speed == 0 else TEXT_FAINT)


func set_undo(tip: String) -> void:
	# tip: what Undo would do ("" = nothing to undo: the button is greyed out).
	if undo_button == null:
		return
	undo_button.disabled = tip == ""
	undo_button.tooltip_text = tip if tip != "" else "Nothing to undo"
	undo_button.modulate.a = 1.0 if tip != "" else 0.35


func set_clock(text: String) -> void:
	clock_label.text = text


func show_city(sim, money_str: String, net_text: String, income_text: String, upkeep_text: String) -> void:
	date_label.text = sim.date_text()
	var low: bool = sim.money < Settings.LOW_MONEY
	money_label.text = money_str
	money_label.add_theme_color_override("font_color", BAD if low else TEXT)
	var net: int = sim.last_balance()      # taxes - upkeep - loan payments
	var net_colour := GOOD if net > 0 else (BAD if net < 0 else TEXT_DIM)
	_net_label.text = "%s last month" % net_text
	_net_label.add_theme_color_override("font_color", net_colour)
	budget_label.text = "%s last month   ·   taxes %s, upkeep %s" % [net_text, income_text, upkeep_text]
	var level: String = sim.difficulty_name()
	_budget_caption.text = "BUDGET  ·  %s" % level.to_upper()
	_budget_caption.tooltip_text = "%s: chosen when the city was started. Running costs %s, loans at %d%% a year." % [
		level, upkeep_words(sim.upkeep_scale()), roundi(sim.loan_rate() * 100.0)]
	_income_label.text = income_text
	_upkeep_label.text = upkeep_text
	var loan_paid: int = sim.last_loan
	_loan_label.text = money_text(loan_paid)
	_net_full_label.text = net_text
	_net_full_label.add_theme_color_override("font_color", net_colour)
	_show_loans(sim)

	var pop: int = sim.population
	var jobs: int = sim.jobs()
	_people_big.text = thousands(pop)
	_jobs_small.text = "%s jobs" % thousands(jobs)
	people_label.text = "%s people   ·   %s jobs" % [thousands(pop), thousands(jobs)]

	# Happiness sums everything up; when it slips, say what residents mind most
	# and what would help.
	var happy: float = sim.happiness
	_happy_value = happy
	var word: String = sim.happiness_word()
	var happy_colour := BAD if happy < 0.5 else (GOOD if happy >= 0.6 else WARN)
	_happy_big.text = "%d%%" % roundi(happy * 100.0)
	_happy_small.text = word.get_slice(",", 0)
	_happy_small.add_theme_color_override("font_color", happy_colour)
	_happy_icon.modulate = happy_colour
	happiness_label.text = "%d%%: %s" % [roundi(happy * 100.0), word]
	var keys: Array[String] = sim.complaint_keys(2)
	if not keys.is_empty() and happy < 0.8:
		var lines: Array[String] = []
		for key: String in keys:
			var what: String = sim.complaint_text(key)
			var fix: String = sim.complaint_fix(key)
			lines.append("%s%s: %s" % [what.left(1).to_upper(), what.substr(1), fix])
		happiness_label.text += "\nMain complaint%s:\n%s" % ["s" if lines.size() > 1 else "", "\n".join(lines)]
	happiness_label.add_theme_color_override("font_color", BAD if happy < 0.5 else TEXT)
	_happy_bar.queue_redraw()

	var short: float = sim.housing_shortage()
	var shortage := "none" if short <= 0.0 else ("some" if short < 0.4 else ("serious" if short < 0.8 else "severe"))
	if sim.average_home_price > 0:
		housing_label.text = "Average home £%s   ·   housing shortage: %s" % [thousands(sim.average_home_price), shortage]
	else:
		housing_label.text = "Housing shortage: %s" % shortage
	_set_row_colour(housing_label, BAD if short >= 0.4 else TEXT_DIM)
	_set_row_colour(people_label, TEXT_DIM)

	# Power.
	var power_frac := 0.0
	var power_colour := BAD
	if sim.plants == 0:
		power_label.text = "No power plant yet: build one to start growing"
	else:
		power_label.text = "Power: %s of %s used" % [thousands(sim.power_used), thousands(sim.power_supply)]
		power_frac = clampf(float(sim.power_used) / maxf(sim.power_supply, 1.0), 0.0, 1.0)
		power_colour = BAD if sim.power_used > sim.power_supply * 0.9 else GOOD
	_set_row_colour(power_label, power_colour)
	_set_meter(0, power_frac, power_colour, power_label.text)

	# Water.
	var water_frac := 0.0
	var dry: bool = (sim.water_supply == 0 and sim.population > 0) or sim.water_used > sim.water_supply * 0.9
	if sim.water_supply == 0:
		utility_label.text = "Water: no water supply yet"
	else:
		utility_label.text = "Water: %s of %s used" % [thousands(sim.water_used), thousands(sim.water_supply)]
		water_frac = clampf(float(sim.water_used) / maxf(sim.water_supply, 1.0), 0.0, 1.0)
	var water_colour := BAD if dry else (GOOD if sim.water_supply > 0 else TEXT_DIM)
	_set_row_colour(utility_label, water_colour)
	_set_meter(1, water_frac, water_colour, utility_label.text)

	# Services.
	var service_word: String = sim.services_word()
	if service_word == "none yet":
		services_label.text = "Services: none yet (build a police or fire station)"
	elif service_word == "not needed yet":
		services_label.text = "Services: not needed yet"
	else:
		services_label.text = "Services: %s (%d%% cover)" % [service_word, roundi(sim.service_score * 100.0)]
	var service_colour := TEXT_DIM
	if service_word in ["poor", "none yet", "not reaching homes"]:
		service_colour = BAD
	elif service_word == "patchy":
		service_colour = WARN
	elif service_word in ["good", "excellent"]:
		service_colour = GOOD
	_set_row_colour(services_label, service_colour)
	_set_meter(2, sim.service_score, service_colour, services_label.text)

	# Rubbish.
	var piling: float = sim.rubbish_shortfall()
	rubbish_label.text = "Rubbish: %s" % sim.rubbish_word()
	if piling > 0.3:
		rubbish_label.text += " (build a landfill, recycling or incinerator)"
	elif sim.population >= Settings.RUBBISH_START_POP and sim.rubbish_capacity > 0:
		# How much room is left at the tips: "all collected, 35% room to spare".
		var spare := 100 - roundi(minf(float(sim.rubbish_made) / sim.rubbish_capacity, 1.0) * 100.0)
		rubbish_label.text += ", %d%% room to spare" % spare
	var collecting: bool = sim.population >= Settings.RUBBISH_START_POP
	var rubbish_colour := TEXT_DIM
	if collecting:
		rubbish_colour = BAD if piling > 0.3 else (WARN if piling > 0.0 else GOOD)
	_set_row_colour(rubbish_label, rubbish_colour)
	_set_meter(3, 1.0 - piling if collecting else 0.0, rubbish_colour, rubbish_label.text)

	# Traffic (shown only for now: jams don't hold anything back yet).
	var jams: float = sim.traffic_jammed_share()
	var car_trips: int = sim.traffic_trips
	var transit: int = sim.transit_trips
	if car_trips <= 0:
		traffic_label.text = "Traffic: none yet"
	else:
		traffic_label.text = "Traffic: %d%% of trips in jams   ·   %s car trips a day" % [roundi(jams * 100.0),
			thousands(car_trips)]
		if transit > 0:
			traffic_label.text += ", %s by bus or train" % thousands(transit)
	traffic_label.tooltip_text = "The Traffic map view shows which roads are busy"
	_set_row_colour(traffic_label, BAD if jams >= Settings.TRAFFIC_JAM_WARN else (
		WARN if jams >= Settings.TRAFFIC_JAM_TIP else (GOOD if car_trips > 0 else TEXT_DIM)))

	growth_label.text = "Last month: %d plots grew, %d shrank" % [sim.grew.size(), sim.shrank.size()]
	if sim.abandoned_count > 0:
		growth_label.text += "   ·   %d abandoned" % sim.abandoned_count
	if sim.run_down_count > 0:
		growth_label.text += "   ·   %d run down" % sim.run_down_count
	_set_row_colour(growth_label, BAD if sim.abandoned_count > 0 else TEXT_DIM)

	tax_label.text = "Tax rate %d%%: %s" % [roundi(sim.tax_rate * 100.0), sim.tax_word()]
	tax_label.add_theme_color_override("font_color", BAD if sim.business_appeal() < 0.3 else TEXT)
	var has_tech: bool = sim.has_tech_zone()
	tech_tax_label.text = "Tech zone tax %d%%: %s" % [roundi(sim.tech_tax_rate * 100.0), sim.tech_word()]
	if has_tech:
		var tech_jobs: int = sim.tech_zone_jobs()
		tech_tax_label.text += "\n%s jobs there" % thousands(tech_jobs)
		if sim.last_tech_relief > 0:
			tech_tax_label.text += " · the break cost %s last month" % money_text(sim.last_tech_relief)
	tech_tax_label.add_theme_color_override("font_color", TEXT if has_tech else TEXT_DIM)

	# Demand, in words for the tooltip.
	var parts: Array[String] = []
	for t: int in _demand_colours:
		var v: float = sim.demand_bar(t)
		var label: String = _demand_colours[t][1]
		parts.append("%s: %s" % [label, "wanted" if v > 0.1 else ("too many" if v < -0.1 else "steady")])
	demand_box.tooltip_text = "Demand (bars up: wanted; down: too many)\n" + "\n".join(parts)
	demand_box.queue_redraw()


func _show_loans(sim) -> void:
	# The Loans block: what's owed, next month's payment, and the buttons (each
	# greyed out, with the reason on hover, when it can't be used just now).
	var owed: int = sim.debt
	var rate := roundi(sim.loan_rate() * 100.0)
	var limit: int = sim.loan_limit()
	_debt_label.text = money_text(owed) if owed > 0 else "Nothing"
	_debt_label.add_theme_color_override("font_color", TEXT if owed > 0 else TEXT_DIM)
	if owed > 0:
		var interest: int = sim.loan_interest()
		_loan_pay_label.text = money_text(sim.loan_payment())
		_loan_pay_label.tooltip_text = "%s interest and %s paid back" % [money_text(interest),
			money_text(sim.loan_repayment())]
	else:
		_loan_pay_label.text = "None"
		_loan_pay_label.tooltip_text = ""
	_loan_pay_label.add_theme_color_override("font_color", TEXT if owed > 0 else TEXT_DIM)
	_loan_pay_label.mouse_filter = Control.MOUSE_FILTER_PASS
	var limit_hit := false
	for n: int in borrow_buttons.size():
		var step: int = Settings.BORROW_STEPS[n]
		var why: String = sim.borrow_problem(step)
		var b := borrow_buttons[n]
		b.disabled = why != ""
		b.tooltip_text = "Can't borrow %s: %s" % [money_text(step), why] if why != "" \
			else "Borrow %s now. Paid back over about %d years, with %d%% interest a year." % [
				money_text(step), roundi(Settings.LOAN_MONTHS / 12.0), rate]
		limit_hit = limit_hit or why != ""
	if limit_hit:
		var room: int = limit - owed
		_loan_note.text = "%d%% a year. You can owe at most %s on %s%s." % [rate, money_text(limit),
			sim.difficulty_name(), "" if room <= 0 else ": %s more can be borrowed" % money_text(room)]
	else:
		_loan_note.text = "%d%% a year, paid back a little each month over about %d years. You can owe up to %s." % [
			rate, roundi(Settings.LOAN_MONTHS / 12.0), money_text(limit)]
	_loan_note.add_theme_color_override("font_color", WARN if limit_hit else TEXT_FAINT)
	for pair: Array in [[repay_button, Settings.REPAY_STEP], [repay_all_button, -1]]:
		var b: Button = pair[0]
		var amount: int = pair[1]
		var why: String = sim.repay_problem(amount)
		b.disabled = why != ""
		var what := "everything owed" if amount < 0 else money_text(amount)
		b.tooltip_text = "Can't repay %s: %s" % [what, why] if why != "" \
			else "Pay back %s now, from the town's money (saves interest)" % what


static func upkeep_words(scale: float) -> String:
	# 0.8 -> "20% less", 1.0 -> "as usual", 1.25 -> "25% more".
	if is_equal_approx(scale, 1.0):
		return "as usual"
	return "%d%% %s" % [roundi(absf(scale - 1.0) * 100.0), "less" if scale < 1.0 else "more"]


func _set_row_colour(label: Label, colour: Color) -> void:
	# A City panel row: the text stays quiet when all is well; the icon shows the colour.
	label.add_theme_color_override("font_color", TEXT_DIM if colour == GOOD else colour)
	var icon := label.get_parent().get_child(0) as TextureRect
	if icon:
		icon.modulate = colour


func _set_meter(n: int, value: float, colour: Color, tip: String) -> void:
	_meter_value[n] = value
	_meter_colour[n] = colour
	_meters[n].tooltip_text = tip
	_meters[n].queue_redraw()


func _draw_meter(m: Control, n: int, icon_id: String) -> void:
	# An icon, and a little bar under it: how full, coloured red, amber or green.
	var colour := _meter_colour[n]
	var s := 18.0
	m.draw_texture_rect(_line_icon(icon_id, 40), Rect2((m.size.x - s) * 0.5, 4, s, s), false, colour)
	var bar := Rect2(5, 27, m.size.x - 10, 3)
	m.draw_rect(bar, Color(1, 1, 1, 0.16))
	m.draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(_meter_value[n], 0.0, 1.0), bar.size.y)), colour)


func _draw_happy_bar() -> void:
	var size := _happy_bar.size
	var r := Rect2(0, 1, size.x, 6)
	_happy_bar.draw_rect(r, Color(1, 1, 1, 0.12))
	var colour := BAD if _happy_value < 0.5 else (GOOD if _happy_value >= 0.6 else WARN)
	_happy_bar.draw_rect(Rect2(r.position, Vector2(size.x * clampf(_happy_value, 0.0, 1.0), 6)), colour)
	for mark: float in [1.0 / 3.0, 0.5]:      # people leave below a third; stop coming below half
		_happy_bar.draw_rect(Rect2(floorf(size.x * mark), 0, 1, 8), Color(1, 1, 1, 0.55))


func _draw_demand() -> void:
	# A bar per zone round a zero line (up: wanted, down: too many), labelled H S O I.
	if _sim == null:
		return
	var size := demand_box.size
	var mid := 15.0
	demand_box.draw_line(Vector2(0, mid), Vector2(size.x, mid), Color(1, 1, 1, 0.3), 1.0)
	var keys := _demand_colours.keys()
	var col_w := size.x / keys.size()
	for n: int in keys.size():
		var t: int = keys[n]
		var value: float = _sim.demand_bar(t)
		var reach := 13.0 if value > 0.0 else 10.0
		var bar_h := maxf(absf(value) * reach, 1.5)
		var x := n * col_w + (col_w - 10.0) * 0.5
		var top := mid - bar_h if value > 0.0 else mid
		var colour: Color = _demand_colours[t][0]
		demand_box.draw_rect(Rect2(x, top, 10.0, bar_h), colour)
		var letter: String = String(_demand_colours[t][1]).left(1)
		demand_box.draw_string(_bold, Vector2(n * col_w, size.y - 1), letter,
			HORIZONTAL_ALIGNMENT_CENTER, col_w, 11, TEXT_DIM)


# ---------------------------------------------------------------- advisors

func _build_advice() -> void:
	# A ticker, top centre: the most urgent tip and a count. Click the tip to see
	# it on the map; click the count for the full list. Hidden when there's
	# nothing to say.
	advice_panel = _panel(_root)
	advice_panel.theme_type_variation = "Island"
	advice_panel.visible = false
	var row := _hbox(advice_panel, 4)
	_ticker = _advice_row()
	_ticker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ticker.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_ticker.custom_minimum_size = Vector2.ZERO
	_ticker.pressed.connect(func(): _advice_clicked(0))
	row.add_child(_ticker)
	_advice_count = Button.new()
	_advice_count.theme_type_variation = "Count"
	_advice_count.focus_mode = Control.FOCUS_NONE
	_advice_count.toggle_mode = true
	_advice_count.icon = _line_icon("chevron", 16)
	_advice_count.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_advice_count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_advice_count.toggled.connect(func(on: bool): _open(_advice_list, on))
	row.add_child(_advice_count)

	_advice_list = _panel(_root)
	_advice_list.theme_type_variation = "Card"
	_advice_list.visible = false
	var box := _vbox(_advice_list, 2)
	_advice_title = _label("", 11, TEXT_DIM, true)
	box.add_child(_advice_title)
	for n: int in ADVICE_ROWS:
		var b := _advice_row()
		b.pressed.connect(func(): _advice_clicked(n))
		box.add_child(b)
		_advice_rows.append(b)
	_advice_more = _label("", 12, TEXT_DIM)
	box.add_child(_advice_more)


func _advice_row() -> Button:
	# A flat, left-aligned row that lights up on hover. One line; the full
	# explanation is in its tooltip.
	var b := Button.new()
	b.theme_type_variation = "AdviceRow"
	b.focus_mode = Control.FOCUS_NONE
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.clip_text = true
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	b.custom_minimum_size = Vector2(300, 0)
	return b


func set_advice(tips: Array[Dictionary], month: int) -> void:
	# tips: from advisors.gd, most urgent first. The ticker always shows the top
	# tip; an urgent tip also flashes once, then not again for a year, so it
	# doesn't nag. (It waits if another message is showing.)
	_advice_tips = tips
	if _message_time <= 0.0:
		for tip: Dictionary in tips:
			var severity: int = tip["severity"]
			if severity < ADVICE_URGENT:
				break
			var id: String = tip["id"]
			var last: int = _advice_flashed.get(id, -ADVICE_REFLASH_MONTHS)
			if month < last or month - last >= ADVICE_REFLASH_MONTHS:   # (a new city starts at 0)
				_advice_flashed[id] = month
				flash("Advisor: %s" % tip["text"])
				break
	_show_advice()


func _show_advice() -> void:
	var total := _advice_tips.size()
	if total == 0:
		advice_panel.visible = false
		_advice_count.button_pressed = false
		return
	var urgent := 0
	for tip: Dictionary in _advice_tips:
		var severity: int = tip["severity"]
		if severity >= ADVICE_URGENT:
			urgent += 1
	_fill_advice_row(_ticker, _advice_tips[0])
	_advice_count.text = str(total)
	_advice_count.tooltip_text = "All %d of the advisors' tips%s" % [total,
		", %d urgent" % urgent if urgent > 0 else ""]
	_advice_count.add_theme_color_override("font_color", BAD if urgent > 0 else TEXT)
	_advice_title.text = "ADVISORS  ·  %d %s" % [total, "tip" if total == 1 else "tips"]
	if urgent > 0:
		_advice_title.text += ", %d urgent" % urgent
	_advice_title.add_theme_color_override("font_color", BAD if urgent > 0 else TEXT_DIM)
	for n: int in _advice_rows.size():
		var b := _advice_rows[n]
		b.visible = n < total
		if b.visible:
			_fill_advice_row(b, _advice_tips[n])
	_advice_more.visible = total > ADVICE_ROWS
	_advice_more.text = "and %d more" % (total - ADVICE_ROWS)


func _fill_advice_row(b: Button, tip: Dictionary) -> void:
	var severity: int = tip["severity"]
	var overlay: int = tip["overlay"]
	var colour := BAD if severity >= ADVICE_URGENT else (WARN if severity == ADVICE_URGENT - 1 else HINT)
	b.text = tip["text"]
	b.icon = _dot_icon(colour)
	b.tooltip_text = String(tip["detail"])
	if overlay >= 0:
		var view: String = OVERLAY_NAMES[overlay]
		var filter: int = tip.get("filter", -1)
		if filter >= 0:
			b.tooltip_text += "\nClick to see it on the map (Services view, %s only)." \
				% String(SERVICE_CHIPS[filter + 1][2]).to_lower()
		else:
			b.tooltip_text += "\nClick to see it on the %s map view." % view.to_lower()
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if overlay >= 0 else Control.CURSOR_ARROW


func _advice_clicked(n: int) -> void:
	# Switch on the map view that shows the problem (or back to normal if it's on).
	if n >= _advice_tips.size():
		return
	var kind: int = _advice_tips[n]["overlay"]
	if kind < 0:
		return
	# A tip about one service opens the Services view showing just that service.
	var filter: int = _advice_tips[n].get("filter", -1)
	if kind == _overlay_kind and filter == _service_filter:
		overlay_chosen.emit(0)
		return
	overlay_chosen.emit(kind)
	if kind == SERVICES_VIEW:
		service_filter_chosen.emit(filter)


func _dot_icon(colour: Color) -> Texture2D:
	var key := "dot:" + colour.to_html(false)
	if not _icon_cache.has(key):
		_icon_cache[key] = _svg("<svg xmlns='http://www.w3.org/2000/svg' width='12' height='12'>"
			+ "<circle cx='6' cy='6' r='4' fill='#%s'/></svg>" % colour.to_html(false), 1.0)
	return _icon_cache[key]


# ----------------------------------------------------------------- pieces

func _panel(parent: Control, radius: float = 14.0) -> PanelContainer:
	# A frosted glass panel. The glass is drawn by a ColorRect behind the
	# contents, stretched over the whole panel (plus room for its shadow)
	# whenever it's laid out.
	var panel := PanelContainer.new()
	var glass := ColorRect.new()
	glass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = GLASS_SHADER
	mat.set_shader_parameter("radius", radius)
	mat.set_shader_parameter("pad", SHADOW_PAD)
	glass.material = mat
	panel.add_child(glass)
	panel.sort_children.connect(func():
		glass.position = -Vector2(SHADOW_PAD, SHADOW_PAD)
		glass.size = panel.size + Vector2(SHADOW_PAD, SHADOW_PAD) * 2.0
		mat.set_shader_parameter("size", panel.size))
	parent.add_child(panel)
	return panel


func _open(c: Control, on: bool) -> void:
	# Show or hide with a quick fade.
	if _tweens.has(c):
		(_tweens[c] as Tween).kill()
		_tweens.erase(c)
	if on:
		if not c.visible:
			c.modulate.a = 0.0
		c.visible = true
		if c.get_parent() == _root:
			c.move_to_front()      # a drop-down goes over everything else
		var t := create_tween()
		t.tween_property(c, "modulate:a", 1.0, 0.12)
		_tweens[c] = t
	elif c.visible:
		var t := create_tween()
		t.tween_property(c, "modulate:a", 0.0, 0.09)
		t.tween_callback(func():
			c.visible = false
			c.modulate.a = 1.0
			_tweens.erase(c))
		_tweens[c] = t


func _vbox(parent: Control, separation: int = 8) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", separation)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if parent:
		parent.add_child(box)
	return box


func _hbox(parent: Control, separation: int = 8) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", separation)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if parent:
		parent.add_child(box)
	return box


func _stack(parent: Control) -> VBoxContainer:
	# A big number with a small line under it, centred vertically.
	var box := _vbox(parent, 0)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	return box


func _label(text: String, size: int, colour: Color, bold: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	if bold:
		l.add_theme_font_override("font", _bold)
	return l


func _caption(text: String) -> Label:
	# A small heading in capitals inside a panel.
	return _label(text.to_upper(), 11, TEXT_FAINT, true)


func _button(text: String, toggle: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = toggle
	b.focus_mode = Control.FOCUS_NONE
	return b


func _icon_button(icon_id: String, tip: String, toggle: bool) -> Button:
	var b := Button.new()
	b.theme_type_variation = "IconButton"
	b.icon = _line_icon(icon_id, 40)
	b.expand_icon = true
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.tooltip_text = tip
	b.toggle_mode = toggle
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(34, 34)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return b


func _icon_rect(icon_id: String, px: int, colour: Color) -> TextureRect:
	var r := TextureRect.new()
	r.texture = _line_icon(icon_id, px * 2)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.custom_minimum_size = Vector2(px, px)
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.modulate = colour
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


func _divider() -> HSeparator:
	var sep := HSeparator.new()
	var line := StyleBoxLine.new()
	line.color = Color(1, 1, 1, 0.1)
	line.thickness = 1
	sep.add_theme_stylebox_override("separator", line)
	sep.add_theme_constant_override("separation", 6)
	return sep


func _vline() -> VSeparator:
	var sep := VSeparator.new()
	var line := StyleBoxLine.new()
	line.color = Color(1, 1, 1, 0.12)
	line.thickness = 1
	line.vertical = true
	line.grow_begin = -8
	line.grow_end = -8
	sep.add_theme_stylebox_override("separator", line)
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return sep


static func thousands(n: int) -> String:
	# 1234567 -> "1,234,567"
	var digits := str(absi(n))
	var out := ""
	while digits.length() > 3:
		out = "," + digits.substr(digits.length() - 3) + out
		digits = digits.substr(0, digits.length() - 3)
	return ("-" if n < 0 else "") + digits + out


static func money_text(amount: int) -> String:
	# -1234 -> "-£1,234"
	return ("-£" if amount < 0 else "£") + thousands(absi(amount))


# ----------------------------------------------------------------- theme

func _make_theme() -> Theme:
	# Type scale: 11 captions (capitals), 12-13 details, 14 body, 16-19 numbers,
	# 20 titles. Spacing on a 4-pixel grid.
	var theme := Theme.new()
	var names := PackedStringArray(["SF Pro Text", "SF Pro Display", "Helvetica Neue", "Inter", "Segoe UI", "Arial"])
	var font := SystemFont.new()
	font.font_names = names
	font.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	theme.default_font = font
	theme.default_font_size = 14
	var bold := SystemFont.new()
	bold.font_names = names
	bold.font_weight = 600
	bold.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	_bold = bold

	# Panels: the frosted glass is drawn separately (see _panel), so the panel
	# style itself is just spacing.
	_panel_style(theme, "PanelContainer", 16, 14)
	_panel_style(theme, "Island", 12, 8)
	_panel_style(theme, "Card", 12, 10)
	_panel_style(theme, "Dock", 8, 8)
	_panel_style(theme, "Toast", 14, 8)

	# Buttons: soft translucent white, brighter when hovered or chosen.
	var normal := _soft_box(Color(1, 1, 1, 0.08), 9)
	normal.content_margin_left = 12
	normal.content_margin_right = 12
	normal.content_margin_top = 6
	normal.content_margin_bottom = 7
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(1, 1, 1, 0.16)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(1, 1, 1, 0.26)
	pressed.border_color = Color(1, 1, 1, 0.28)
	pressed.set_border_width_all(1)
	_button_styles(theme, "Button", normal, hover, pressed, pressed)
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Color(1, 1, 1, 0.035)
	theme.set_stylebox("disabled", "Button", disabled)
	theme.set_color("font_disabled_color", "Button", Color(1, 1, 1, 0.32))
	theme.set_color("font_color", "Button", TEXT)
	theme.set_color("font_hover_color", "Button", Color.WHITE)
	theme.set_color("font_pressed_color", "Button", Color.WHITE)
	theme.set_color("font_hover_pressed_color", "Button", Color.WHITE)
	theme.set_color("icon_normal_color", "Button", Color(1, 1, 1, 0.85))
	theme.set_color("icon_hover_color", "Button", Color.WHITE)
	theme.set_color("icon_pressed_color", "Button", Color.WHITE)
	theme.set_color("icon_hover_pressed_color", "Button", Color.WHITE)
	theme.set_color("font_color", "Label", TEXT)

	# The main action of a dialog (Start): filled in the accent colour.
	theme.set_type_variation("Primary", "Button")
	var primary := normal.duplicate() as StyleBoxFlat
	primary.bg_color = ACCENT
	var primary_hover := normal.duplicate() as StyleBoxFlat
	primary_hover.bg_color = ACCENT.lightened(0.12)
	var primary_down := normal.duplicate() as StyleBoxFlat
	primary_down.bg_color = ACCENT.darkened(0.12)
	_button_styles(theme, "Primary", primary, primary_hover, primary_down, primary_down)
	theme.set_font("font", "Primary", bold)
	theme.set_color("font_color", "Primary", Color.WHITE)

	# Square icon buttons (the menu), and the same without a background until hovered.
	var icon_normal := _pad(_soft_box(Color(1, 1, 1, 0.07), 9), 8)
	var icon_hover := _pad(_soft_box(Color(1, 1, 1, 0.16), 9), 8)
	var icon_on := _pad(_soft_box(Color(1, 1, 1, 0.26), 9), 8)
	theme.set_type_variation("IconButton", "Button")
	_button_styles(theme, "IconButton", icon_normal, icon_hover, icon_on, icon_on)
	theme.set_type_variation("Flat", "Button")
	_button_styles(theme, "Flat", _pad(StyleBoxEmpty.new(), 6), _pad(_soft_box(Color(1, 1, 1, 0.14), 9), 6),
		_pad(_soft_box(Color(1, 1, 1, 0.22), 9), 6), _pad(_soft_box(Color(1, 1, 1, 0.22), 9), 6))
	theme.set_color("icon_normal_color", "Flat", Color(1, 1, 1, 0.6))

	# Segments: a speed or a map view; the chosen one is lit in the accent colour
	# (pause in amber, so a stopped clock is obvious).
	var seg := _pad(StyleBoxEmpty.new(), 8)
	theme.set_type_variation("Segment", "Button")
	_button_styles(theme, "Segment", seg, icon_hover, _pad(_soft_box(ACCENT, 9), 8),
		_pad(_soft_box(ACCENT.lightened(0.12), 9), 8))
	theme.set_color("icon_normal_color", "Segment", Color(1, 1, 1, 0.62))
	# Chips: the Services view's All / Police / Fire / Schools / Hospitals, lit like a segment.
	theme.set_type_variation("Chip", "Button")
	var chip := _soft_box(Color(1, 1, 1, 0.06), 8)
	chip.content_margin_left = 7
	chip.content_margin_right = 8
	chip.content_margin_top = 4
	chip.content_margin_bottom = 4
	var chip_hover := chip.duplicate() as StyleBoxFlat
	chip_hover.bg_color = Color(1, 1, 1, 0.16)
	var chip_on := chip.duplicate() as StyleBoxFlat
	chip_on.bg_color = ACCENT
	var chip_on_hover := chip.duplicate() as StyleBoxFlat
	chip_on_hover.bg_color = ACCENT.lightened(0.12)
	_button_styles(theme, "Chip", chip, chip_hover, chip_on, chip_on_hover)
	theme.set_font_size("font_size", "Chip", 12)
	theme.set_constant("h_separation", "Chip", 4)
	theme.set_constant("icon_max_width", "Chip", 14)
	theme.set_color("font_color", "Chip", TEXT_DIM)
	theme.set_color("font_pressed_color", "Chip", Color.WHITE)
	theme.set_color("font_hover_pressed_color", "Chip", Color.WHITE)
	theme.set_color("icon_normal_color", "Chip", Color(1, 1, 1, 0.62))
	theme.set_type_variation("Pause", "Button")
	var amber := Color(0.93, 0.62, 0.18)
	_button_styles(theme, "Pause", seg, icon_hover, _pad(_soft_box(amber, 9), 8),
		_pad(_soft_box(amber.lightened(0.12), 9), 8))
	theme.set_color("icon_normal_color", "Pause", Color(1, 1, 1, 0.62))

	# Menu rows: flat, left-aligned, with an icon.
	theme.set_type_variation("MenuRow", "Button")
	var row_flat := _pad(StyleBoxEmpty.new(), 7)
	var row_lit := _pad(_soft_box(Color(1, 1, 1, 0.12), 8), 7)
	_button_styles(theme, "MenuRow", row_flat, row_lit, row_flat, row_lit)
	theme.set_constant("h_separation", "MenuRow", 10)
	theme.set_color("icon_pressed_color", "MenuRow", WARN)
	theme.set_color("icon_hover_pressed_color", "MenuRow", WARN)

	# Advisors: flat rows, and the count badge.
	theme.set_type_variation("AdviceRow", "Button")
	_button_styles(theme, "AdviceRow", _pad(StyleBoxEmpty.new(), 6), _pad(_soft_box(Color(1, 1, 1, 0.09), 8), 6),
		_pad(_soft_box(Color(1, 1, 1, 0.09), 8), 6), _pad(_soft_box(Color(1, 1, 1, 0.09), 8), 6))
	theme.set_font_size("font_size", "AdviceRow", 13)
	theme.set_constant("h_separation", "AdviceRow", 8)
	theme.set_type_variation("Count", "Button")
	var count := _soft_box(Color(1, 1, 1, 0.10), 9)
	count.content_margin_left = 10
	count.content_margin_right = 6
	count.content_margin_top = 6
	count.content_margin_bottom = 6
	var count_hover := count.duplicate() as StyleBoxFlat
	count_hover.bg_color = Color(1, 1, 1, 0.18)
	var count_on := count.duplicate() as StyleBoxFlat
	count_on.bg_color = Color(1, 1, 1, 0.26)
	_button_styles(theme, "Count", count, count_hover, count_on, count_on)
	theme.set_font("font", "Count", bold)
	theme.set_font_size("font_size", "Count", 13)
	theme.set_constant("h_separation", "Count", 2)

	# Build dock: the category rail and its buttons.
	theme.set_type_variation("RailButton", "Button")
	var rail_normal := _pad(StyleBoxEmpty.new(), 5)
	var rail_hover := _pad(_soft_box(Color(1, 1, 1, 0.08), 10), 5)
	var rail_on := _pad(_soft_box(Color(1, 1, 1, 0.18), 10), 5)
	_button_styles(theme, "RailButton", rail_normal, rail_hover, rail_on, rail_on)
	theme.set_font_size("font_size", "RailButton", 11)
	theme.set_color("font_color", "RailButton", TEXT_DIM)
	theme.set_color("font_pressed_color", "RailButton", Color.WHITE)
	theme.set_color("font_hover_pressed_color", "RailButton", Color.WHITE)
	theme.set_color("icon_normal_color", "RailButton", Color(1, 1, 1, 0.72))
	theme.set_constant("h_separation", "RailButton", 2)
	theme.set_type_variation("Bulldoze", "RailButton")
	var doze_on := _pad(_soft_box(Color(0.86, 0.30, 0.28, 0.85), 10), 5)
	_button_styles(theme, "Bulldoze", rail_normal, rail_hover, doze_on, doze_on)

	# Build menu rows: invisible until hovered; the chosen one is lit in the accent colour.
	theme.set_type_variation("ItemRow", "Button")
	var item_hover := _soft_box(Color(1, 1, 1, 0.08), 12)
	var item_on := _soft_box(Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.28), 12)
	item_on.border_color = Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.85)
	item_on.set_border_width_all(1)
	_button_styles(theme, "ItemRow", StyleBoxEmpty.new(), item_hover, item_on, item_on)
	theme.set_type_variation("IconTile", "PanelContainer")
	var tile := _pad(_soft_box(Color(0, 0, 0, 0.30), 10), 1)
	theme.set_stylebox("panel", "IconTile", tile)

	# Scroll bar: thin and quiet.
	var grabber := _soft_box(Color(1, 1, 1, 0.22), 3)
	grabber.content_margin_left = 3
	grabber.content_margin_right = 3
	var grabber_hi := _soft_box(Color(1, 1, 1, 0.38), 3)
	var track := StyleBoxEmpty.new()
	track.content_margin_left = 4
	theme.set_stylebox("grabber", "VScrollBar", grabber)
	theme.set_stylebox("grabber_highlight", "VScrollBar", grabber_hi)
	theme.set_stylebox("grabber_pressed", "VScrollBar", grabber_hi)
	theme.set_stylebox("scroll", "VScrollBar", track)

	var tip := StyleBoxFlat.new()
	tip.bg_color = Color(0.06, 0.07, 0.09, 0.96)
	tip.border_color = Color(1, 1, 1, 0.12)
	tip.set_border_width_all(1)
	tip.set_corner_radius_all(8)
	tip.set_content_margin_all(8)
	theme.set_stylebox("panel", "TooltipPanel", tip)
	theme.set_color("font_color", "TooltipLabel", TEXT)
	theme.set_font_size("font_size", "TooltipLabel", 13)
	return theme


func _panel_style(theme: Theme, type: String, h: int, v: int) -> void:
	var s := StyleBoxEmpty.new()
	s.content_margin_left = h
	s.content_margin_right = h
	s.content_margin_top = v
	s.content_margin_bottom = v
	if type != "PanelContainer":
		theme.set_type_variation(type, "PanelContainer")
	theme.set_stylebox("panel", type, s)


func _pad(box: StyleBox, margin: int) -> StyleBox:
	box.set_content_margin_all(margin)
	return box


func _soft_box(colour: Color, radius: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = colour
	box.set_corner_radius_all(radius)
	box.anti_aliasing = true
	return box


func _button_styles(theme: Theme, type: String, normal: StyleBox, hover: StyleBox, pressed: StyleBox,
		hover_pressed: StyleBox) -> void:
	theme.set_stylebox("normal", type, normal)
	theme.set_stylebox("hover", type, hover)
	theme.set_stylebox("pressed", type, pressed)
	theme.set_stylebox("hover_pressed", type, hover_pressed)
	theme.set_stylebox("focus", type, StyleBoxEmpty.new())
