extends Node
## Persistent player progress, lives, currencies and the squad roster.

signal changed

const SAVE_PATH := "user://save.json"
const MAX_LIVES := 5
const LIFE_REFILL_SECONDS := 20 * 60
const FREE_LIVES_LEVELS := 2  # the first missions never cost a life
const GEMS_FOR_LIVES := 10
const GEMS_FOR_REVIVE := 5

const FIRST_NAMES := [
	"Pip", "Bolt", "Rivet", "Dash", "Sprocket", "Moss", "Flint", "Juniper", "Cobble", "Wren",
	"Ziggy", "Basil", "Tumble", "Rook", "Pebble", "Marlo", "Sunny", "Gizmo", "Hazel", "Tank",
	"Clover", "Ollie", "Pickle", "Nova", "Bram", "Kit", "Fennel", "Rusty", "Mabel", "Scout",
	"Buttons", "Tilly", "Domino", "Ferris", "Quill", "Echo", "Barley", "Dot", "Mungo", "Pepper",
]
const RANKS := ["Recruit", "Private", "Corporal", "Sergeant", "Lieutenant", "Captain", "Major"]

# Squad paint jobs (cosmetics). Price in coins, 0 = owned by default.
const SKINS := {
	"leaf": {"name": "Woodland", "color": Color(0.62, 0.78, 0.52), "price": 0},
	"sky": {"name": "Urban Grey", "color": Color(0.72, 0.74, 0.78), "price": 400},
	"bubble": {"name": "Desert Tan", "color": Color(1.0, 0.86, 0.62), "price": 600},
	"gold": {"name": "Arctic White", "color": Color(1.1, 1.1, 1.12), "price": 1500},
	"night": {"name": "Night Ops", "color": Color(0.32, 0.34, 0.4), "price": 2500},
}

var lives := MAX_LIVES
var last_refill_unix := 0
var coins := 0
var gems := 20
var stars := {}  # level index (String) -> best stars 0..3
var unlocked := 1
var roster: Array = []  # [{name, rank, kills, missions}]
var fallen: Array = []  # [{name, rank, level}]
var recruit_counter := 0
var skin := "leaf"
var owned_skins: Array = ["leaf"]
var no_ads := false
var unlimited_lives := false
var last_daily_day := -1
var daily_streak := 0
var bonus_grenades := 0
var bonus_rockets := 0
var music_on := true
var sfx_on := true
var interstitial_counter := 0


func _ready() -> void:
	load_game()
	_ensure_roster(5)
	tick_lives()


func _process(_delta: float) -> void:
	# Cheap, runs once a second at most.
	if Engine.get_process_frames() % 60 == 0:
		tick_lives()


# ---------------------------------------------------------------- lives

func now_unix() -> int:
	return int(Time.get_unix_time_from_system())


func tick_lives() -> void:
	if lives >= MAX_LIVES:
		last_refill_unix = now_unix()
		return
	var elapsed := now_unix() - last_refill_unix
	if elapsed >= LIFE_REFILL_SECONDS:
		var gained := int(elapsed / LIFE_REFILL_SECONDS)
		lives = min(MAX_LIVES, lives + gained)
		last_refill_unix += gained * LIFE_REFILL_SECONDS
		save_game()
		changed.emit()


func seconds_to_next_life() -> int:
	if lives >= MAX_LIVES:
		return 0
	return max(0, LIFE_REFILL_SECONDS - (now_unix() - last_refill_unix))


func has_life_for(level: int) -> bool:
	return unlimited_lives or level < FREE_LIVES_LEVELS or lives > 0


func lose_life(level: int) -> void:
	if unlimited_lives or level < FREE_LIVES_LEVELS:
		return
	if lives >= MAX_LIVES:
		last_refill_unix = now_unix()
	lives = max(0, lives - 1)
	save_game()
	changed.emit()


func add_lives(n: int) -> void:
	lives = min(MAX_LIVES, lives + n)
	save_game()
	changed.emit()


func buy_lives_with_gems() -> bool:
	if gems < GEMS_FOR_LIVES:
		return false
	gems -= GEMS_FOR_LIVES
	add_lives(MAX_LIVES)
	return true


# ---------------------------------------------------------------- daily reward

const DAILY_REWARDS := [
	{"coins": 100}, {"coins": 150}, {"gems": 3}, {"coins": 250},
	{"grenades": 3}, {"coins": 400}, {"gems": 10},
]


func today_index() -> int:
	return int(now_unix() / 86400)


func daily_available() -> bool:
	return last_daily_day != today_index()


func claim_daily() -> Dictionary:
	if not daily_available():
		return {}
	var day := today_index()
	if last_daily_day == day - 1:
		daily_streak = (daily_streak + 1) % DAILY_REWARDS.size()
	else:
		daily_streak = 0
	last_daily_day = day
	var reward: Dictionary = DAILY_REWARDS[daily_streak]
	coins += reward.get("coins", 0)
	gems += reward.get("gems", 0)
	bonus_grenades += reward.get("grenades", 0)
	save_game()
	changed.emit()
	return reward


# ---------------------------------------------------------------- roster

func _new_recruit() -> Dictionary:
	recruit_counter += 1
	var n: String = FIRST_NAMES[(recruit_counter * 7 + 3) % FIRST_NAMES.size()]
	if recruit_counter > FIRST_NAMES.size():
		n += " " + str(int(recruit_counter / FIRST_NAMES.size()) + 1)
	return {"name": n, "rank": 0, "kills": 0, "missions": 0}


func _ensure_roster(n: int) -> void:
	while roster.size() < n:
		roster.append(_new_recruit())


func squad_for(size: int) -> Array:
	_ensure_roster(size)
	return roster.slice(0, size)


func rank_name(rank: int) -> String:
	return RANKS[clampi(rank, 0, RANKS.size() - 1)]


func skin_color() -> Color:
	return SKINS.get(skin, SKINS["leaf"])["color"]


## Called at the end of a mission. survivors / dead are roster indices.
func finish_mission(level: int, won: bool, survivors: Array, dead: Array, kills: Dictionary, star_count: int, coins_earned: int) -> void:
	for i in kills.keys():
		if i < roster.size():
			roster[i]["kills"] += kills[i]
	if won:
		for i in survivors:
			roster[i]["missions"] += 1
			roster[i]["rank"] = min(RANKS.size() - 1, roster[i]["rank"] + 1)
	# Fallen soldiers go to the Roll of Honour and are replaced.
	var dead_sorted := dead.duplicate()
	dead_sorted.sort()
	dead_sorted.reverse()
	for i in dead_sorted:
		var s: Dictionary = roster[i]
		fallen.append({"name": s["name"], "rank": s["rank"], "level": level + 1})
		roster.remove_at(i)
	_ensure_roster(5)
	coins += coins_earned
	if won:
		var key := str(level)
		stars[key] = max(int(stars.get(key, 0)), star_count)
		unlocked = max(unlocked, min(Levels.count(), level + 2))
	else:
		lose_life(level)
	save_game()
	changed.emit()


func total_stars() -> int:
	var t := 0
	for k in stars:
		t += int(stars[k])
	return t


# ---------------------------------------------------------------- persistence

func save_game() -> void:
	var data := {
		"lives": lives, "last_refill_unix": last_refill_unix, "coins": coins, "gems": gems,
		"stars": stars, "unlocked": unlocked, "roster": roster, "fallen": fallen,
		"recruit_counter": recruit_counter, "skin": skin, "owned_skins": owned_skins,
		"no_ads": no_ads, "unlimited_lives": unlimited_lives, "last_daily_day": last_daily_day,
		"daily_streak": daily_streak, "bonus_grenades": bonus_grenades, "bonus_rockets": bonus_rockets,
		"music_on": music_on, "sfx_on": sfx_on, "interstitial_counter": interstitial_counter,
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))


func load_game() -> void:
	last_refill_unix = now_unix()
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var data = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		return
	lives = int(data.get("lives", lives))
	last_refill_unix = int(data.get("last_refill_unix", last_refill_unix))
	coins = int(data.get("coins", coins))
	gems = int(data.get("gems", gems))
	stars = data.get("stars", {})
	unlocked = int(data.get("unlocked", 1))
	roster = data.get("roster", [])
	for s in roster:
		s["rank"] = int(s.get("rank", 0))
		s["kills"] = int(s.get("kills", 0))
		s["missions"] = int(s.get("missions", 0))
	fallen = data.get("fallen", [])
	recruit_counter = int(data.get("recruit_counter", 0))
	skin = str(data.get("skin", "leaf"))
	owned_skins = data.get("owned_skins", ["leaf"])
	no_ads = bool(data.get("no_ads", false))
	unlimited_lives = bool(data.get("unlimited_lives", false))
	last_daily_day = int(data.get("last_daily_day", -1))
	daily_streak = int(data.get("daily_streak", 0))
	bonus_grenades = int(data.get("bonus_grenades", 0))
	bonus_rockets = int(data.get("bonus_rockets", 0))
	music_on = bool(data.get("music_on", true))
	sfx_on = bool(data.get("sfx_on", true))
	interstitial_counter = int(data.get("interstitial_counter", 0))


func reset_progress() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	lives = MAX_LIVES
	coins = 0
	gems = 20
	stars = {}
	unlocked = 1
	roster = []
	fallen = []
	recruit_counter = 0
	skin = "leaf"
	owned_skins = ["leaf"]
	no_ads = false
	unlimited_lives = false
	last_daily_day = -1
	bonus_grenades = 0
	bonus_rockets = 0
	_ensure_roster(5)
	save_game()
	changed.emit()
