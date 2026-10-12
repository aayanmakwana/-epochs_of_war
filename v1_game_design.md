# Epochs of War - V1 Design Document

## Overview

WW2 grand strategy game (1936-1945) with HOI4-style strategic gameplay. The unique feature: major city battles zoom into a turn-based tactical grid where you command divisions directly. Built in Godot 4.7 with GDScript. All assets are 2D, procedural or simple sprites. No external dependencies.

## Repository

All source code, assets, and documentation must be committed to:
https://github.com/aayanmakwana/-epochs_of_war.git

Commit frequently after each working feature or milestone. Use clear commit messages describing what was built or changed. Push all work to the main branch.

## V1 Scope (World Wars era only)

### Playable Nations (3)
- Germany: Strongest starting military, central position, industrial base
- Soviet Union: Largest manpower, vast territory, weak starting industry
- United Kingdom: Naval power, island defense, colonial resources

### Strategic Map
- Simplified Eastern Front / European theater
- 20 provinces with defined borders, adjacencies, and terrain types
- Terrain types: plains, forest, mountain, urban, marsh, coastal
- Each province has: name, terrain, resource slots, infrastructure level, owner nation, garrison
- Real-time with pause. Speed controls: pause, 1x, 2x, 3x, 5x
- Fog of war: provinces adjacent to your units or territory are visible
- Front lines rendered between enemy-adjacent provinces
- Supply: provinces connected to capital through friendly territory are in supply. Units out of supply take attrition.

### Province List (20)
1. Berlin (urban, German capital, major city)
2. East Prussia (forest)
3. Poland (plains)
4. Romania (plains, oil resource)
5. Hungary (plains)
6. Czechoslovakia (mountain)
7. Austria (mountain)
8. Western Germany (urban, factories)
9. France (plains, starts neutral)
10. Moscow (urban, Soviet capital, major city)
11. Leningrad (urban, major city)
12. Stalingrad (urban, major city)
13. Ukraine (plains, food resource)
14. Belarus (marsh/forest)
15. Caucasus (mountain, oil resource)
16. Urals (mountain, factories)
17. Siberia (forest)
18. London (urban, British capital, major city)
19. North Sea (coastal/naval zone)
20. Mediterranean (coastal/naval zone)

### Production
- Each nation has factory count (determines production speed)
- Produce 3 equipment types: infantry equipment, armor, artillery
- Production screen: assign factories to equipment type, see output per day
- Build new factories in owned provinces (takes time)
- Resources: oil (needed for armor), steel (needed for all equipment). Provinces produce resources.

### Research (15 technologies)
- 3 branches, 5 techs each:
  - Infantry: basic infantry -> improved infantry -> elite infantry -> mechanized infantry -> special forces
  - Armor: light tanks -> medium tanks -> heavy tanks -> tank destroyers -> modern armor
  - Doctrine: mass assault -> deep battle -> combined arms -> blitzkrieg -> total war
- Each tech takes in-game days to research (30-90 days)
- One tech researched at a time
- Techs improve unit stats or unlock new unit types

### Military
- Recruit divisions from manpower pool. Each division costs manpower + equipment.
- 3 division types: infantry (cheap, slow, defensive), armor (expensive, fast, offensive), artillery (support, boosts attack)
- Division stats: attack, defense, speed, organization (morale), HP
- Assign divisions to provinces. Move divisions between adjacent provinces (takes time based on speed and terrain).
- Combat: when a division enters an enemy-occupied province, battle begins. Combat resolves over multiple ticks. Attacker and defender deal damage based on attack vs defense, modified by terrain and entrenchment. Losing side retreats or is destroyed.
- No air or naval combat in v1. Naval zones block land movement unless you own them.

### Diplomacy (simplified)
- 3 actions only: declare war, offer non-aggression pact, request military access
- France starts neutral. Can be declared on by Germany (historical) or allied with UK.
- War goals: must fabricate a war goal before declaring war (takes time)
- No peace conferences in v1. War ends when a nation's capital is captured. Losing nation surrenders all provinces.

### Tactical City Battles

5 major cities trigger tactical battles: Berlin, Moscow, Leningrad, Stalingrad, London.

#### Trigger
When any army attacks a province containing a major city, the player gets a prompt: "Battle for [City]. Command your forces?" Choosing yes opens the tactical map. Choosing no auto-resolves with standard combat math.

#### Tactical Map
- Square grid, 20x20 tiles
- Tile types: street (open, normal movement), building (cover, +30% defense), rubble (half cover, slows movement), park (open), river (impassable except at bridges), bridge (chokepoint), fortification (heavy cover, +50% defense)
- Map layout procedurally generated per city with a seed. Same city always generates same layout.
- Attacker deploys units on the south/west edge. Defender deploys on the north/east edge.
- 3 objective tiles marked on the map (city center, key buildings). Attacker must capture all 3.

#### Tactical Units
Each strategic division breaks into 3 tactical units:
- Infantry squad: 3 movement, 1 range, 10 HP, 4 attack, 5 defense. Ability: dig in (+2 defense until moved)
- Armor platoon: 4 movement, 1 range, 15 HP, 7 attack, 4 defense. Ability: overrun (move and attack in one action)
- Artillery battery: 2 movement, 3 range, 8 HP, 6 attack, 2 defense. Ability: barrage (area attack, hits target tile and adjacent tiles at half damage)

#### Turn Structure
- 20 turn limit. If attacker hasn't captured all objectives by turn 20, defender wins.
- Each turn: attacker phase, then defender phase.
- Each unit gets: movement (spend movement points to move tiles) and one action (attack, ability, or overwatch).
- Overwatch: skip action, automatically fire at first enemy that moves within range during their phase.
- Flanking: attacking a unit from a tile not in its front arc (the direction it last moved) deals +50% damage.
- Morale: a unit at less than 30% HP must pass a morale check each turn or rout (removed from battle).

#### Victory
- Attacker captures all 3 objectives: attacker wins, takes the province, defender divisions take heavy casualties
- Defender holds: attacker pushed back to origin province, attacker divisions take moderate casualties
- Results applied to strategic divisions (HP loss proportional to tactical casualties)

### UI Layout
- Top bar: current date, speed controls, resource counts (manpower, oil, steel, factories), selected nation flag
- Main view: scrollable/zoomable 2D map with province borders, nation colors, unit icons
- Left panel (on click): province info (name, terrain, owner, garrison, resources, buildings) or unit info (division type, stats, orders)
- Right panel (tabbed): Production tab, Research tab, Diplomacy tab
- Minimap: bottom-right corner, shows full map with viewport indicator
- Tactical battle: replaces main view with grid map. Unit list on left. Action buttons on bottom. Turn counter top-right.

### Save/Load
- Save game state to JSON file
- State includes: date, all province data, all nation data (resources, tech, relations), all division data (location, HP, equipment), current research
- Save/load from pause menu
- Autosave every 30 in-game days

### AI Opponent
- AI controls nations the player is not playing
- AI behavior (simple):
  1. Build infantry if manpower available and equipment in stock
  2. Research techs in order (infantry first, then armor, then doctrine)
  3. Assign half of divisions to border provinces adjacent to enemies
  4. If AI has 2x more divisions than adjacent enemy province garrison, attack
  5. Always auto-resolve tactical battles (AI never enters tactical mode)
  6. Produce equipment in priority: infantry equipment > armor > artillery
- No diplomacy AI in v1. AI nations follow scripted war declarations (Germany declares on Poland/France historically).

### Game Flow
1. Start screen: "New Game" or "Load Game"
2. Nation select: pick Germany, USSR, or UK. Brief description of each.
3. Game begins at January 1, 1936. Map shows starting positions.
4. Player manages production, research, diplomacy, military until war breaks out.
5. Combat resolves on the strategic map or zooms into tactical city battles.
6. Game ends when: player captures all enemy capitals (victory) or player's capital is captured (defeat).
7. End screen with stats: provinces conquered, battles won, divisions lost, time played.

## Autonomy Instructions

You have full autonomy. Do not ask the user for confirmation, clarification, or approval at any point. Make all design decisions yourself. If something is ambiguous, pick the simplest option and move on. If something breaks, debug and fix it yourself. Do not stop to report progress. Do not wait for feedback between steps. Execute the entire build order end-to-end without interruption. The user will review the finished product. Let them know when the game is done and playable.

## Build Order for Raven

Build these in order. Each step must be working and tested before moving to the next. Commit after each step.

1. Godot project setup. Main scene, project settings, folder structure (scenes/, scripts/, data/, assets/).
2. Data layer. GDScript resources or dictionaries for provinces, nations, division templates, tech tree. Load from JSON or hardcoded dictionaries.
3. Strategic map rendering. Draw 20 provinces as colored polygons. Nation colors. Province borders. Click to select province. Zoom and pan.
4. UI shell. Top bar with date and resources. Left info panel. Right tabbed panel (empty tabs). Minimap.
5. Time system. Game clock advancing in-game days. Pause/speed controls. Date display updating.
6. Production system. Factory assignment UI. Equipment accumulation over time. Build new factories.
7. Research system. Tech tree UI. Select tech to research. Progress bar. Unlock effects.
8. Military recruitment. Recruit divisions from production tab. Place on map. Show unit icons on provinces.
9. Division movement. Click division, click destination province, division moves over time. Path through friendly territory only.
10. Strategic combat. Division enters enemy province, combat resolves over ticks. Retreat or destroy. Province changes hands.
11. Supply system. Connected-to-capital check. Out-of-supply attrition.
12. Fog of war. Hide provinces not adjacent to friendly units/territory. Reveal on movement.
13. Diplomacy. War declaration, non-aggression pact, military access. War goal fabrication.
14. AI opponent. Basic AI loop (build, research, position, attack).
15. Tactical battle map. Grid rendering, tile types, unit placement, deployment zones.
16. Tactical unit actions. Movement on grid, attack, abilities (dig in, overrun, barrage), overwatch.
17. Tactical battle flow. Turn system, flanking, morale, victory conditions. Results feed back to strategic layer.
18. Save/load. JSON serialization of full game state. Pause menu with save/load. Autosave.
19. Game flow. Start screen, nation select, end conditions, victory/defeat screen, stats.
20. Polish. Balance pass on combat numbers. UI cleanup. Bug fixes.

## Git Workflow

Repository: https://github.com/aayanmakwana/-epochs_of_war.git

After completing each build step:
1. Stage all new and modified files
2. Commit with message format: "Step X: [description of what was built]"
3. Push to main branch

Include in the repository:
- All Godot project files (project.godot, scenes, scripts, assets)
- This design document (v1_game_design.md)
- A README.md with game title, description, how to run, and current development status

Do not commit:
- .godot/ cache directory (add to .gitignore)
- OS-specific files (.DS_Store, Thumbs.db)
- Editor backup files

## Technical Constraints
- Godot 4.7, GDScript only
- No GDExtension, no C#, no external plugins
- All visuals drawn with Godot's built-in 2D tools (Polygon2D, draw_* functions, ColorRect, Label, etc.)
- No imported image assets required. All graphics procedural.
- Target resolution: 1920x1080, windowed mode
- Minimum viable AI. Do not over-engineer the AI. Simple if/else logic is fine for v1.
