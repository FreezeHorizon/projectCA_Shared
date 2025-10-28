# EnemyCard.gd
class_name EnemyCard extends BaseCard # Inherits from BaseCard

#-----------------------------------------------------------------------------
# LIFECYCLE METHODS
#-----------------------------------------------------------------------------
func _ready() -> void:
	super._ready() # CORRECTED
	set_owner_is_player(false)
	if scale == Vector2.ONE:
		scale = Vector2(0.5, 0.5) 
	add_to_group("EnemyCards")

#-----------------------------------------------------------------------------
# VISUAL UPDATE IMPLEMENTATIONS (Overrides from BaseCard)
#-----------------------------------------------------------------------------
func _update_visuals_from_data() -> void:
	super._update_visuals_from_data() # CORRECTED (or omit if base is 'pass')
	
	var card_image_node = get_node_or_null("CardImage")
	if is_instance_valid(card_image_node) and atlas_path_info != "" and atlas_region_info.size() == 4:
		var new_atlas = AtlasTexture.new()
		var atlas_res = load(atlas_path_info)
		if atlas_res is AtlasTexture: new_atlas.atlas = atlas_res.atlas
		elif atlas_res is Texture2D: new_atlas.atlas = atlas_res
		else: printerr("EnemyCard '", name, "': Failed to load atlas from path: ", atlas_path_info); return
		
		new_atlas.region = Rect2(atlas_region_info[0], atlas_region_info[1], atlas_region_info[2], atlas_region_info[3])
		card_image_node.texture = new_atlas
	
	var stats_node = get_node_or_null("CardImage/Stats")
	if is_instance_valid(stats_node):
		var card_type_to_check = card_type_enum # Use the inherited variable
		# Ensure GameConstants or CardDB is correctly accessed for enums
		if GameConstants:
			match card_type_to_check:
				GameConstants.CardType.ARTIFACT, GameConstants.CardType.SPELL:
					stats_node.visible = false
				GameConstants.CardType.PLOY:
					stats_node.visible = false
					if base_health > 0: 
						var health_img_node = stats_node.get_node_or_null("HealthImage")
						if is_instance_valid(health_img_node): health_img_node.visible = true
				_: 
					stats_node.visible = true
		else: # Fallback
			match card_type_to_check:
				3,4: stats_node.visible = false
				2: 
					stats_node.visible = false
					if base_health > 0: stats_node.get_node_or_null("HealthImage").visible = true
				_: stats_node.visible = true


		var attack_label = stats_node.get_node_or_null("AttackImage/Attack")
		if is_instance_valid(attack_label): attack_label.text = str(base_attack)
		
		_update_health_visual()

	var ap_cost_node = get_node_or_null("ApCostImage/Cost")
	if is_instance_valid(ap_cost_node): ap_cost_node.text = str(base_cost)
	
	var type_display_node = get_node_or_null("TypeImage/Type")
	if is_instance_valid(type_display_node): type_display_node.text = str(card_type_enum)
	
	_update_health_visual()
	_update_visual_state()

func _update_health_visual() -> void:
	super._update_health_visual() # CORRECTED (or omit if base is 'pass')
	var health_label = get_node_or_null("CardImage/Stats/HealthImage/Health")
	if is_instance_valid(health_label):
		health_label.text = str(current_health)
		if current_health < base_health and current_health > 0:
			print("card_damanged!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!")
			health_label.add_theme_color_override("default_color", Color("#f16d87")) 
		else:
			if health_label.has_theme_color_override("default_color"): # Check if override exists before removing
				health_label.remove_theme_color_override("default_color")

func _update_visual_state() -> void:
	super._update_visual_state()

	var card_image_node = get_node_or_null("CardImage")
	var card_back_image_node = get_node_or_null("CardBackImage") # Assuming this is the name
	var ap_cost_node = get_node_or_null("ApCostImage")
	var type_image_node = get_node_or_null("TypeImage")
	var highlight_node = get_node_or_null("Highlight")

	if not is_instance_valid(card_image_node) or not is_instance_valid(card_back_image_node):
		printerr(name, ": Missing CardImage or CardBackImage node for visual state update.")
		return
	
	if not is_instance_valid(card_is_in_slot): # Enemy Card is IN HAND
		print("	 EnemyCard.gd: In hand. Forcing card back visible.")
		card_image_node.visible = true # Hide face
		card_back_image_node.visible = true # Show back
		if is_instance_valid(ap_cost_node): ap_cost_node.visible = false
		if is_instance_valid(type_image_node): type_image_node.visible = false
		return
	
	if is_face_down:
		card_image_node.visible = false
		if is_instance_valid(ap_cost_node): ap_cost_node.visible = false
		if is_instance_valid(type_image_node): type_image_node.visible = false
		card_back_image_node.visible = true
		if is_instance_valid(highlight_node): highlight_node.visible = false
	else: # Card is face-up
		card_image_node.visible = true
		if is_instance_valid(ap_cost_node): ap_cost_node.visible = true
		if is_instance_valid(type_image_node): type_image_node.visible = true
		card_back_image_node.visible = false

	print(name, ": Visual state updated. Is face down: ", is_face_down)
