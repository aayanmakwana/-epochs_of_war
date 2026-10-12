# Epochs of War

## Concept

Grand strategy game spanning three playable eras (Medieval, World Wars, Modern), with HOI4-style strategic gameplay and a tactical twist: major city battles zoom into a turn-based grid where you command divisions directly.

## Eras

### Medieval (500-1500 AD)
- Factions: England, France, Holy Roman Empire, Byzantine Empire, Mongol Empire, Abbasid Caliphate
- Units: Infantry levies, knights, archers, siege engines, cavalry
- Tech tree: Feudalism, castle fortification, longbow, plate armor, gunpowder (late era)
- Resources: Gold, food, manpower, iron
- Diplomacy: Vassalage, crusades, marriage alliances, excommunication

### World Wars (1914-1945)
- Factions: Germany, UK, France, USA, USSR, Japan, Italy, Austria-Hungary, Ottoman Empire
- Units: Infantry divisions, armor, artillery, aircraft, submarines, battleships
- Tech tree: Trench warfare, tanks, radar, jet engines, rockets, nuclear weapons
- Resources: Oil, steel, rubber, aluminum, manpower
- Diplomacy: Factions (Entente/Central Powers, Allies/Axis/Comintern), war goals, peace conferences

### Modern Era (1950-2030)
- Factions: NATO nations, Russia, China, India, Middle Eastern powers
- Units: Mechanized infantry, MBTs, stealth aircraft, drones, carriers, missile systems, cyber units
- Tech tree: Nuclear deterrence, satellites, stealth, precision munitions, cyber warfare, AI-guided systems
- Resources: Oil, rare earth minerals, semiconductors, manpower, GDP
- Diplomacy: UN resolutions, sanctions, proxy wars, nuclear treaties, trade agreements

## Core Systems

### Strategic Map (HOI4 layer)
- 2D political map divided into provinces grouped into states and regions
- Each province has terrain type (plains, forest, mountain, urban, desert, coastal) affecting combat
- Real-time with pause and speed controls (1x, 2x, 3x, 5x, max)
- Fog of war based on unit and intelligence coverage
- Front lines drawn automatically between belligerent nations
- Army groups assigned to front line segments with attack/defend orders
- Supply lines from capital through controlled provinces, degrading with distance and enemy interdiction

### Production
- Factories (or era equivalent) produce equipment over time
- Build queue with priority ordering
- Construction of new factories, infrastructure, fortifications
- Equipment types per era (swords/bows, rifles/tanks, drones/missiles)
- Trade with other nations for scarce resources

### Research
- Tech tree branching into military, industrial, and doctrine paths
- Each era has 40-60 technologies
- Research speed based on literacy/education/research labs
- Some techs unlock new unit types, others improve existing ones

### Military
- Recruit divisions from manpower pool
- Division designer: choose unit composition (infantry, armor, support companies)
- Assign divisions to armies, armies to army groups
- Army groups execute strategic orders (advance, hold, fall back, encircle)
- Attrition from supply shortages, weather, terrain
- Air missions: air superiority, close air support, strategic bombing, transport
- Naval: fleet composition, sea zones, convoy raiding, amphibious assault

### Diplomacy
- Relations score per nation (-100 to +100)
- Actions: improve relations, guarantee independence, declare war, offer alliance, request military access, trade deal, non-aggression pact
- Factions/alliances that nations can join or create
- Peace conferences after wars (demand territory, puppet states, reparations)

### National Focus / Decisions
- Each major nation has a branching focus tree
- Focuses cost time and political power to complete
- Historical and alternate-history branches (democratic Germany, communist Britain, etc.)
- One-off decisions (mobilize, enact conscription, launch offensive)

## Tactical City Battles

When a major city is attacked and the player chooses to intervene, the game zooms from the strategic map into a turn-based tactical battle.

### Trigger
- Only for cities designated as "major" (capitals, strategic cities like Stalingrad, Berlin, Paris, Baghdad)
- Player prompt: "Battle for [City]. Command your forces?" Yes zooms in, No auto-resolves with standard combat math

### Tactical Map
- Grid-based city map (hex or square, 20x20 to 30x30 tiles)
- Terrain tiles: streets, buildings (cover), rubble, parks, bridges, river crossings, fortifications
- Procedurally generated based on city size and era (medieval walls/keeps, WW2 bombed-out blocks, modern high-rises)
- Fog of war per unit line of sight

### Tactical Units
- Each strategic division breaks into 3-6 tactical units on the city grid
- Unit types map from the strategic layer (infantry squad, armor platoon, artillery battery, sniper team, engineers)
- Each unit has: HP, attack, defense, movement points per turn, special abilities
- Special abilities by type:
  - Engineers: breach walls, clear rubble, build pontoon bridges
  - Snipers: long range, high single-target damage, low HP
  - Armor: high damage, slow in urban terrain, vulnerable to flanking
  - Artillery: indirect fire, area damage, cannot fire adjacent
  - Infantry: balanced, benefits most from building cover

### Turn Structure
- Attacker moves first, then defender
- Each unit gets movement points and one action (attack, defend, special ability, overwatch)
- Overwatch: unit skips action to fire on any enemy moving in its line of sight during opponent's turn
- Flanking bonus: attacking from side or rear increases damage
- Morale: units taking heavy casualties or surrounded may rout
- Turns continue until attacker captures all objective tiles or retreats

### Victory Conditions
- Attacker wins: capture all objective tiles (city center, key buildings)
- Defender wins: attacker retreats or runs out of turns (turn limit based on attacker supply)
- Result feeds back to strategic layer: city changes hands, casualties applied to divisions

## Visual Style
- 2D, clean, map-focused (HOI4 political map style)
- Province colors by nation, terrain overlays
- Unit counters/icons on strategic map (NATO military symbols)
- Tactical battles: top-down 2D grid with sprite-based units and terrain tiles
- UI: top bar (date, speed, resources), left panel (selected unit/province info), right panel (decisions/production/research)
- Minimap in corner

## Technical
- Engine: Godot 4.7
- Language: GDScript
- No external dependencies
- All assets procedural or simple 2D sprites/icons
- Save/load via JSON serialization
- Single player only (v1)

## Scope for v1
- One era fully playable: World Wars (most HOI4-like, start here)
- 5-7 playable major nations with unique focus trees
- 50+ provinces on a simplified European map
- 10+ major cities with tactical battle maps
- Full production, research, diplomacy, and military systems
- 3-5 tactical unit types
- Save/load
- Basic AI opponent (manages production, recruits, attacks)

## Stretch Goals (v2+)
- All three eras playable
- Campaign mode linking eras (medieval kingdom legacy affects WW2 nation)
- Multiplayer
- More nations, deeper focus trees
- Weather and seasons affecting combat
- Espionage system
- Modding support (data-driven nation/unit/tech definitions)
