extends Node
## Global signal hub (autoload "EventBus").
##
## Systems and UI never hold references to each other; they talk through
## these signals. Signals are declared here even before the build step that
## first emits them, so every phase uses the same names.
##
## Convention: ids are Strings for provinces / nations / techs / templates,
## ints for divisions and battles.

@warning_ignore_start("unused_signal")

# --- Game lifecycle -------------------------------------------------------
## Emitted after GameState has been (re)built by a new game or a load.
## UI should fully refresh when this fires.
signal game_state_ready
## Emitted when the game ends. result: "victory" | "defeat".
signal game_over(result: String)

# --- Time -----------------------------------------------------------------
signal hour_passed(hour: int)
signal day_passed(day_index: int)
signal month_passed(year: int, month: int)
## speed_index indexes TimeManager.SPEEDS. paused is separate from speed.
signal speed_changed(speed_index: int, paused: bool)

# --- Selection / map interaction -------------------------------------------
signal province_selected(province_id: String)
signal province_hovered(province_id: String)   # "" when nothing hovered
## Right click on the map (used for move orders from step 9).
signal province_right_clicked(province_id: String)
signal selection_cleared
signal division_selected(division_id: int)

# --- World state changes ---------------------------------------------------
## Owner / controller / factories / infrastructure of a province changed.
signal province_changed(province_id: String)
## Stockpile, manpower, research, relations ... of a nation changed.
signal nation_changed(nation_id: String)

# --- Production / research (steps 6-7) ------------------------------------
signal factory_completed(province_id: String)
signal research_started(nation_id: String, tech_id: String)
signal research_completed(nation_id: String, tech_id: String)

# --- Military (steps 8-11) ------------------------------------------------
signal division_created(division_id: int)
## A division's move order was given, changed, finished or cancelled (step 9).
signal division_order_changed(division_id: int)
## Several divisions selected at once on the map (step 9). Empty = unit selection cleared.
signal divisions_selected(division_ids: Array)
signal division_moved(division_id: int, from_province: String, to_province: String)
signal division_destroyed(division_id: int)
signal battle_started(province_id: String)
signal battle_ended(province_id: String, attacker_won: bool)
signal province_captured(province_id: String, new_controller: String, old_controller: String)
## The set of provinces in supply for a nation changed (step 11).
signal supply_changed(nation_id: String)
## The set of provinces visible to the player changed (step 12, fog of war).
signal fog_changed

# --- Diplomacy (step 13) --------------------------------------------------
signal war_declared(attacker: String, defender: String)
signal pact_signed(nation_a: String, nation_b: String)
signal military_access_granted(host: String, guest: String)
signal nation_capitulated(nation_id: String, conqueror: String)

# --- Tactical battles (steps 15-17) ---------------------------------------
signal tactical_battle_requested(province_id: String)
signal tactical_prompt_requested(province_id: String)
signal tactical_battle_finished(province_id: String, attacker_won: bool)

# --- Misc -------------------------------------------------------------------
## Short message for the player (event log / toast).
signal notify(text: String)

@warning_ignore_restore("unused_signal")
