extends Node
## Fog of war (autoload "Fog", step 12).
##
## A nation sees:
##   - every province it controls (its territory),
##   - every province where one of its divisions stands,
##   - every province adjacent to either of those.
## Everything else is hidden ("fogged"). Visibility is derived from the map on
## demand (20 provinces, trivial), so it never goes stale and needs no save
## data. Moving a division reveals the provinces around its new position.
##
## What fog hides on the map/UI (the political map stays known, like HOI4):
## division counters, battle markers/outlines, front lines between two hidden
## provinces, the garrison and battle sections of the province info panel.
## Terrain, owner, resources and buildings stay visible.
##
## EventBus.fog_changed fires (deferred) when the PLAYER's visible set changes
## (after division created/moved/destroyed, province changes, new game/load).
## `enabled` (rules.fog_of_war, default true) switches fog off entirely
## (everything visible) - for debugging; the AI ignores fog anyway.

var enabled: bool = true
## Sorted visible provinces of the player as last announced.
var _snapshot: PackedStringArray = []
var _check_queued := false


func _ready() -> void:
	enabled = bool(GameData.rule("fog_of_war", true))
	EventBus.division_created.connect(func(_d: int) -> void: queue_check())
	EventBus.division_destroyed.connect(func(_d: int) -> void: queue_check())
	EventBus.division_moved.connect(func(_d: int, _a: String, _b: String) -> void: queue_check())
	EventBus.province_changed.connect(func(_p: String) -> void: queue_check())
	EventBus.nation_capitulated.connect(func(_n: String, _c: String) -> void: queue_check())
	EventBus.game_state_ready.connect(_on_game_state_ready)


# --- Queries -------------------------------------------------------------------

## Provinces that give [param nid] sight (controlled + occupied by its divisions).
func sight_sources(nid: String) -> Dictionary:
	var src: Dictionary = {}
	if not GameState.active or GameState.nation(nid) == null:
		return src
	for pid in GameState.controlled_provinces(nid):
		src[pid] = true
	for d: DivisionState in GameState.divisions_of(nid):
		if d.province != "":
			src[d.province] = true
	return src


## Set (pid -> true) of provinces visible to [param nid] (ignores `enabled`).
func visible_set(nid: String) -> Dictionary:
	var vis: Dictionary = {}
	for pid in sight_sources(nid):
		vis[pid] = true
		for nb in GameData.adjacent(pid):
			vis[nb] = true
	return vis


## Visible provinces of [param nid] in design-doc order.
func visible_provinces(nid: String) -> PackedStringArray:
	var s := visible_set(nid)
	var out: PackedStringArray = []
	for pid in GameData.province_ids:
		if s.has(pid):
			out.append(pid)
	return out


## Hidden provinces of [param nid] in design-doc order.
func hidden_provinces(nid: String) -> PackedStringArray:
	var s := visible_set(nid)
	var out: PackedStringArray = []
	for pid in GameData.province_ids:
		if not s.has(pid):
			out.append(pid)
	return out


func is_visible_to(nid: String, pid: String) -> bool:
	return visible_set(nid).has(pid)


## True if the PLAYER can see [param pid]. Always true with fog disabled or
## without an active game / player.
func is_visible(pid: String) -> bool:
	if not enabled or not GameState.active or GameState.player_nation == "":
		return true
	return visible_set(GameState.player_nation).has(pid)


## Set of provinces the player sees (every province when fog is off).
func player_visible_set() -> Dictionary:
	if not enabled or not GameState.active or GameState.player_nation == "":
		var all: Dictionary = {}
		for pid in GameData.province_ids:
			all[pid] = true
		return all
	return visible_set(GameState.player_nation)


## Provinces hidden from the player (empty when fog is off).
func player_hidden_provinces() -> PackedStringArray:
	var s := player_visible_set()
	var out: PackedStringArray = []
	for pid in GameData.province_ids:
		if not s.has(pid):
			out.append(pid)
	return out


func set_enabled(on: bool) -> void:
	if enabled == on:
		return
	enabled = on
	check_changes(true)


# --- Change tracking -------------------------------------------------------------

func queue_check() -> void:
	if _check_queued:
		return
	_check_queued = true
	check_changes.call_deferred()


## Emit fog_changed if the player's visible set differs from the last one
## (or always with [param force]).
func check_changes(force: bool = false) -> void:
	_check_queued = false
	if not GameState.active:
		return
	var now := _current()
	if force or now != _snapshot:
		_snapshot = now
		EventBus.fog_changed.emit()


func _current() -> PackedStringArray:
	var s := player_visible_set()
	var out: PackedStringArray = []
	for pid in GameData.province_ids:
		if s.has(pid):
			out.append(pid)
	return out


func _on_game_state_ready() -> void:
	_snapshot = PackedStringArray()
	check_changes(true)
