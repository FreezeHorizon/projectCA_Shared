extends Node

const atlas_path = {
	ARTIFACT ="res://Assets/CardAtlas/ArtifactAtlas.tres",
	LP = "res://Assets/CardAtlas/LostParadiseUnitAtlas.tres",
	NEUTRAL_1 ="res://Assets/CardAtlas/Neutral1UnitAtlas.tres",
	NEUTRAL_2 = "res://Assets/CardAtlas/Neutral2UnitAtlas2.tres",
	ONMYODO_1 = "res://Assets/CardAtlas/OnmyodoUnitAtlas1.tres",
	ONMYODO_2 = "res://Assets/CardAtlas/OnmyodoUnitAtlas2.tres",
	PHARAOH = "res://Assets/CardAtlas/PharaohUnitAtlas.tres",
	SKIN = "res://Assets/CardAtlas/SkinListAtlas.tres",
	ARS = "res://Assets/CardAtlas/ArsGeotiaUnitAtlas.tres",
	SPELL_1 = "res://Assets/CardAtlas/SpellAtlas.tres",
	SPELL_2 = "res://Assets/CardAtlas/SpellAtlas2.tres",
	SPELL_3 = "res://Assets/CardAtlas/SpellAtlas3.tres",
	VEDA = "res://Assets/CardAtlas/VedaUnitAtlas.tres",
}

const CARDS = { #Attack,Health,#ApCost,#Type #AtlasRegion #Faction
	# TYPE [ 0 = Emperor, 1 = Hero , 2 = Ploy , 3 = Artifact, 4 = Spell
	#Sample [0,0,0,0,[0,0,207,252],atlas_path.FACTION_NAME, FACTION_NAME]
	"VedaEmperor1": {
		"attack": 0,
		"health": 20,
		"apCost": 0,
		"type": GameConstants.CardType.EMPEROR, 
		"atlasRegion": [2, 1176, 207, 252],
		"atlasPath": atlas_path.VEDA,
		"faction": GameConstants.Faction.VEDA, 
		"moveRange": 1,
		"attackRange": 1
	},
	"Heros": {
		"attack": 5,
		"health": 4,
		"apCost": 4,
		"type": GameConstants.CardType.HERO, 
		"atlasRegion": [1762, 510, 207, 252],
		"atlasPath": atlas_path.NEUTRAL_1,
		"faction": GameConstants.Faction.NEUTRAL, 
		"moveRange": 3,
		"attackRange": 1
	},
	"Bilwis": {
		"attack": 5,
		"health": 4,
		"apCost": 4,
		"type": GameConstants.CardType.HERO, 
		"atlasRegion": [838, 1526, 207, 252],
		"atlasPath": atlas_path.NEUTRAL_1,
		"faction": GameConstants.Faction.NEUTRAL, 
		"moveRange": 2,
		"attackRange": 1
	},
	"Irad": {
		"attack": 2,
		"health": 3,
		"apCost": 2,
		"type": GameConstants.CardType.HERO, 
		"atlasRegion": [1256, 1780, 207, 252],
		"atlasPath": atlas_path.NEUTRAL_1,
		"faction": GameConstants.Faction.NEUTRAL, 
		"moveRange": 1,
		"attackRange": 1
	},
	"Cain": {
		"attack": 10,
		"health": 10,
		"apCost": 10,
		"type": GameConstants.CardType.HERO, 
		"atlasRegion": [717, 764, 207, 252],
		"atlasPath": atlas_path.NEUTRAL_1,
		"faction": GameConstants.Faction.NEUTRAL, 
		"moveRange": 1,
		"attackRange": 1
	},
	"Ereshkigal": {
		"attack": 5,
		"health": 5,
		"apCost": 8,
		"type": GameConstants.CardType.HERO, 
		"atlasRegion": [838, 1780, 207, 252],
		"atlasPath": atlas_path.NEUTRAL_1,
		"faction": GameConstants.Faction.NEUTRAL, 
		"moveRange": 1,
		"attackRange": 1
	},
	"Aesma": {
		"attack": 2,
		"health": 1,
		"apCost": 2,
		"type": GameConstants.CardType.HERO, 
		"atlasRegion": [629, 1780, 207, 252],
		"atlasPath": atlas_path.NEUTRAL_1,
		"faction": GameConstants.Faction.NEUTRAL, 
		"moveRange": 1,
		"attackRange": 1
	},
	"Erge": {
		"attack": 4,
		"health": 3,
		"apCost": 4,
		"type": GameConstants.CardType.HERO, 
		"atlasRegion": [1553, 764, 207, 252],
		"atlasPath": atlas_path.NEUTRAL_1,
		"faction": GameConstants.Faction.NEUTRAL, 
		"moveRange": 1,
		"attackRange": 1
	}
}

func get_card_data(card_key: String) -> Dictionary:
	if CARDS.has(card_key):
		return CARDS[card_key].duplicate()
	else:
		printerr("CardDatabase: Key '", card_key, "' not found.")
		return {}
