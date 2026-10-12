extends "res://tests/test_base.gd"
## Step 17: "Battle for [City]. Command your forces?" prompt and tactical results
## fed back to the strategic divisions (Combat + game screen + TacticalView).

var gs: Node
var cb: Node
var tm: Node
var game: Node
var finished_events: Array = []


func setup_attack() -> DivisionState:
	gs.new_game("germany")
	gs.nation("germany").at_war_with.append("ussr")
	gs.nation("ussr").at_war_with.append("germany")
	var att: DivisionState = gs.add_division("armor", "ussr", "poland")
	autoload("Movement").order_move(att.id, "berlin")
	# What Movement does when the division reaches full progress (Movement.hostile_entry),
	# without letting a daily combat tick run first.
	att.move_progress = 1.0
	var entered: bool = autoload("Movement").hostile_entry.call(att, "berlin")
	check(not entered, "attacker held at the border while the battle runs")
	return att


func berlin_defenders() -> Array:
	return gs.divisions_in("berlin").filter(func(d): return d.owner == "germany")


func run_tests() -> void:
	gs = autoload("GameState")
	cb = autoload("Combat")
	tm = autoload("TimeManager")
	autoload("AI").enabled = false
	autoload("EventBus").tactical_battle_finished.connect(func(p, w): finished_events.append([p, w]))
	gs.new_game("germany")
	game = (load("res://scenes/game/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await process_frame

	check(cb.has_method("should_prompt") and "pending_prompts" in cb, "Combat prompt API")
	check(game.prompt_dialog is ConfirmationDialog, "game screen has the prompt dialog")

	# --- Prompt on a major-city battle involving the player; decline auto-resolves ---
	var att := setup_attack()
	check(cb.has_battle("berlin"), "AI attack on the player's Berlin starts a battle")
	check(cb.should_prompt("berlin"), "Berlin battle with the player qualifies for the prompt")
	check(cb.pending_prompts.has("berlin"), "prompt pending")
	check(tm.paused, "prompt pauses the clock")
	check_eq(game.prompt_province, "berlin", "game shows the Berlin prompt")
	check_eq(game.prompt_dialog.dialog_text, "Battle for Berlin. Command your forces?", "prompt text")
	check_eq(game.prompt_dialog.ok_button_text, "Yes", "OK = Yes")
	check_eq(game.prompt_dialog.cancel_button_text, "No", "Cancel = No")
	check(not cb.should_prompt("poland") , "non-city province never prompts")
	game.answer_prompt(false)
	check(not cb.pending_prompts.has("berlin") and not cb.is_tactical("berlin"), "No: battle stays auto-resolved")
	check(not tm.paused, "No resumes the clock")
	check(game.tactical_view == null, "No does not open the tactical view")
	tm.pause()
	var days0: int = int(cb.battle_at("berlin").get("days", 0))
	tm.advance_days(1)
	check(not cb.has_battle("berlin") or int(cb.battle_at("berlin").days) > days0, "declined battle ticks daily")

	# --- Yes opens the tactical view; ticks paused; finishing applies results and returns ---
	att = setup_attack()
	check_eq(game.prompt_province, "berlin", "prompt again")
	game.answer_prompt(true)
	await process_frame
	check(cb.is_tactical("berlin"), "Yes flags the battle tactical")
	check(game.tactical_view != null, "Yes opens the tactical view")
	var days1: int = int(cb.battle_at("berlin").days)
	tm.advance_days(1)
	check_eq(int(cb.battle_at("berlin").days), days1, "tactical battle is not auto-resolved")
	var view = game.tactical_view
	view.start_battle()
	finished_events.clear()
	TacticalAI.play_out(view.battle)
	check(view.battle.is_finished, "tactical battle finished")
	check_eq(view.phase, "finished", "view in finished phase")
	check(not cb.has_battle("berlin"), "strategic battle resolved by the tactical result")
	check_eq(finished_events.size(), 1, "tactical_battle_finished emitted")
	var att_won: bool = view.last_result.attacker_won
	check(finished_events.size() == 1 and finished_events[0] == ["berlin", att_won], "finished carries province + winner")
	check_eq(gs.province("berlin").controller, "ussr" if att_won else "germany", "controller follows the result")
	await process_frame
	await process_frame
	check(game.tactical_view == null, "view closes after the result")
	check(game.get_node("World").visible, "back on the strategic map")
	check(not tm.paused, "clock resumes after the battle")
	tm.pause()

	# --- Early exit: losses so far, then auto-resolve ---
	att = setup_attack()
	game.answer_prompt(true)
	await process_frame
	view = game.tactical_view
	view.start_battle()
	view.close()
	await process_frame
	check(game.tactical_view == null, "early exit closes the view")
	check(cb.has_battle("berlin") and not cb.is_tactical("berlin"), "early exit hands the battle back to auto-resolve")
	tm.pause()
	game.answer_prompt(false)

	# --- apply_tactical_result: attacker wins ---
	att = setup_attack()
	game.answer_prompt(false)
	tm.pause()
	var dfs: Array = berlin_defenders()
	var att_hp: float = att.hp
	var def_hp := {}
	for d in dfs:
		def_hp[d.id] = d.hp
	var cas := {att.id: 0.2}
	for d in dfs:
		cas[d.id] = 0.5
	finished_events.clear()
	cb.apply_tactical_result("berlin", true, cas)
	check_eq(gs.province("berlin").controller, "ussr", "attacker win: Berlin changes hands")
	check(not cb.has_battle("berlin"), "battle closed")
	check_eq(att.province, "berlin", "attacker entered Berlin")
	check(is_equal_approx(att.hp, att_hp * 0.8), "attacker HP loss = tactical casualties (20%)")
	var heavy_ok := true
	for d in dfs:
		var live: DivisionState = gs.division(d.id)
		if live:
			heavy_ok = heavy_ok and live.province != "berlin" and is_equal_approx(live.hp, def_hp[d.id] * 0.5 * 0.6) \
				and live.organization == 0.0
	check(heavy_ok, "defenders: 50% casualties + heavy defeat loss (40% of the rest), 0 org, retreated or destroyed")
	check(finished_events.size() == 1 and finished_events[0] == ["berlin", true], "tactical_battle_finished(berlin, true)")

	# --- apply_tactical_result: defender holds ---
	att = setup_attack()
	game.answer_prompt(false)
	tm.pause()
	att_hp = att.hp
	cb.apply_tactical_result("berlin", false, {att.id: 0.1})
	check_eq(gs.province("berlin").controller, "germany", "defender win: Berlin stays German")
	check(not cb.has_battle("berlin"), "battle closed")
	check(att.province == "poland" and not att.is_moving(), "attacker back in its origin province, halted")
	check(is_equal_approx(att.hp, att_hp * 0.9 * 0.8), "attacker: 10% casualties + moderate defeat loss (20% of the rest)")
	game.queue_free()
	await process_frame
