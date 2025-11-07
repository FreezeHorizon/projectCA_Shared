extends Node2D

const CARD_SCENE_PATH = "res://Scenes/Card.tscn" 
# You'll likely move player_deck and emperor_card to a PlayerState object managed by BattleManager eventually
var player_deck_card_names: Array[String] = ["Bilwis", "Irad","Erge","Ereshkigal","Aesma","Bilwis", "Irad","Erge","Ereshkigal","Aesma"]
var emperor_card_name: String = "VedaEmperor1" # Just the name/ID

# drawn_card_this_turn will be managed by BattleManager or PlayerState
# is_enemy_turn will be managed by BattleManager

# --- Initialization & Mulligan ---
func _ready() -> void:
	self.set_deck_clickable(false)
	player_deck_card_names.shuffle()
	update_remaining_cards_display() # New helper function

func update_remaining_cards_display() -> void:
	if has_node("remainingCards"): # Check if the node exists
		get_node("remainingCards").text = 'x' + str(player_deck_card_names.size())
	if has_node("Area2D/CollisionShape2D") and has_node("CardBack"):
		var can_draw = player_deck_card_names.size() > 0
		get_node("Area2D/CollisionShape2D").disabled = not can_draw
		get_node("CardBack").visible = can_draw
		if has_node("remainingCards"):
			get_node("remainingCards").visible = can_draw

# --- Core Deck Operations (Called by BattleManager) ---

func can_draw_card() -> bool:
	return player_deck_card_names.size() > 0

# NEW: Returns the instantiated card node, but doesn't add it to hand or CardManager
func draw_card() -> Card: # Returns Card node or null
	if not can_draw_card():
		printerr("Deck: Attempted to draw from empty deck!")
		return null

	var card_name_drawn: String = player_deck_card_names.pop_front() # Removes and returns first element

	if not CardDatabase.CARDS.has(card_name_drawn): # Check key exists
		printerr("Deck: Card name '", card_name_drawn, "' not found in database! Cannot create card node.")
		# Optionally, put card_name_drawn back in deck or handle differently
		# player_deck_card_names.push_front(card_name_drawn) # Put it back if it was a bad key
		return null # Critical error, cannot proceed with this card

	var card_data: Dictionary = CardDatabase.CARDS[card_name_drawn]

	update_remaining_cards_display()

	var card_scene: PackedScene = load(CARD_SCENE_PATH)
	var new_card_node: Card = card_scene.instantiate() as Card # Ensure Card.gd has class_name Card
	if not is_instance_valid(new_card_node): # After instantiation
		printerr("Deck: Failed to instantiate card scene for ", card_name_drawn)
		return null
	# Setup the card node with its data (visuals and core stats)
	# This part is crucial: CardManager will become parent later.
	# For now, the card is just an orphaned node with data.
	new_card_node.name = str(card_name_drawn) + "_" + str(randi_range(1,1000))
	new_card_node.initialize_card_from_database(card_name_drawn, card_data)
	_set_card_data(new_card_node, card_name_drawn, card_data) # New helper
	new_card_node.get_node("AnimationPlayer").play("DrawFlip")
	return new_card_node

func get_emperor_card_node() -> Card: # Similar to draw_card
	if emperor_card_name == "":
		printerr("Deck: No emperor card name defined or already drawn!")
		return null
	
	var card_data: Dictionary = CardDatabase.CARDS[emperor_card_name]
	update_remaining_cards_display()
	var card_scene: PackedScene = load(CARD_SCENE_PATH)
	var new_card_node: Card = card_scene.instantiate() as Card
	new_card_node.name = emperor_card_name
	new_card_node.initialize_card_from_database(emperor_card_name, card_data)
	_set_card_data(new_card_node, emperor_card_name, card_data)
	new_card_node.get_node("AnimationPlayer").play("DrawFlip")
	return new_card_node

# For mulligan - returns an array of card NODES
func draw_mulligan(count: int) -> Array[Card]:
	print("Deck: draw_mulligan called for count: ", count)
	var mulligan_cards: Array[Card] = []
	for i in range(count):
		# print("	 Mulligan loop i: ", i) # Keep for debugging if needed
		if not can_draw_card():
			print("	 Deck: Ran out of cards during draw_mulligan.")
			break 
		var card_node = draw_card() # This now plays DrawFlip
		# print("	 draw_card returned: ", card_node) # Keep for debugging
		if is_instance_valid(card_node):
			# MulliganManager will set the MULLIGAN state after parenting.
			mulligan_cards.append(card_node)
		else:
			print("	 Deck: draw_card returned an invalid node for mulligan.")
	print("Deck: draw_mulligan returning array of size: ", mulligan_cards.size())
	return mulligan_cards

func return_card_name_to_deck(card_name: String) -> void:
	# This now takes a card name/ID, not full card_data dictionary
	if CardDatabase.CARDS.has(card_name):
		player_deck_card_names.append(card_name)
		player_deck_card_names.shuffle() # Shuffle when card is returned
		update_remaining_cards_display()
		print("Deck: Returned ", card_name, " to deck.")
	else:
		printerr("Deck ERROR: Could not find card ID '", card_name, "' in database to return.")

func setCardTexture(card_drawn:String, new_atlas_path:String) -> AtlasTexture:
	var new_atlas = AtlasTexture.new()
	new_atlas.atlas = (load(new_atlas_path) as AtlasTexture).atlas
	var region_data = CardDatabase.CARDS[card_drawn]["atlasRegion"]
	new_atlas.region = Rect2(
		region_data[0], 
		region_data[1], 
		region_data[2], 
		region_data[3]
	)
	return new_atlas

func set_deck_clickable(clickable: bool) -> void:
	if has_node("Area2D/CollisionShape2D"):
		get_node("Area2D/CollisionShape2D").disabled = not clickable

func _set_card_data(card_node_to_setup: Card, card_name_key: String, card_data_dict: Dictionary):
	var card_image = card_node_to_setup.get_node_or_null("CardImage")
	if not is_instance_valid(card_image): return # Error already printed if path is wrong

	card_image.texture = setCardTexture(card_name_key, card_data_dict["atlasPath"])
	
	var stats_node = card_image.get_node_or_null("Stats")
	if is_instance_valid(stats_node):
		# Assuming GameConstants is valid and has enums
		match card_data_dict["type"]:
			GameConstants.CardType.ARTIFACT, GameConstants.CardType.SPELL:
				stats_node.visible = false
			GameConstants.CardType.PLOY:
				stats_node.visible = false
				if card_data_dict.has("health") and card_data_dict["health"] > 0 :
					var health_image_node = stats_node.get_node_or_null("HealthImage")
					if is_instance_valid(health_image_node): health_image_node.visible = true
			_: # Default for HERO etc.
				stats_node.visible = true 
		
		var attack_label = stats_node.get_node_or_null("AttackImage/Attack")
		if is_instance_valid(attack_label): attack_label.text = str(card_data_dict["attack"])
		
		var health_label = stats_node.get_node_or_null("HealthImage/Health")
		if is_instance_valid(health_label): health_label.text = str(card_data_dict["health"])
	
	var ap_cost_node = card_node_to_setup.get_node_or_null("ApCostImage/Cost")
	if is_instance_valid(ap_cost_node): ap_cost_node.text = str(card_data_dict["apCost"])
	
	var type_node = card_node_to_setup.get_node_or_null("TypeImage/Type")
	if is_instance_valid(type_node): type_node.text = str(card_data_dict["type"])
