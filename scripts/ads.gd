extends Node
## Ads and in-app purchase facade.
##
## In this build every call is simulated so the full reward and purchase flow
## can be played end to end. To go live, replace the bodies of `show_rewarded`,
## `show_interstitial` and `purchase` with calls into the AdMob and Google Play
## Billing Godot plugins. Nothing else in the game needs to change.

signal rewarded_finished(ok: bool)
signal purchase_finished(product_id: String, ok: bool)

const SIMULATED := true
const INTERSTITIAL_EVERY := 3
const MAX_REWARDED_PER_DAY := 10

const PRODUCTS := {
	"gems_small": {"title": "Pouch of Gems", "desc": "40 gems", "price": "£0.99", "gems": 40},
	"gems_medium": {"title": "Box of Gems", "desc": "120 gems", "price": "£2.49", "gems": 120},
	"gems_large": {"title": "Chest of Gems", "desc": "400 gems", "price": "£6.99", "gems": 400},
	"starter_pack": {"title": "Starter Pack", "desc": "60 gems, 1,000 coins, 5 grenades, 3 rockets", "price": "£1.99", "gems": 60, "coins": 1000, "grenades": 5, "rockets": 3},
	"no_ads": {"title": "No Ads + Unlimited Lives", "desc": "Removes all ads and lives never run out", "price": "£4.99"},
}

var _rewarded_today := 0
var _rewarded_day := -1


func can_show_rewarded() -> bool:
	var d := Game.today_index()
	if d != _rewarded_day:
		_rewarded_day = d
		_rewarded_today = 0
	return _rewarded_today < MAX_REWARDED_PER_DAY


## Shows a rewarded ad. `rewarded_finished(true)` fires only if the player
## watched it through. The caller grants the reward.
func show_rewarded(parent: Node) -> void:
	if not can_show_rewarded():
		rewarded_finished.emit(false)
		return
	_rewarded_today += 1
	if SIMULATED:
		await _fake_ad(parent, "Rewarded ad (simulated)", 2.0)
		rewarded_finished.emit(true)


## Called between missions. Never shown in the first two missions or to
## players who bought No Ads.
func maybe_show_interstitial(parent: Node, level: int) -> void:
	if Game.no_ads or level < 2:
		return
	Game.interstitial_counter += 1
	if Game.interstitial_counter % INTERSTITIAL_EVERY != 0:
		return
	if SIMULATED:
		await _fake_ad(parent, "Ad break (simulated)", 1.5)


func purchase(parent: Node, product_id: String) -> void:
	if not PRODUCTS.has(product_id):
		purchase_finished.emit(product_id, false)
		return
	if SIMULATED:
		await _fake_ad(parent, "Google Play purchase (simulated)\n" + PRODUCTS[product_id]["title"], 1.0)
	_grant(product_id)
	purchase_finished.emit(product_id, true)


func _grant(product_id: String) -> void:
	var p: Dictionary = PRODUCTS[product_id]
	Game.gems += p.get("gems", 0)
	Game.coins += p.get("coins", 0)
	Game.bonus_grenades += p.get("grenades", 0)
	Game.bonus_rockets += p.get("rockets", 0)
	if product_id == "no_ads":
		Game.no_ads = true
		Game.unlimited_lives = true
		Game.lives = Game.MAX_LIVES
	Game.save_game()
	Game.changed.emit()


func _fake_ad(parent: Node, text: String, seconds: float) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var layer := CanvasLayer.new()
	layer.layer = 100
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.85)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(bg)
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	l.add_theme_font_size_override("font_size", 36)
	bg.add_child(l)
	parent.add_child(layer)
	await parent.get_tree().create_timer(seconds).timeout
	layer.queue_free()
