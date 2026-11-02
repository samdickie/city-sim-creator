extends CanvasLayer
## The on-screen interface: a clean, modern look with rounded translucent panels.
##   Top left:      city name, date, game speed
##   Top right:     money, budget, people, power, tax, demand
##   Bottom centre: building tools with prices
##   Bottom left:   what's under the mouse, and messages
##   Bottom right:  map overlays (land value, power, roads, growth) and their key
## It only displays things and reports button presses; the game decides what they do.

signal tool_chosen(tool_id: int)
signal density_chosen(density: int)
signal speed_chosen(speed: int)
signal tax_changed(step: float)
signal new_city_pressed
signal save_pressed
signal load_pressed
signal day_cycle_toggled(on: bool)
signal overlay_chosen(kind: int)

const Settings = preload("res://scripts/settings.gd")

const ACCENT := Color(0.24, 0.56, 0.98)
const TEXT := Color(0.93, 0.95, 0.98)
const TEXT_DIM := Color(0.66, 0.70, 0.76)
const GOOD := Color(0.45, 0.88, 0.58)
const BAD := Color(1.0, 0.45, 0.42)
const OVERLAY_NAMES := ["Normal", "Land value", "Power", "Roads", "Growth"]
const OVERLAY_TIPS := ["The normal view",
	"What land is worth: the sea, parks and shops raise it; industry and power plants lower it",
	"Which plots have electricity, and what carries it",
	"How far each plot is from a road (zones need one within 2 tiles)",
	"Why each zone is or isn't growing"]

var tool_buttons := {}
var density_buttons := {}
var density_panel: PanelContainer
var speed_buttons := {}
var date_label: Label
var clock_label: Label
var money_label: Label
var budget_label: Label
var people_label: Label
var housing_label: Label
var power_label: Label
var growth_label: Label
var tax_label: Label
var info_label: Label
var message_label: Label
var help_panel: PanelContainer
var demand_box: Control
var overlay_buttons := {}
var legend_box: VBoxContainer
var confirm_new: ConfirmationDialog
var _message_time := 0.0
var _sim                         # read for the demand bars
var _demand_colours := {}


func build(tools: Array, demand_colours: Dictionary, sim) -> void:
	# tools: [[id, name, key, price_text, colour], ...]
	_sim = sim
	_demand_colours = demand_colours
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = _make_theme()
	add_child(root)
	_build_top_left(root)
	_build_top_right(root)
	_build_toolbar(root, tools)
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


func _build_toolbar(root: Control, tools: Array) -> void:
	var panel := _panel(root)
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_bottom = -20.0
	panel.offset_top = -20.0
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	panel.add_child(row)
	for t in tools:
		var id: int = t[0]
		var b := _button("%s\n%s" % [t[1], t[3]], true)
		b.custom_minimum_size = Vector2(108, 58)
		b.tooltip_text = "Key %s" % t[2]
		# A coloured strip along the bottom shows what the tool builds.
		var strip := ColorRect.new()
		strip.color = t[4]
		strip.custom_minimum_size = Vector2(0, 4)
		strip.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		strip.offset_top = -8.0
		strip.offset_bottom = -4.0
		strip.offset_left = 14.0
		strip.offset_right = -14.0
		strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(strip)
		b.pressed.connect(func(): tool_chosen.emit(id))
		row.add_child(b)
		tool_buttons[id] = b

	# Density picker, shown above the toolbar while Homes or Shops is selected.
	density_panel = _panel(root)
	density_panel.anchor_left = 0.5
	density_panel.anchor_right = 0.5
	density_panel.anchor_top = 1.0
	density_panel.anchor_bottom = 1.0
	density_panel.offset_bottom = -116.0
	density_panel.offset_top = -116.0
	density_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	density_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var drow := HBoxContainer.new()
	drow.add_theme_constant_override("separation", 6)
	density_panel.add_child(drow)
	drow.add_child(_label("Density (Tab)", 14, TEXT_DIM))
	for d: int in [0, 1, 2]:
		var db := _button(["Low", "Medium", "High"][d], true)
		db.custom_minimum_size = Vector2(84, 0)
		db.tooltip_text = ["Villas and corner shops; never more than 2 storeys",
			"Terraces and tenements; mansion flats when space runs short",
			"Flats, towers and offices, as high as land value allows"][d]
		db.pressed.connect(func(): density_chosen.emit(d))
		drow.add_child(db)
		density_buttons[d] = db
	density_panel.visible = false


func _build_info(root: Control) -> void:
	var panel := _panel(root)
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = 20.0
	panel.offset_bottom = -132.0
	panel.offset_top = -132.0
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.custom_minimum_size = Vector2(360, 0)
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
	panel.offset_top = -116.0      # above the toolbar
	panel.offset_bottom = -116.0
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
		"Homes and shops come in low, medium and high density (Tab or the buttons)\n" +
		"Move: two-finger scroll, middle-drag, or WASD\n" +
		"Rotate and tilt: right-drag, or Q / E\n" +
		"Zoom: pinch or scroll wheel\n" +
		"Tools: keys 1-9     Pause: Space     Fast: F     Help: H\n" +
		"Map views: O, or the buttons bottom right (land value, power, roads, growth)\n\n" +
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

func set_density(d: int) -> void:
	for k in density_buttons:
		(density_buttons[k] as Button).set_pressed_no_signal(k == d)


func show_density(on: bool) -> void:
	if density_panel:
		density_panel.visible = on


func set_tool(id: int) -> void:
	for k in tool_buttons:
		(tool_buttons[k] as Button).set_pressed_no_signal(k == id)


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
	tax_label.text = "Tax rate %d%%" % roundi(sim.tax_rate * 100.0)
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
	var panel := PanelContainer.new()
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

	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.07, 0.09, 0.12, 0.80)
	panel.set_corner_radius_all(18)
	panel.set_content_margin_all(18)
	panel.border_color = Color(1, 1, 1, 0.07)
	panel.set_border_width_all(1)
	panel.shadow_color = Color(0, 0, 0, 0.3)
	panel.shadow_size = 16
	panel.anti_aliasing = true
	theme.set_stylebox("panel", "PanelContainer", panel)

	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(1, 1, 1, 0.06)
	normal.set_corner_radius_all(12)
	normal.content_margin_left = 12
	normal.content_margin_right = 12
	normal.content_margin_top = 7
	normal.content_margin_bottom = 9
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(1, 1, 1, 0.13)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = ACCENT
	var hover_pressed := pressed.duplicate() as StyleBoxFlat
	hover_pressed.bg_color = ACCENT.lightened(0.1)
	theme.set_stylebox("normal", "Button", normal)
	theme.set_stylebox("hover", "Button", hover)
	theme.set_stylebox("pressed", "Button", pressed)
	theme.set_stylebox("hover_pressed", "Button", hover_pressed)
	theme.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	theme.set_color("font_color", "Button", TEXT)
	theme.set_color("font_hover_color", "Button", Color.WHITE)
	theme.set_color("font_pressed_color", "Button", Color.WHITE)
	theme.set_color("font_hover_pressed_color", "Button", Color.WHITE)
	theme.set_color("font_color", "Label", TEXT)

	var tip := StyleBoxFlat.new()
	tip.bg_color = Color(0.07, 0.09, 0.12, 0.95)
	tip.set_corner_radius_all(8)
	tip.set_content_margin_all(8)
	theme.set_stylebox("panel", "TooltipPanel", tip)
	return theme
