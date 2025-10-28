# File: GameConstants.txt
extends Node

# Collision layer constants
const COLLISION_MASK_CARD:int = 1
const COLLISION_MASK_CARD_SLOT:int = 2
const COLLISION_MASK_DECK:int = 4 # Added from InputManager

# Card Type Enum (Sole Source)
enum CardType { 
	EMPEROR = 0, 
	HERO = 1, 
	PLOY = 2, 
	ARTIFACT = 3, 
	SPELL = 4 
}

enum TriggerSource {
	PLAYER_CHOICE,    # An active choice by the card's owner (e.g., double-click)
	EFFECT_ALLY,      # Caused by an effect from an allied card/spell
	EFFECT_ENEMY,     # Caused by an effect from an enemy card/spell
	COMBAT_REVEAL,    # Revealed by being attacked
	GAME_RULE         # Caused by a core game rule (e.g., end of turn effect)
}

# Faction Enum (Sole Source)
enum Faction {
	NEUTRAL = 0,
	LP = 1,        # Lost Paradise
	ARS = 2,       # Ars Goetia
	ONMYODO = 3,
	VEDA = 4,
	CTHULHU = 5,   # Cthulhu's Call
	PHARAOH = 6,   # Pharaoh's Curse
	OLYMPUS = 7,
	YGGDRASIL = 8,
	# SHEN_ZHOU was in CardResourceMaker but not here, added for completeness if used
	SHEN_ZHOU = 9  # From CardResourceMaker, ensure consistency if this faction is used
}

# Card scaling constants for different states
const DEFAULT_SCALING:Vector2 = Vector2(0.5,0.5)  # Normal card size
const DRAG_SCALING = Vector2(0.52,0.52)          # Slightly larger when dragging
const HIGHLIGHT_SCALING = Vector2(0.52,0.52)     # Slightly larger when highlighted
const DEFAULT_CARD_MOVE_SPEED:float = 0.4        # Speed for card movement animations
const HAND_Y_POSITION:int = 700                  # Y coordinate for cards in player's hand
const MULLIGAN_CARD_SCALE = Vector2(0.7,0.7)

# Game rule constants for unit placement and movement
const EMPEROR_PLACEMENT_RANGE:int = 6            # Initial placement range for emperor (only for initialization)
const HERO_PLACEMENT_FROM_EMPEROR:int = 2        # Heroes must be within 2 tiles of emperor
const HERO_PLACEMENT_FROM_ALLY:int = 1           # Heroes must be within 1 tile of another ally
const EMPEROR_MOVE_RANGE:int = 1                 # Emperor can only move 1 tile at a time
