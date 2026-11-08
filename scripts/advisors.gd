extends RefCounted
## Advisors: short tips when something in the town needs attention.
## tips(sim) reads the simulation and returns what to tell the player, most
## urgent first. It never changes the town; the HUD decides how to show it.
##
## Each tip is a Dictionary:
##   id        a stable name, so the HUD can tell tips apart from month to month
##   text      one short line for the card (keep it under about 55 characters)
##   detail    a longer explanation, shown on hover
##   severity  URGENT, WARNING or ADVICE
##   overlay   the map view that shows the problem (WorldView.Overlay), or NO_OVERLAY
##
## To add a tip: work out the condition from the simulation in tips() and call
## _add(). If it depends on why zone plots aren't growing, add the phrase from
## simulation.gd's _zone_check() to REASONS and use _n(stuck, "your_key").

const Settings = preload("res://scripts/settings.gd")
const Simulation = preload("res://scripts/simulation.gd")
const WorldView = preload("res://scripts/world3d.gd")

const URGENT := 3                 # stopping the town growing, or about to go wrong
const WARNING := 2                # holding things back
const ADVICE := 1                 # worth knowing
const NO_OVERLAY := -1

# Why zone plots aren't growing, read from the reasons simulation.gd's
# _zone_check() gives (via zone_status()). [phrase in that text, key]. Every
# phrase that appears in a plot's reason is counted, so keep them distinct. If
# _zone_check()'s wording changes, update the phrase here or the tip goes quiet.
const REASONS := [
	["needs a road within", "road"],
	["link it to a power plant", "power_link"],
	["power plant is full", "power_full"],
	["needs water to grow any bigger", "water_link"],
	["needs more water to grow", "water_full"],
	["rubbish is piling up", "rubbish"],
	["taxes are high for the services", "taxes"],
	["town needs more jobs", "jobs"],
	["town needs more residents", "residents"],
	["town needs more workers", "workers"],
	["railway station or bus depot", "sky_transit"],
	["waiting for a school", "school"],
	["land value too low", "land_value"],
	["no police station", "police"],
	["hospital nearby", "hospital"],
	# Hook (pollution): when _zone_check() gains a pollution reason, add its
	# phrase here, e.g. ["pollution", "pollution"], and a tip in tips().
]


static func tips(sim: Simulation) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var survey := _survey(sim)
	var stuck: Dictionary = survey["stuck"]
	var zones: int = survey["zones"]
	var broken: Array[int] = []
	broken.assign(survey["broken"])
	var power_kind := WorldView.Overlay.POWER
	var water_kind := WorldView.Overlay.WATER
	var services_kind := WorldView.Overlay.SERVICES
	var growth_kind := WorldView.Overlay.GROWTH

	# --- Getting started ---
	if sim.road_tiles == 0 and zones == 0:
		_add(out, "start", ADVICE, "Start with a road, then zone homes beside it",
			"Lay a road from the Build menu, then zone homes within %d tiles of it. "
			% Settings.ROAD_REACH + "Homes also need power to grow.", NO_OVERLAY)

	# --- Money ---
	var net: int = sim.last_income - sim.last_upkeep
	if sim.money < 0:
		_add(out, "debt", URGENT, "The town is in debt: raise taxes or cut costs",
			"You've spent more than you have. Raise taxes a little, lower service funding, "
			+ "or bulldoze buildings that cost a lot to run.", NO_OVERLAY)
	elif sim.month > 0 and net < 0:
		var months: int = ceili(float(sim.money) / float(-net))
		if months <= 24:
			var when := "next month" if months <= 1 else "in about %d months" % months
			_add(out, "money", URGENT if months <= 6 else WARNING, "Money will run out %s" % when,
				"The town spends %s a month more than it takes in taxes. Raise taxes, cut " % _pounds(-net)
				+ "service funding, or grow the town to earn more.", NO_OVERLAY)

	# --- Power ---
	if sim.plants == 0:
		if zones > 0:
			_add(out, "no_power", URGENT, "No power plant yet: nothing can grow",
				"Build a power plant (Power in the Build menu). Power travels through roads, "
				+ "zones and power lines that touch.", power_kind)
	else:
		var power_full := _n(stuck, "power_full")
		if power_full > 0:
			_add(out, "power_out", URGENT, "Power has run out: %d plots can't grow" % power_full,
				"Build another power plant, or join this area to a network with spare power.",
				power_kind)
		elif sim.power_used > sim.power_supply * 0.9:
			_add(out, "power_low", WARNING, "Power is nearly used up: build another plant",
				"Power %d of %d used. When it runs out, plots furthest from the plant go dark."
				% [sim.power_used, sim.power_supply], power_kind)
		var unlinked := _n(stuck, "power_link")
		if unlinked > 0:
			_add(out, "power_link", WARNING, "%d %s no power: link them to a plant"
				% [unlinked, "plot has" if unlinked == 1 else "plots have"],
				"Power travels through roads, zones and power lines that share an edge. "
				+ "Join these plots to something that has power.", power_kind)

	# --- Buildings that aren't working ---
	if not broken.is_empty():
		var first: int = sim.tiles[broken[0]]
		var water_down := false
		for i: int in broken:
			var t: int = sim.tiles[i]
			if t == Simulation.Tile.WATER_PUMP or t == Simulation.Tile.WATER_TOWER:
				water_down = true
		var text := "%s not working: needs a road and power" % _name_of(sim, first)
		if broken.size() > 1:
			text = "%d buildings aren't working: no road or power" % broken.size()
		_add(out, "broken", URGENT if water_down else WARNING, text,
			"Services and most buildings need a road within %d tiles, and power. " % Settings.ROAD_REACH
			+ "The Power view shows what's connected.", power_kind)

	# --- Water ---
	var water_unlinked := _n(stuck, "water_link")
	var water_full := _n(stuck, "water_full")
	if sim.water_supply == 0:
		if water_unlinked > 0:
			_add(out, "no_water", URGENT, "Homes can't grow: no water yet. Build a water pump",
				"Anything bigger than a first-level plot needs water. Build a water pump or "
				+ "tower (Utilities); water travels through roads and buildings, like power.",
				water_kind)
	else:
		if water_full > 0:
			_add(out, "water_out", URGENT, "Water has run out: %d plots can't grow" % water_full,
				"Build another water pump or tower (Utilities), and check your pumps have a "
				+ "road and power.", water_kind)
		elif sim.water_used > sim.water_supply * 0.9:
			_add(out, "water_low", WARNING, "Water is nearly used up: build another pump",
				"Water %d of %d used. When it runs out, plots can't grow any bigger."
				% [sim.water_used, sim.water_supply], water_kind)
		if water_unlinked > 0:
			_add(out, "water_link", WARNING, "%d %s no water: link them to a pump"
				% [water_unlinked, "plot has" if water_unlinked == 1 else "plots have"],
				"Water travels through roads and buildings that touch. Join these plots to a "
				+ "road that has water, or build a pump or tower near them.", water_kind)

	# --- Rubbish ---
	var rubbish := sim.rubbish_shortfall()
	if rubbish > 0.3:
		_add(out, "rubbish", URGENT if _n(stuck, "rubbish") > 0 else WARNING,
			"Rubbish is piling up: build a landfill",
			"Uncollected rubbish puts people off moving here. Build a landfill or recycling "
			+ "centre (Utilities) with a road; recycling also needs power.", NO_OVERLAY)
	elif rubbish > 0.0:
		_add(out, "rubbish_some", ADVICE, "Some rubbish isn't collected: add landfill space",
			"The town makes more rubbish than its landfills and recycling can take.", NO_OVERLAY)

	# --- Roads ---
	var no_road := _n(stuck, "road")
	if no_road >= 3:
		_add(out, "road", WARNING, "%d plots can't grow: no road within %d tiles"
			% [no_road, Settings.ROAD_REACH],
			"Zones need a road within %d tiles (one more near a bus depot). " % Settings.ROAD_REACH
			+ "Build a road closer, or bulldoze the far plots.", WorldView.Overlay.ROADS)

	# --- Taxes and services ---
	var appeal := sim.appeal()
	var high_tax: bool = sim.tax_rate > Settings.DEFAULT_TAX_RATE + 0.005
	var tax_tip := false
	if high_tax and appeal < 0.0:
		_add(out, "leaving", URGENT, "Taxes are high and services poor: people are leaving",
			"People put up with high taxes only when they get good services for them. "
			+ "Lower taxes, or build police, fire, schools and hospitals near homes.", services_kind)
		tax_tip = true
	elif high_tax and appeal < 0.3:
		_add(out, "taxes", WARNING, "Taxes are putting people off: lower them a little",
			"High taxes with patchy services stop people moving in. Lower taxes, or "
			+ "improve services near homes.", services_kind)
		tax_tip = true
	if not tax_tip and sim.services_word() == "poor":
		_add(out, "services", WARNING if appeal < 0.3 else ADVICE, "Services are poor for a town this size",
			"Bigger towns expect police, fire, schools and hospitals near their homes. "
			+ "Poor cover makes people less keen to move here.", services_kind)

	# --- Fire ---
	if sim.population >= Settings.FIRE_START_POP:
		var fire_stations: int = sim.services[Simulation.Service.FIRE]
		var fire_funding: float = sim.funding[Simulation.Service.FIRE]
		if fire_stations == 0:
			_add(out, "fire", WARNING, "Fire risk: the town has no fire station",
				"Buildings with no fire station nearby can burn down (industry most often). "
				+ "Build one (Services) with a road and power.", services_kind)
		elif fire_funding <= 0.0:
			_add(out, "fire_closed", WARNING, "Fire risk: the fire stations are closed",
				"Fire funding is at 0%. Raise it to open them again.", services_kind)

	# --- Schools, police, hospitals ---
	var school := _n(stuck, "school")
	if school > 0:
		var schools: int = sim.services[Simulation.Service.SCHOOL]
		var text := "Families need a school: build one" if schools == 0 \
			else "%d %s a school nearby to grow" % [school, "plot needs" if school == 1 else "plots need"]
		_add(out, "school", WARNING, text,
			"In a town of over %d people, homes won't grow past terraces without " % Settings.SCHOOL_NEEDED_POP
			+ "a school nearby.", services_kind)
	var police := _n(stuck, "police")
	if police >= 5:
		_add(out, "police", ADVICE, "%d plots grow slowly: no police nearby" % police,
			"In a town of over %d people, homes and shops with no police station " % Settings.POLICE_NEEDED_POP
			+ "nearby grow at half speed.", services_kind)
	var hospital := _n(stuck, "hospital")
	if hospital >= 5:
		_add(out, "hospital", ADVICE, "%d homes grow slowly: no hospital nearby" % hospital,
			"In a town of over %d people, homes with no hospital nearby grow at " % Settings.HOSPITAL_NEEDED_POP
			+ "half speed.", services_kind)

	# --- Skyscrapers and taller buildings ---
	var no_transit := _n(stuck, "sky_transit")
	if no_transit > 0:
		_add(out, "sky_transit", ADVICE, "Big blocks need a station or bus depot to go higher",
			"Skyscrapers need a working railway station or bus depot within %d m."
			% (Settings.SKYSCRAPER_TRANSIT * 50), growth_kind)
	var low_value := _n(stuck, "land_value")
	if low_value >= 5:
		_add(out, "land_value", ADVICE, "%d plots need better land to build taller" % low_value,
			"Taller buildings need higher land value. Parks, shops, leisure and services "
			+ "raise it; industry and power plants lower it.", WorldView.Overlay.LAND_VALUE)

	# --- Jobs and workers ---
	var want_jobs := _n(stuck, "jobs")
	if want_jobs >= 10 and (sim.demand_for(Simulation.Tile.INDUSTRY) > 0.0
			or sim.demand_for(Simulation.Tile.SHOPS) > 0.0):
		_add(out, "jobs", ADVICE, "Homes are waiting for jobs: zone industry or shops",
			"People won't move in until there's work. The demand bars show what's wanted.",
			growth_kind)
	var want_people := _n(stuck, "residents") + _n(stuck, "workers")
	if want_people >= 10 and sim.demand_for(Simulation.Tile.HOMES) > 0.0:
		_add(out, "people", ADVICE, "Businesses are waiting for people: zone more homes",
			"Shops need residents and industry needs workers before they grow.", growth_kind)

	# --- Hooks for systems being added alongside ---
	# Happiness: when the simulation has a happiness score with reasons, add a tip
	# here when it's low, using its biggest reason as the text (WARNING, or URGENT
	# if people are leaving), with the overlay that shows that reason.
	# Pollution: when the simulation tracks pollution, add a tip when many homes sit
	# in polluted air ("Homes near industry are polluted: add parks or move
	# industry away"), pointing at the pollution map view, and add the zone reason
	# phrase to REASONS above.

	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var sa: int = a["severity"]
		var sb: int = b["severity"]
		if sa != sb:
			return sa > sb
		var ra: int = a["rank"]
		var rb: int = b["rank"]
		return ra < rb
	)
	return out


static func _survey(sim: Simulation) -> Dictionary:
	# One pass over the map: why zone plots are stuck (reason key -> plots), how
	# many zone plots there are, and which buildings aren't working.
	var stuck := {}
	var zones := 0
	var broken: Array[int] = []
	for i: int in sim.w * sim.h:
		var t: int = sim.tiles[i]
		if sim.is_zone(t):
			zones += 1
			var why := sim.zone_status(i)
			for entry: Array in REASONS:
				var phrase: String = entry[0]
				if why.contains(phrase):
					var key: String = entry[1]
					stuck[key] = int(stuck.get(key, 0)) + 1
		elif sim.is_service(t):
			# A closed service (0% funding) is the player's choice, not a fault.
			if sim.service_status(i).begins_with("not working"):
				broken.append(i)
		elif sim.is_building(t) and not sim.building_working(i):
			broken.append(i)
	return {"stuck": stuck, "zones": zones, "broken": broken}


static func _add(out: Array[Dictionary], id: String, severity: int, text: String, detail: String,
		overlay: int) -> void:
	out.append({"id": id, "severity": severity, "text": text, "detail": detail,
		"overlay": overlay, "rank": out.size()})


static func _n(stuck: Dictionary, key: String) -> int:
	var n: int = stuck.get(key, 0)
	return n


static func _name_of(sim: Simulation, t: int) -> String:
	if sim.is_service(t):
		var s: String = Settings.SERVICE_NAMES[t - Simulation.Tile.POLICE]
		return s
	return sim.building_name(t)


static func _pounds(amount: int) -> String:
	var digits := str(absi(amount))
	var out := ""
	while digits.length() > 3:
		out = "," + digits.substr(digits.length() - 3) + out
		digits = digits.substr(0, digits.length() - 3)
	return "£" + digits + out
