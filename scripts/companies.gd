extends RefCounted
## Who writes to the mayor, and what they say (the tech layer's letters).
## Only words and made-up names: no rules. The simulation decides when a
## letter comes and what saying yes does (simulation.gd, Letters); this
## writes it. Each letter's text is made once, when it arrives, and saved
## with it, so it never changes.
##
## Start-ups are made up. Real companies (from the data centre on) are satire
## of their founders' public personas: no invented facts, scandals or private
## lives (see GAME_DESIGN.md, Tech layer).

const Settings = preload("res://scripts/settings.gd")

# --- Start-ups: a made-up name, a pitch, founders and a grant they ask for ---
const STARTUP_FRONTS := ["Kettle", "Drizzle", "Bramble", "Puddle", "Thistle", "Brolly", "Pebble", "Sprout",
	"Nudge", "Snack", "Hive", "Quill", "Loop", "Pixel", "Toast", "Crumb", "Wobble", "Fizz", "Biscuit", "Gutter"]
const STARTUP_ENDS := ["ly", "ify", "r", "hub", ".ai", "io", "stack", "labs", "base", "verse", "pal", "AI"]
const STARTUP_PITCHES := [
	"Uber, but for dog walking",
	"an AI that writes your shopping list, then forgets it",
	"blockchain for allotments",
	"a dating app for houseplants",
	"Netflix for bus timetables",
	"smart bins that post online when they're full",
	"sock subscriptions, but on the blockchain",
	"an app that tells you if it's raining (we're told you can also look outside)",
	"drones that deliver one chip at a time",
	"AI-powered umbrellas",
	"a social network for people who don't like social networks",
	"Airbnb for garden sheds",
	"a fitness tracker for dogs",
	"self-driving shopping trolleys",
	"an AI that answers your emails with \"per my last email\"",
	"a meditation app that shouts at you",
]
const STARTUP_FOUNDERS := ["Josh and Priya", "Tyler", "Callum and Mo", "Ana", "Kai and Freddie", "Zara",
	"Ollie and Jas", "Ruby", "Dev and Hannah", "Finn", "Leo and Amara", "Isla"]
const STARTUP_OPENINGS := [
	"Hi Mayor!",
	"Hey Mayor,",
	"Mayor! Huge fan of your zoning.",
	"Dear Mayor (can we call you boss?),",
]
const STARTUP_BRAGS := [
	"We're pre-revenue but very post-vibes.",
	"We've got a waiting list of eleven people, nine of whom are our mums.",
	"Our deck has forty slides and a rocket emoji on every one.",
	"We've disrupted three things already this week. Mostly sleep.",
	"Our growth is up 400% (we went from one user to five).",
	"We're basically the next big thing, but smaller, for now.",
]
const STARTUP_PROMISES := [
	"We'll be a unicorn by Christmas. Probably.",
	"In five years we'll be the biggest employer in town, or a funny story.",
	"You'll be able to say you knew us before we were famous.",
	"Think of it less as a grant and more as a very early ticket to the moon.",
]


static func startup_name(rng: RandomNumberGenerator) -> String:
	var front: String = STARTUP_FRONTS[rng.randi() % STARTUP_FRONTS.size()]
	var end: String = STARTUP_ENDS[rng.randi() % STARTUP_ENDS.size()]
	return front + end


static func startup_letter(rng: RandomNumberGenerator, taken: Array) -> Dictionary:
	# A start-up asking for a grant and an office plot in the Tech zone.
	# taken: names already in use (none twice in a town).
	var company := startup_name(rng)
	for n: int in 8:
		if not taken.has(company):
			break
		company = startup_name(rng)
	var pitch: String = STARTUP_PITCHES[rng.randi() % STARTUP_PITCHES.size()]
	var founders: String = STARTUP_FOUNDERS[rng.randi() % STARTUP_FOUNDERS.size()]
	var grant: int = Settings.STARTUP_GRANTS[rng.randi() % Settings.STARTUP_GRANTS.size()]
	var role := "co-founders" if founders.contains(" and ") else "founder and CEO"
	var body := "%s\n\nWe're %s: %s. %s\n\nBack us with %s and we'll move into an empty office plot in your Tech zone. %s\n\n%s, %s, %s" % [
		_pick(rng, STARTUP_OPENINGS), company, pitch, _pick(rng, STARTUP_BRAGS), _pounds(grant),
		_pick(rng, STARTUP_PROMISES), founders, role, company]
	return {"kind": "startup", "company": company, "from": founders, "pitch": pitch,
		"subject": "%s: %s" % [company, pitch], "body": body, "grant": grant}


static func startup_news(kind: String, s: Dictionary, amount: int = 0) -> String:
	# A line of news about a start-up the town backed.
	var name: String = s.get("name", "A start-up")
	match kind:
		"grow":
			return "%s has raised a seed round and taken on more staff." % name
		"fold":
			return "%s has \"pivoted to AI\" and quietly closed. Its office is empty again." % name
		"acquired":
			return "%s has been bought by a big tech firm! The town's stake pays out %s." % [name, _pounds(amount)]
	return ""


static func expired_news(letter: Dictionary) -> String:
	return "%s gave up waiting and went to a town that answers its post." % String(letter.get("company", "A company"))


# --- Data centres: real companies, satire of their founders' public personas ---
# [company, who signs, the letter]. Sizes and terms are added by the card
# (Settings.DC_SCALES), so the words never go out of step with the numbers.
const DATA_CENTRE_LETTERS := [
	["Amazon", "Jeff Bezos",
		"Mayor,\n\nAt Amazon it is always Day 1. Today, it is Day 1 for your town.\n\n"
		+ "We would like to build a data centre in your Tech zone. Your residents will never see inside it, never "
		+ "visit it and never stop needing it. It will need power. Quite a lot of power.\n\n"
		+ "Pick the size that suits you. We have taken the liberty of assuming it's the biggest.\n\n"
		+ "Jeff Bezos, Amazon"],
	["Microsoft", "Satya Nadella",
		"Dear Mayor,\n\nWe want to help every person on the planet achieve more. Your town is on the planet, "
		+ "so here we are.\n\nWe'd love to bring a cloud data centre to your Tech zone, built with a growth "
		+ "mindset and a great deal of electricity. We are learners, not know-it-alls, so we'll learn how much "
		+ "water it drinks as we go.\n\nWith gratitude,\nSatya Nadella, Microsoft"],
	["Google", "Sundar Pichai",
		"Dear Mayor,\n\nThank you so much for your time. Google would be honoured to build an AI-ready data "
		+ "centre in your AI-curious town, powering AI features for AI users, with AI.\n\n"
		+ "It would mean a great deal to us, and to AI. We have also put AI in the cooling.\n\n"
		+ "Warm regards,\nSundar Pichai, Google"],
]


static func data_centre_letter(rng: RandomNumberGenerator, busy: Array) -> Dictionary:
	# A data centre offer from a company that isn't already building one here
	# (busy: companies with a deal or letter already). {} if they all are.
	var free := []
	for entry: Array in DATA_CENTRE_LETTERS:
		if not busy.has(entry[0]):
			free.append(entry)
	if free.is_empty():
		return {}
	var e: Array = free[rng.randi() % free.size()]
	return {"kind": "data_centre", "company": e[0], "from": "%s, %s" % [e[1], e[0]],
		"subject": "%s wants to build a data centre in your Tech zone" % e[0], "body": e[2], "big": true}


static func scale_terms(scale: Dictionary) -> String:
	# One line for a size of data centre: what it needs and what it brings.
	var asks := []
	var years: int = scale.get("break_years", 0)
	if years > 0:
		asks.append("no tax for %d years" % years)
	if bool(scale.get("priority", false)):
		asks.append("power before homes when it runs short")
	return "%d tiles · %d power · %d water · %d jobs · %s tax a month · %s invested%s" % [
		int(scale["tiles"]), int(scale["power"]), int(scale["water"]), int(scale["jobs"]),
		_pounds(int(scale["tax"])), _pounds(int(scale["investment"])),
		("\nAsks for: " + ", ".join(asks)) if not asks.is_empty() else ""]


static func deal_news(kind: String, deal: Dictionary) -> String:
	var company: String = deal.get("company", "A company")
	match kind:
		"open":
			return "%s's data centre is open: %s invested in the town." % [company, _pounds(int(deal.get("investment", 0)))]
		"gave_up":
			return "%s gave up waiting for a site and built its data centre somewhere else." % company
		"left":
			return "%s has closed its data centre here and left." % company
	return ""


static func _pick(rng: RandomNumberGenerator, list: Array) -> String:
	var s: String = list[rng.randi() % list.size()]
	return s


static func _pounds(amount: int) -> String:
	var digits := str(absi(amount))
	var out := ""
	while digits.length() > 3:
		out = "," + digits.substr(digits.length() - 3) + out
		digits = digits.substr(0, digits.length() - 3)
	return "£" + digits + out
