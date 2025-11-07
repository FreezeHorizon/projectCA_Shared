extends Node2D

# Scene path for enemy cards
const ENEMY_CARD_SCENE_PATH = "res://Scenes/EnemyCard.tscn" 

# temporary right now
var enemy_deck_card_names: Array[String] = ["Bilwis", "Irad", "Erge", "Ereshkigal", "Aesma","Irad","Irad","Irad","Irad","Irad"] # Example enemy starting deck
var enemy_emperor_card_name: String = "VedaEmperor1" # Example enemy emperor (can be same as player's or different)

func _ready() -> void:
	enemy_deck_card_names.shuffle()
	update_remaining_cards_display()
	set_deck_clickable(false) 


func update_remaining_cards_display() -> void:
	var remaining_cards_label = get_node_or_null("remainingCards")
	if is_instance_valid(remaining_cards_label):
		remaining_cards_label.text = 'x' + str(enemy_deck_card_names.size())

	var card_back_sprite = get_node_or_null("CardBack")
	if is_instance_valid(card_back_sprite):
		card_back_sprite.visible = enemy_deck_card_names.size() > 0
		if is_instance_valid(remaining_cards_label):
			remaining_cards_label.visible = card_back_sprite.visible

func can_draw_card() -> bool:
	return enemy_deck_card_names.size() > 0

func draw_card() -> Node2D:
	if not can_draw_card():
		printerr("EnemyDeck: Attempted to draw from empty deck!")
		return null

	var card_name_drawn: String = enemy_deck_card_names.pop_front()
	
	if not CardDatabase.CARDS.has(card_name_drawn):
		printerr("EnemyDeck: Card name '", card_name_drawn, "' not found in database!")
		# Optionally, put the card_name_drawn back into the deck or handle error
		return null
		
	var card_data: Dictionary = CardDatabase.CARDS[card_name_drawn]
	update_remaining_cards_display()

	var card_scene: PackedScene = load(ENEMY_CARD_SCENE_PATH)
	var new_enemy_card_node = card_scene.instantiate() # Cast to EnemyCard if it has class_name

	new_enemy_card_node.name = "Enemy_" + str(card_name_drawn) + "_" + str(randi_range(1,1000))
	new_enemy_card_node.initialize_card_from_database(card_name_drawn, card_data)

	# EnemyCard node should handle its own visual setup based on its card_data.
	# Example: new_enemy_card_node.setup_visuals() if such a method exists in EnemyCard.gd
	# For now, we'll do basic texture setup here if the above method isn't assumed.
	_setup_basic_enemy_card_visuals(new_enemy_card_node, card_name_drawn, card_data)


	return new_enemy_card_node

func draw_emperor() -> Node2D: # Should ideally return type EnemyCard
	if enemy_emperor_card_name == "":
		printerr("EnemyDeck: No enemy emperor card name defined!")
		return null
	
	if not CardDatabase.CARDS.has(enemy_emperor_card_name):
		printerr("EnemyDeck: Emperor card name '", enemy_emperor_card_name, "' not found in database!")
		return null

	var card_data: Dictionary = CardDatabase.CARDS[enemy_emperor_card_name]
	
	var card_scene: PackedScene = load(ENEMY_CARD_SCENE_PATH)
	var new_emperor_node = card_scene.instantiate()
	new_emperor_node.name = "Enemy_Emperor_" + str(randi_range(1,1000)) # Unique name
	
	new_emperor_node.initialize_card_from_database(enemy_emperor_card_name, card_data)
	
	_setup_basic_enemy_card_visuals(new_emperor_node, enemy_emperor_card_name, card_data)
		
	return new_emperor_node

func return_card_name_to_deck(card_name: String) -> void:
	if CardDatabase.CARDS.has(card_name):
		enemy_deck_card_names.append(card_name)
		enemy_deck_card_names.shuffle() # Good to shuffle when cards are returned
		update_remaining_cards_display()
		print("EnemyDeck: Returned '", card_name, "' to enemy deck. Size: ", enemy_deck_card_names.size())
	else:
		printerr("EnemyDeck ERROR: Could not find card ID '", card_name, "' in database to return.")

func set_deck_clickable(_clickable: bool) -> void: # Parameter is unused as enemy deck is not clickable
	var collision_shape = get_node_or_null("Area2D/CollisionShape2D")
	if is_instance_valid(collision_shape):
		collision_shape.disabled = true # Enemy deck is generally not clickable by the player

#-----------------------------------------------------------------------------
# INTERNAL HELPER METHODS
#-----------------------------------------------------------------------------

# Helper to set up basic visuals on the card node.
# Ideally, EnemyCard.gd handles most of this in its own setup method after data is set.
func _setup_basic_enemy_card_visuals(card_node: Node2D, card_name_key: String, card_data: Dictionary) -> void:
	var card_image = card_node.get_node_or_null("CardImage") # Adjust path as per your EnemyCard.tscn
	if not is_instance_valid(card_image):
		printerr("EnemyDeck: CardImage node not found in ", card_node.name)
		return

	card_image.texture = setCardTexture(card_name_key, card_data.get("atlasPath", ""))
	
	var stats_node = card_image.get_node_or_null("Stats")
	if is_instance_valid(stats_node):
		var card_type = card_data.get("type", -1) # Default to an invalid type
		# Assuming CardDatabase has direct access to enums if it's an instance of CardDatabase.gd
		# Or use GameConstants if enums are there.
		# For this example, assuming direct access for simplicity.
		match card_type:
			GameConstants.CardType.ARTIFACT, GameConstants.CardType.SPELL:
				stats_node.visible = false
			GameConstants.CardType.PLOY:
				stats_node.visible = false
				if card_data.has("health") and card_data["health"] > 0:
					var health_img_node = stats_node.get_node_or_null("HealthImage")
					if is_instance_valid(health_img_node): health_img_node.visible = true
			_: # Default case for HERO or other types with stats
				stats_node.visible = true

		var attack_label = stats_node.get_node_or_null("AttackImage/Attack")
		if is_instance_valid(attack_label): attack_label.text = str(card_data.get("attack", 0))
		
		var health_label = stats_node.get_node_or_null("HealthImage/Health")
		if is_instance_valid(health_label): health_label.text = str(card_data.get("health", 0))
	
	var ap_cost_node = card_node.get_node_or_null("ApCostImage/Cost")
	if is_instance_valid(ap_cost_node): ap_cost_node.text = str(card_data.get("apCost", 0))
	
	var type_node = card_node.get_node_or_null("TypeImage/Type")
	if is_instance_valid(type_node): type_node.text = str(card_data.get("type", "N/A"))


# Helper for texture loading
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
