# Protocol-Z

Protocol-Z is a multiplayer Godot project with survival, building, combat, and zombie AI. It mixes a fun retro style with systems like hunger, thirst, inventory, crafting/building, loot spawning, and networked gameplay.

## Features

- Singleplayer
- Multiplayer support
- First-person movement, jumping, and crouching
- Health, hunger, and thirst systems
- Inventory with item tracking
- Axe/combat interactions
- Tree harvesting
- Zombie enemies with wander/chase behavior
- Loot spawning system
- Building system with placeable structures

## Gameplay

You play as a survivor in a hostile world where you need to gather resources, manage your needs, and stay alive while dealing with enemies.
- Collect logs, rocks, food, and water
- Chop trees for resources
- Fight enemies
- Place structures to build a base
- Manage hunger, thirst, and health
- Explore for loot and survive longer

## Controls

- **WASD** — Move
- **Space** — Jump
- **1 / 2 / 3** — Empty Hands / Axe / Torch
- **Mouse Left Click** — Attack / Pickup / Place buildable
- **Mouse Right Click** — Throw your held item / cancel build
- **E** — Put item in inventory
- **Esc** — Pause / unpause
- **I** — Open Inventory
- **Ctrl** — Crouch
- **T** — Chat (Multiplayer)

## Systems

### Player
The player script includes:
- health
- speed and jumping
- mouse sensitivity
- hunger and thirst
- inventory tracking
- building/placing structures

### Enemy AI
Enemies:
- start in wander mode
- switch to chase mode when a player enters range
- use NavigationAgent3D to move
- take damage and die with delayed cleanup

### Trees
Trees:
- take damage from player actions
- play hit/fall effects
- spawn log drops when destroyed
- sync break/fall behavior across multiplayer

### Loot Spawning
Loot spawning:
- random spawn positions
- max active loot limits
- configurable spawn interval
- optional spawn amounts and exit tracking

### Building
The player can build many different structures such as:
- house
- campfire
- table
- bed
- stairs
- tent
- raspberry bush
- lamp
- wall
- floor

### Optimisation

- I optimised the game by using a timer for the enemy so that it isnt updating its pathfinding system every frame and it only does it every 0.1 seconds. I also optimised it by making it so that the enemys rotation doesnt do the same and it updates to where it is going every 0.35 seconds. This improved the FPS drastically and improved it from 40fps to a solid 60fps
- I also noticed that the many trees rendering were causing issues so i implemented an LOD system, if the tree is far enough away it hides it to save VRAM and leave out more GPU and RAM headroom. This removed all the stuttering i was experiencing.
