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
