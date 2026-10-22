class_name Daily
extends RefCounted

## The daily climb: one solo map per UTC day, the same for everyone, as many
## tries as you like - your best counts. You race ghosts: your own best run
## today (kept on this computer, so it works offline) and your friends' best
## (from the server, signaling/src/daily.js).
##
## A ghost is where a ball was every STEP s of its run, from the start:
## {"step": STEP, "pts": [x, y, x, y, ...]} in whole px.

const STEP := 0.1
const DIR := "user://daily"
## Long runs keep only this many points (10 min): the server's limit too.
const MAX_POINTS := 6000


## Today, UTC: "YYYY-MM-DD". Everyone's "today" changes at the same moment.
static func today() -> String:
	return Time.get_date_string_from_system(true)


## The map seed for a day: the same on every computer.
static func seed_for(day: String) -> int:
	return posmod(hash("cakum-pakum daily " + day), 2000000000) + 1


static func version() -> String:
	return str(ProjectSettings.get_setting("application/config/version"))


## Your best run of `day` on this computer: {"height", "time", "version",
## "ghost"}, or {} if you haven't climbed it here.
static func local_best(day: String) -> Dictionary:
	var f := FileAccess.open("%s/%s.json" % [DIR, day], FileAccess.READ)
	if f == null:
		return {}
	var data: Variant = JSON.parse_string(f.get_as_text())
	return data if data is Dictionary else {}


## Keeps the run if it beats this computer's best for the day. True if it did.
static func keep_if_best(day: String, run: Dictionary) -> bool:
	var best := local_best(day)
	if not best.is_empty() and (best.height > run.height or best.height == run.height and best.time <= run.time):
		return false
	DirAccess.make_dir_recursive_absolute(DIR)
	var f := FileAccess.open("%s/%s.json" % [DIR, day], FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(run))
	return true


## Whether a ghost fits this game's map (another version may build it differently).
static func fits(run: Dictionary) -> bool:
	return str(run.get("version", "")) == version() and run.get("ghost") is Dictionary
