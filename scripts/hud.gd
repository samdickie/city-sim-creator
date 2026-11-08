extends CanvasLayer
## The on-screen interface: a clean, modern look with rounded translucent panels.
##   Top left:      city name, date, game speed
##   Top right:     money, budget, people, power, tax, demand
##   Bottom left:   the Build menu (categories down the side, items with
##                  pictures, descriptions and prices) and the Build / Bulldoze buttons
##   Bottom centre: what's under the mouse, and messages
##   Bottom right:  map overlays (land value, power, roads, growth, pollution...) and their key
## It only displays things and reports button presses; the game decides what they do.

signal tool_chosen(tool_id: int)            # (the Bulldoze button)
signal build_item_chosen(id: String)       # an item picked in the Build menu
signal speed_chosen(speed: int)
signal tax_changed(step: float)
signal new_city_pressed
signal save_pressed
signal load_pressed
signal day_cycle_toggled(on: bool)
signal overlay_chosen(kind: int)
signal funding_changed(step: float)

const Settings = preload("res://scripts/settings.gd")
const Icons = preload("res://scripts/icons.gd")
const GLASS_SHADER = preload("res://shaders/glass.gdshader")
const BULLDOZE_TOOL := 4                   # (game3d.gd's Tool.BULLDOZE)

const ACCENT := Color(0.24, 0.56, 0.98)
const TEXT := Color(0.93, 0.95, 0.98)
const TEXT_DIM := Color(0.66, 0.70, 0.76)
const GOOD := Color(0.45, 0.88, 0.58)
const BAD := Color(1.0, 0.45, 0.42)
const OVERLAY_NAMES := ["Normal", "Land value", "Power", "Roads", "Growth", "Services", "Water", "Districts", "Pollution"]
const OVERLAY_TIPS := ["The normal view",
	"What land is worth: the sea, parks and shops raise it; industry and power plants lower it",
	"Which plots have electricity, and what carries it",
	"How far each plot is from a road (zones need one within 2 tiles)",
	"Why each zone is or isn't growing",
	"How many of police, fire, schools and hospitals cover each area",
	"Which plots have water (anything bigger than a first-level plot needs it)",
	"CBD (skyscrapers allowed) and conservation areas (low-rise only)",
	"Where the air is dirty: industry, coal and gas power, landfill and the harbour pollute; parks help"]

var speed_buttons := {}
var build_panel: PanelContainer
var build_toggle: Button
var bulldoze_button: Button
var _rail_buttons := {}                    # category id -> Button
var _rows := {}                            # item id -> {button, name, desc, price, price_icon, cat}
var _category := "all"
var _category_names := {}
var _selected_id := ""
var _list_title: Label
var _list_box: VBoxContainer
var _scroll: ScrollContainer
var _icon_cache := {}
var date_label: Label
var clock_label: Label
var money_label: Label
var budget_label: Label
var people_label: Label
var housing_label: Label
var power_label: Label
var growth_label: Label
var services_label: Label
var tax_label: Label
var info_label: Label
var message_label: Label
var help_panel: PanelContainer
var demand_box: Control
var overlay_buttons := {}
var funding_row: HBoxContainer
var utility_label: Label      # water
var rubbish_label: Label
var funding_label: Label
var legend_box: VBoxContainer
var confirm_new: ConfirmationDialog
var _message_time := 0.0
var _sim                         # read for the demand bars
var _demand_colours := {}


func build(categories: Array, demand_colours: Dictionary, sim) -> void:
	# categories: [[id, name], ...] for the Build menu's side rail.
	_sim = sim
	_demand_colours = demand_colours
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = _make_theme()
	add_child(root)
	_build_top_left(root)
	_build_top_right(root)
	_build_build_menu(root, categories)
	_build_info(root)
	_build_overlays(root)
	_build_help(root)

	confirm_new = ConfirmationDialog.new()
	confirm_new.title = "New city"
	confirm_new.dialog_text = "Clear everything you've built and start again?"
	confirm_new.confirmed.connect(func(): new_city_pressed.emit())
	root.add_child(confirm_new)


func _process(delta: float) -> void:
	if _message_time > 0.0:
		_message_time -= delta
		if _message_time <= 0.0:
			message_label.text = ""


# ------------------------------------------------------------------ layout

func _build_top_left(root: Control) -> void:
	var panel := _panel(root)
	panel.position = Vector2(20, 20)
	var box := _vbox(panel)

	var title := _label("Troon", 26, TEXT)
	box.add_child(title)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	box.add_child(row)
	date_label = _label("", 17, TEXT_DIM)
	date_label.custom_minimum_size = Vector2(96, 0)
	row.add_child(date_label)
	clock_label = _label("", 17, TEXT_DIM)
	clock_label.custom_minimum_size = Vector2(56, 0)
	row.add_child(clock_label)
	for s in [0, 1, Settings.FAST_SPEED]:
		var b := _button({0: "Pause", 1: "Play", Settings.FAST_SPEED: "Fast"}[s], true)
		b.pressed.connect(func(): speed_chosen.emit(s))
		row.add_child(b)
		speed_buttons[s] = b

	var files := HBoxContainer.new()
	files.add_theme_constant_override("separation", 6)
	box.add_child(files)
	for item in [["New", func(): confirm_new.popup_centered()],
			["Save", func(): save_pressed.emit()],
			["Load", func(): load_pressed.emit()],
			["Help", func(): help_panel.visible = not help_panel.visible]]:
		var b := _button(item[0], false)
		b.pressed.connect(item[1])
		files.add_child(b)
	var cycle := _button("Day & night", true)
	cycle.button_pressed = true
	cycle.tooltip_text = "Turn off to keep it daytime"
	cycle.toggled.connect(func(on: bool): day_cycle_toggled.emit(on))
	files.add_child(cycle)


func _build_top_right(root: Control) -> void:
	var panel := _panel(root)
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.offset_left = -20.0
	panel.offset_right = -20.0
	panel.offset_top = 20.0
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.custom_minimum_size = Vector2(290, 0)
	var box := _vbox(panel)

	money_label = _label("", 30, GOOD)
	box.add_child(money_label)
	budget_label = _label("", 13, TEXT_DIM)
	box.add_child(budget_label)
	box.add_child(_divider())
	people_label = _label("", 16, TEXT)
	box.add_child(people_label)
	housing_label = _label("", 14, TEXT_DIM)
	box.add_child(housing_label)
	power_label = _label("", 14, TEXT_DIM)
	box.add_child(power_label)
	services_label = _label("", 14, TEXT_DIM)
	box.add_child(services_label)
	utility_label = _label("", 14, TEXT_DIM)
	box.add_child(utility_label)
	rubbish_label = _label("", 14, TEXT_DIM)
	box.add_child(rubbish_label)
	growth_label = _label("", 14, TEXT_DIM)
	box.add_child(growth_label)
	box.add_child(_divider())

	var tax_row := HBoxContainer.new()
	box.add_child(tax_row)
	tax_label = _label("", 15, TEXT)
	tax_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tax_row.add_child(tax_label)
	var minus := _button("–", false)
	minus.pressed.connect(func(): tax_changed.emit(-0.01))
	tax_row.add_child(minus)
	var plus := _button("+", false)
	plus.pressed.connect(func(): tax_changed.emit(0.01))
	tax_row.add_child(plus)

	box.add_child(_label("Demand", 13, TEXT_DIM))
	demand_box = Control.new()
	demand_box.custom_minimum_size = Vector2(260, 84)
	demand_box.draw.connect(_draw_demand)
	box.add_child(demand_box)


func _build_build_menu(root: Control, categories: Array) -> void:
	# A frosted panel: categories down the left, the items in the chosen category
	# on the right (picture, name, one-line description, price).
	build_panel = _panel(root)
	build_panel.anchor_top = 1.0
	build_panel.anchor_bottom = 1.0
	build_panel.offset_left = 20.0
	build_panel.offset_top = -86.0
	build_panel.offset_bottom = -86.0
	build_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	build_panel.add_child(row)

	var rail := PanelContainer.new()
	rail.theme_type_variation = "Rail"
	row.add_child(rail)
	var rail_box := VBoxContainer.new()
	rail_box.add_theme_constant_override("separation", 4)
	rail.add_child(rail_box)
	for c in categories:
		var id: String = c[0]
		_category_names[id] = c[1]
		var b := Button.new()
		b.theme_type_variation = "RailButton"
		b.text = c[1]
		b.icon = _line_icon(id, 26)
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(80, 58)
		b.pressed.connect(func(): _show_category(id))
		rail_box.add_child(b)
		_rail_buttons[id] = b

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	column.custom_minimum_size = Vector2(390, 0)
	row.add_child(column)
	_list_title = _label("", 13, TEXT_DIM)
	column.add_child(_list_title)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.custom_minimum_size = Vector2(390, 470)
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_scroll)
	_list_box = VBoxContainer.new()
	_list_box.add_theme_constant_override("separation", 4)
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_list_box)

	# Funding for the chosen service, under the list.
	funding_row = HBoxContainer.new()
	funding_row.add_theme_constant_override("separation", 6)
	column.add_child(funding_row)
	funding_label = _label("", 13, TEXT)
	funding_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	funding_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	funding_row.add_child(funding_label)
	var less := _button("–", false)
	less.tooltip_text = "Less funding: cheaper, but reaches less far (0% closes it)"
	less.pressed.connect(func(): funding_changed.emit(-0.1))
	funding_row.add_child(less)
	var more := _button("+", false)
	more.tooltip_text = "More funding: costs more, reaches further (up to 150%)"
	more.pressed.connect(func(): funding_changed.emit(0.1))
	funding_row.add_child(more)
	funding_row.visible = false

	# Build and Bulldoze, bottom left.
	var pills := HBoxContainer.new()
	pills.add_theme_constant_override("separation", 10)
	pills.anchor_top = 1.0
	pills.anchor_bottom = 1.0
	pills.offset_left = 20.0
	pills.offset_top = -20.0
	pills.offset_bottom = -20.0
	pills.grow_vertical = Control.GROW_DIRECTION_BEGIN
	root.add_child(pills)
	build_toggle = _pill("Build", "build")
	build_toggle.button_pressed = true
	build_toggle.tooltip_text = "Show or hide the Build menu"
	build_toggle.toggled.connect(func(on: bool): build_panel.visible = on)
	pills.add_child(build_toggle)
	bulldoze_button = _pill("Bulldoze", "bulldoze")
	bulldoze_button.tooltip_text = "Clear anything you drag over (key 5)"
	bulldoze_button.pressed.connect(func(): tool_chosen.emit(BULLDOZE_TOOL))
	pills.add_child(bulldoze_button)
	_show_category("all")


func _pill(text: String, icon_id: String) -> Button:
	var b := Button.new()
	b.theme_type_variation = "PillButton"
	b.text = text
	b.icon = _line_icon(icon_id, 20)
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_constant_override("h_separation", 8)
	return b


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
		(r["desc"] as Label).text = item["desc"]
		(r["price"] as Label).text = item["price"]
		(r["price_icon"] as TextureRect).texture = _line_icon("lock" if locked else "price", 16)
		var b: Button = r["button"]
		b.tooltip_text = item["about"]
		b.modulate = Color(1, 1, 1, 0.5 if locked else 1.0)
	if first_time:
		_show_category(_category)


func _make_row(item: Dictionary) -> Dictionary:
	var id: String = item["id"]
	var b := Button.new()
	b.theme_type_variation = "ItemRow"
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(380, 70)
	b.pressed.connect(func(): build_item_chosen.emit(id))
	_list_box.add_child(b)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8 if side != "right" else 14)
	b.add_child(margin)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 14)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(line)
	# The picture, on a dark rounded tile.
	var tile := PanelContainer.new()
	tile.theme_type_variation = "IconTile"
	tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.custom_minimum_size = Vector2(54, 54)
	tile.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(tile)
	var pic := TextureRect.new()
	pic.texture = _item_icon(id)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.custom_minimum_size = Vector2(52, 52)
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(pic)
	# Name and one-line description.
	var words := VBoxContainer.new()
	words.add_theme_constant_override("separation", 1)
	words.alignment = BoxContainer.ALIGNMENT_CENTER
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(words)
	var name_label := _label("", 16, TEXT)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	words.add_child(name_label)
	var desc := _label("", 13, TEXT_DIM)
	desc.clip_text = true
	desc.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	desc.custom_minimum_size = Vector2(150, 0)
	desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	words.add_child(desc)
	# Price, with a little tag (or a padlock while it's locked).
	var price_icon := TextureRect.new()
	price_icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	price_icon.modulate = Color(1, 1, 1, 0.65)
	price_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	price_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(price_icon)
	var price := _label("", 15, TEXT)
	price.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	price.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(price)
	return {"button": b, "name": name_label, "desc": desc, "price": price, "price_icon": price_icon,
		"cat": String(item["cat"])}


func _show_category(cat: String) -> void:
	_category = cat
	for k in _rail_buttons:
		(_rail_buttons[k] as Button).set_pressed_no_signal(k == cat)
	var shown := 0
	for id in _rows:
		var r: Dictionary = _rows[id]
		var on: bool = cat == "all" or r["cat"] == cat
		(r["button"] as Button).visible = on
		if on:
			shown += 1
	var title: String = _category_names.get(cat, "")
	_list_title.text = ("Everything" if cat == "all" else title).to_upper() + "   ·   %d" % shown
	_scroll.scroll_vertical = 0


func set_selected(id: String) -> void:
	# Highlight the item being built. Only when the choice changes (a key, or the
	# Bulldoze button) does the menu jump to its category: the game refreshes this
	# every month, and that mustn't pull you away from a category you're browsing.
	var changed := id != _selected_id
	_selected_id = id
	for k in _rows:
		(_rows[k]["button"] as Button).set_pressed_no_signal(k == id)
	bulldoze_button.set_pressed_no_signal(id == "bulldoze")
	if changed and _rows.has(id):
		var r: Dictionary = _rows[id]
		if _category != "all" and r["cat"] != _category:
			_show_category(r["cat"])
		_scroll.ensure_control_visible.call_deferred(r["button"])


func set_funding(text: String) -> void:
	funding_row.visible = text != ""
	funding_label.text = text


func toggle_build_menu() -> void:
	build_toggle.button_pressed = not build_toggle.button_pressed


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


func _build_info(root: Control) -> void:
	var panel := _panel(root)
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_bottom = -20.0
	panel.offset_top = -20.0
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.custom_minimum_size = Vector2(380, 0)
	var box := _vbox(panel)
	info_label = _label("", 14, TEXT)
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_label.custom_minimum_size = Vector2(330, 0)
	box.add_child(info_label)
	message_label = _label("", 14, Color(1.0, 0.82, 0.4))
	box.add_child(message_label)


func _build_overlays(root: Control) -> void:
	var panel := _panel(root)
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -20.0
	panel.offset_right = -20.0
	panel.offset_top = -20.0
	panel.offset_bottom = -20.0
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var box := _vbox(panel)
	box.add_child(_label("Map view (O)", 13, TEXT_DIM))
	for kind in OVERLAY_NAMES.size():
		var b := _button(OVERLAY_NAMES[kind], true)
		b.custom_minimum_size = Vector2(150, 0)
		b.tooltip_text = OVERLAY_TIPS[kind]
		b.pressed.connect(func(): overlay_chosen.emit(kind))
		box.add_child(b)
		overlay_buttons[kind] = b
	legend_box = VBoxContainer.new()
	legend_box.add_theme_constant_override("separation", 4)
	box.add_child(legend_box)


func set_overlay(kind: int, legend: Array) -> void:
	# Highlight the chosen view and show its colour key.
	for k in overlay_buttons:
		(overlay_buttons[k] as Button).set_pressed_no_signal(k == kind)
	for child in legend_box.get_children():
		child.queue_free()
	for entry in legend:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var swatch := ColorRect.new()
		swatch.color = entry[0]
		swatch.custom_minimum_size = Vector2(14, 14)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(swatch)
		var text := _label(entry[1], 13, TEXT)
		text.custom_minimum_size = Vector2(130, 0)
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(text)
		legend_box.add_child(row)


func _build_help(root: Control) -> void:
	help_panel = _panel(root)
	help_panel.anchor_left = 0.5
	help_panel.anchor_right = 0.5
	help_panel.anchor_top = 0.5
	help_panel.anchor_bottom = 0.5
	help_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	help_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	var box := _vbox(help_panel)
	box.add_child(_label("How to play", 20, TEXT))
	var text := _label(
		"Build: press, drag to see a preview and the cost, release to build (Esc cancels)\n" +
		"  Roads and power lines run straight and can turn one corner\n" +
		"  Zones and parks: drag a box. Start the drag ON a road to zone both sides\n" +
		"  of every road in the box, two plots deep\n" +
		"  Street grid (9): drag a box to lay streets with 100 m blocks\n" +
		"Pick what to build in the Build menu (bottom left; categories down its side).\n" +
		"Homes and shops come in low, medium and high density (Tab switches)\n" +
		"Move: two-finger scroll, middle-drag, or WASD\n" +
		"Rotate and tilt: right-drag, or Q / E\n" +
		"Zoom: pinch or scroll wheel\n" +
		"Tools: keys 1-0, - and =     Pause: Space     Fast: F     Help: H\n" +
		"Map views: O, or the buttons bottom right (land value, power, roads, growth, services, water, pollution)\n" +
		"Services (0): police, fire stations, schools and hospitals cover the area around them.\n" +
		"They need a road and power. Bigger towns grow slowly without them; fires break out\n" +
		"where there's no fire station. Funding (- / +) changes how far they reach.\n" +
		"Taxes: people accept higher taxes when they get good services for them. High taxes\n" +
		"with poor services stop growth, and eventually people leave (worst-served areas first).\n" +
		"Power (6), Utilities (7), Leisure (-) and Transport (=) each have several buildings:\n" +
		"pick one with Tab. Anything bigger than a first-level plot needs water (pumps and\n" +
		"towers; it travels like power). Towns over 400 people need rubbish collected.\n" +
		"Some buildings unlock as the town grows.\n" +
		"Districts (Z): paint a CBD where high-density plots can become skyscrapers (8,000\n" +
		"people and a station or bus depot nearby), or a conservation area kept low-rise.\n\n" +
		"Zones grow when a road is within %d tiles and they have power.\n" % Settings.ROAD_REACH +
		"Red icon = no road nearby.   Yellow lightning icon = no power.\n" +
		"Power travels through roads, buildings and power lines that share an edge.\n\n" +
		"Low density grows villas and terraces; medium up to tenements, and mansion flats\n" +
		"when space runs short; high density builds upwards to towers on valuable land.\n" +
		"Land is worth more by the sea, near parks and shops, and less near industry\n" +
		"and power plants. Scarce homes push prices up.", 15, TEXT_DIM)
	box.add_child(text)
	var close := _button("Got it", false)
	close.pressed.connect(func(): help_panel.visible = false)
	box.add_child(close)


# ----------------------------------------------------------------- updates

func set_speed(speed: int) -> void:
	for k in speed_buttons:
		(speed_buttons[k] as Button).set_pressed_no_signal(k == speed)


func show_city(sim, money_str: String, net_text: String, income_text: String, upkeep_text: String) -> void:
	date_label.text = sim.date_text()
	money_label.text = money_str
	money_label.add_theme_color_override("font_color", BAD if sim.money * 10 < Settings.START_MONEY else GOOD)
	budget_label.text = "%s last month   ·   taxes %s, upkeep %s" % [net_text, income_text, upkeep_text]
	people_label.text = "%s people   ·   %s jobs" % [thousands(sim.population), thousands(sim.jobs())]
	var short: float = sim.housing_shortage()
	var word := "none" if short <= 0.0 else ("some" if short < 0.4 else ("serious" if short < 0.8 else "severe"))
	if sim.average_home_price > 0:
		housing_label.text = "Average home £%s   ·   housing shortage: %s" % [thousands(sim.average_home_price), word]
	else:
		housing_label.text = "Housing shortage: %s" % word
	housing_label.add_theme_color_override("font_color", BAD if short >= 0.4 else TEXT_DIM)
	if sim.plants == 0:
		power_label.text = "No power plant yet: build one to start growing"
		power_label.add_theme_color_override("font_color", BAD)
	else:
		power_label.text = "Power %d of %d used" % [sim.power_used, sim.power_supply]
		var tight: bool = sim.power_used > sim.power_supply * 0.9
		power_label.add_theme_color_override("font_color", BAD if tight else TEXT_DIM)
	growth_label.text = "Last month: %d plots grew, %d shrank" % [sim.grew.size(), sim.shrank.size()]
	var water_text := "no water supply yet" if sim.water_supply == 0 \
		else "%d of %d used" % [sim.water_used, sim.water_supply]
	# Water and rubbish on their own lines, so each is only red when it's the problem.
	utility_label.text = "Water %s" % water_text
	var dry: bool = (sim.water_supply == 0 and sim.population > 0) or sim.water_used > sim.water_supply * 0.9
	utility_label.add_theme_color_override("font_color", BAD if dry else TEXT_DIM)
	rubbish_label.text = "Rubbish: %s" % sim.rubbish_word()
	if sim.rubbish_shortfall() > 0.3:
		rubbish_label.text += " (build a landfill or recycling)"
	rubbish_label.add_theme_color_override("font_color", BAD if sim.rubbish_shortfall() > 0.3 else TEXT_DIM)
	var service_word: String = sim.services_word()
	services_label.text = "Services: %s (%d%% cover)" % [service_word, roundi(sim.service_score * 100.0)]
	services_label.add_theme_color_override("font_color",
		BAD if service_word == "poor" else (GOOD if service_word == "excellent" else TEXT_DIM))
	tax_label.text = "Tax rate %d%%: %s" % [roundi(sim.tax_rate * 100.0), sim.tax_word()]
	tax_label.add_theme_color_override("font_color", BAD if sim.appeal() < 0.3 else TEXT)
	demand_box.queue_redraw()


func set_clock(text: String) -> void:
	clock_label.text = text


func show_info(text: String) -> void:
	info_label.text = text


func flash(text: String) -> void:
	message_label.text = text
	_message_time = 2.5


func _draw_demand() -> void:
	if _sim == null:
		return
	var size := demand_box.size
	var mid := size.y * 0.42
	var font := demand_box.get_theme_default_font()
	demand_box.draw_line(Vector2(0, mid), Vector2(size.x, mid), Color(1, 1, 1, 0.25), 1.0)
	var keys := _demand_colours.keys()
	var col_w := size.x / keys.size()
	for n in keys.size():
		var t: int = keys[n]
		var value: float = _sim.demand_bar(t)
		var bar_h := absf(value) * (mid - 4.0)
		var x := n * col_w + col_w * 0.3
		var top := mid - bar_h if value > 0 else mid
		var rect := Rect2(x, top, col_w * 0.4, maxf(bar_h, 2.0))
		demand_box.draw_rect(rect, _demand_colours[t][0])
		demand_box.draw_string(font, Vector2(n * col_w, size.y - 4), _demand_colours[t][1],
			HORIZONTAL_ALIGNMENT_CENTER, col_w, 13, TEXT_DIM)


# ----------------------------------------------------------------- pieces

func _panel(root: Control) -> PanelContainer:
	# A frosted glass panel. The glass is drawn by a ColorRect behind the
	# contents, stretched over the whole panel whenever it's laid out.
	var panel := PanelContainer.new()
	var glass := ColorRect.new()
	glass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = GLASS_SHADER
	glass.material = mat
	panel.add_child(glass)
	panel.sort_children.connect(func():
		glass.position = Vector2.ZERO
		glass.size = panel.size
		mat.set_shader_parameter("size", panel.size)
	)
	root.add_child(panel)
	return panel


func _vbox(panel: PanelContainer) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	return box


func _label(text: String, size: int, colour: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	return l


func _button(text: String, toggle: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = toggle
	b.focus_mode = Control.FOCUS_NONE
	return b


func _divider() -> HSeparator:
	var sep := HSeparator.new()
	var line := StyleBoxLine.new()
	line.color = Color(1, 1, 1, 0.1)
	line.thickness = 1
	sep.add_theme_stylebox_override("separator", line)
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


func _make_theme() -> Theme:
	var theme := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["SF Pro Display", "SF Pro Text", "Helvetica Neue", "Inter", "Segoe UI", "Arial"])
	font.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	theme.default_font = font
	theme.default_font_size = 15

	# Panels: the frosted glass is drawn separately (see _panel), so the panel
	# style itself is just spacing.
	var panel := StyleBoxEmpty.new()
	panel.set_content_margin_all(16)
	theme.set_stylebox("panel", "PanelContainer", panel)

	# Buttons: soft translucent white, brighter when chosen.
	var normal := _soft_box(Color(1, 1, 1, 0.08), 12)
	normal.content_margin_left = 12
	normal.content_margin_right = 12
	normal.content_margin_top = 7
	normal.content_margin_bottom = 8
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(1, 1, 1, 0.15)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(1, 1, 1, 0.24)
	pressed.border_color = Color(1, 1, 1, 0.28)
	pressed.set_border_width_all(1)
	var hover_pressed := pressed.duplicate() as StyleBoxFlat
	hover_pressed.bg_color = Color(1, 1, 1, 0.3)
	_button_styles(theme, "Button", normal, hover, pressed, hover_pressed)

	# Build menu: the dark rail of categories and its buttons.
	var rail := _soft_box(Color(0, 0, 0, 0.22), 20)
	rail.set_content_margin_all(6)
	theme.set_type_variation("Rail", "PanelContainer")
	theme.set_stylebox("panel", "Rail", rail)
	theme.set_type_variation("RailButton", "Button")
	var rail_normal := StyleBoxEmpty.new()
	rail_normal.set_content_margin_all(6)
	var rail_hover := _soft_box(Color(1, 1, 1, 0.07), 16)
	rail_hover.set_content_margin_all(6)
	var rail_on := _soft_box(Color(1, 1, 1, 0.17), 16)
	rail_on.set_content_margin_all(6)
	_button_styles(theme, "RailButton", rail_normal, rail_hover, rail_on, rail_on)
	theme.set_font_size("font_size", "RailButton", 13)
	theme.set_color("font_color", "RailButton", TEXT_DIM)
	theme.set_color("icon_normal_color", "RailButton", Color(1, 1, 1, 0.7))

	# Build menu rows: invisible until hovered; the chosen one is lit with a hairline.
	theme.set_type_variation("ItemRow", "Button")
	var row_hover := _soft_box(Color(1, 1, 1, 0.07), 18)
	var row_on := _soft_box(Color(1, 1, 1, 0.14), 18)
	row_on.border_color = Color(1, 1, 1, 0.22)
	row_on.set_border_width_all(1)
	_button_styles(theme, "ItemRow", StyleBoxEmpty.new(), row_hover, row_on, row_on)
	theme.set_type_variation("IconTile", "PanelContainer")
	var tile := _soft_box(Color(0, 0, 0, 0.28), 14)
	tile.set_content_margin_all(1)
	theme.set_stylebox("panel", "IconTile", tile)

	# Build and Bulldoze pills.
	theme.set_type_variation("PillButton", "Button")
	var pill := _soft_box(Color(0.10, 0.12, 0.11, 0.78), 24)
	pill.border_color = Color(1, 1, 1, 0.14)
	pill.set_border_width_all(1)
	pill.content_margin_left = 18
	pill.content_margin_right = 20
	pill.content_margin_top = 10
	pill.content_margin_bottom = 10
	var pill_hover := pill.duplicate() as StyleBoxFlat
	pill_hover.bg_color = Color(0.18, 0.21, 0.19, 0.85)
	var pill_on := pill.duplicate() as StyleBoxFlat
	pill_on.bg_color = Color(0.30, 0.34, 0.31, 0.9)
	pill_on.border_color = Color(1, 1, 1, 0.3)
	_button_styles(theme, "PillButton", pill, pill_hover, pill_on, pill_on)
	theme.set_font_size("font_size", "PillButton", 16)
	theme.set_color("font_color", "Button", TEXT)
	theme.set_color("font_hover_color", "Button", Color.WHITE)
	theme.set_color("font_pressed_color", "Button", Color.WHITE)
	theme.set_color("font_hover_pressed_color", "Button", Color.WHITE)
	theme.set_color("font_color", "Label", TEXT)

	theme.set_color("font_color", "RailButton", TEXT_DIM)
	theme.set_color("font_pressed_color", "RailButton", Color.WHITE)
	theme.set_color("font_hover_pressed_color", "RailButton", Color.WHITE)

	var tip := StyleBoxFlat.new()
	tip.bg_color = Color(0.07, 0.09, 0.12, 0.95)
	tip.set_corner_radius_all(8)
	tip.set_content_margin_all(8)
	theme.set_stylebox("panel", "TooltipPanel", tip)
	return theme


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
