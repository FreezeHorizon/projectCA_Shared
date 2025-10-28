# Card.gd (Player Card)
class_name Card extends BaseCard # Inherits from BaseCard

signal hovered(card_instance: Card) 
signal hovered_off(card_instance: Card)

#signal card_selected(card_instance: Card) # This card was selected on board


#-----------------------------------------------------------------------------
# LIFECYCLE METHODS
#-----------------------------------------------------------------------------
func _ready() -> void:
	super._ready() # CORRECTED: Call super for _ready (usually works like this or with ())
	self.is_player_card = true 
	self.scale = Vector2(0.5, 0.5)
	self.position = Vector2(1110.0, 631.0)
	if scale == Vector2.ONE: 
		scale = Vector2(0.5, 0.5) 
	
	var area_2d = get_node_or_null("Area2D")
	if is_instance_valid(area_2d):
		if not area_2d.mouse_entered.is_connected(_on_area_2d_mouse_entered):
			area_2d.mouse_entered.connect(_on_area_2d_mouse_entered)
		if not area_2d.mouse_exited.is_connected(_on_area_2d_mouse_exited):
			area_2d.mouse_exited.connect(_on_area_2d_mouse_exited)
	else:
		printerr("Card '", name, "': Area2D node not found for input signals.")
	add_to_group("PlayerCards")

#func _process(_delta: float) -> void: #for debugging purposes
	#if self.is_emperor_card:
		#print(self.position)
		#print((randi()%2)+1) 
#-----------------------------------------------------------------------------
# VISUAL UPDATE IMPLEMENTATIONS (Overrides from BaseCard)
#-----------------------------------------------------------------------------
func _update_visuals_from_data() -> void:
	super._update_visuals_from_data() # CORRECTED (or can be omitted if base is just 'pass')
	# print("Card '", name, "': Updating visuals. Data: ", get_current_card_data_dict())

	# Paths must match your Card.tscn structure
	var card_image_node = get_node_or_null("CardImage")
	if is_instance_valid(card_image_node) and atlas_path_info != "" and atlas_region_info.size() == 4:
		var new_atlas = AtlasTexture.new()
		var atlas_res = load(atlas_path_info)
		if atlas_res is AtlasTexture: new_atlas.atlas = atlas_res.atlas
		elif atlas_res is Texture2D: new_atlas.atlas = atlas_res
		else: printerr("Card '", name, "': Failed to load atlas from path: ", atlas_path_info); return
		
		new_atlas.region = Rect2(atlas_region_info[0], 
								atlas_region_info[1], 
								atlas_region_info[2], 
								atlas_region_info[3])
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
		else: # Fallback if GameConstants not ready or enums missing
			match card_type_to_check: 
				3, 4: stats_node.visible = false # Assuming ARTIFACT=3, SPELL=4 from old enum
				2: # PLOY
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
	super._update_health_visual() # CORRECTED (or can be omitted if base is just 'pass')
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
	super._update_visual_state() # Call base if it ever has shared logic

	var card_image_node = get_node_or_null("CardImage")
	var card_back_image_node = get_node_or_null("CardBackImage") # Assuming this is the name
	var ap_cost_node = get_node_or_null("ApCostImage")
	var type_image_node = get_node_or_null("TypeImage")

	# Basic check for essential display nodes
	if not is_instance_valid(card_image_node) or not is_instance_valid(card_back_image_node):
		printerr(name, ": CardImage or CardBackImage node missing in _update_visual_state!")
		return

	print(name, ": _update_visual_state() called. is_face_down = ", is_face_down, ", card_is_in_slot = ", is_instance_valid(card_is_in_slot))

	if not is_instance_valid(card_is_in_slot): # Card is IN HAND (Player's perspective)
		print("	 Card.gd: In hand. Forcing face-up.")
		card_image_node.visible = true
		card_back_image_node.visible = false
		if is_instance_valid(ap_cost_node): ap_cost_node.visible = true
		if is_instance_valid(type_image_node): type_image_node.visible = true
		# Stats visibility is handled by _update_visuals_from_data based on card type
		return 
	
	# Card is ON THE BOARD
	if is_face_down: 
		print("	 Card.gd: On board & IS FACE DOWN. Hiding face, showing back.")
		card_image_node.visible = false
		card_back_image_node.visible = true
		print("    >> IMMEDIATELY AFTER SET: card_image.visible = ", card_image_node.visible, ", card_back.visible = ", card_back_image_node.visible)
		if is_instance_valid(ap_cost_node): ap_cost_node.visible = false
		if is_instance_valid(type_image_node): type_image_node.visible = false
		# if is_instance_valid(highlight_node): highlight_node.visible = false 
	else: # On board & IS FACE UP
		print("	 Card.gd: On board & IS FACE UP. Showing face, hiding back.")
		card_image_node.visible = true
		card_back_image_node.visible = false
		print("    >> IMMEDIATELY AFTER SET: card_image.visible = ", card_image_node.visible, ", card_back.visible = ", card_back_image_node.visible)
		# For face-up cards on board, AP cost and Type images are usually hidden by CardStateMachine's ON_BOARD_ENTER
		# Ensure they are hidden here as well if that's the design.
		if is_instance_valid(ap_cost_node): ap_cost_node.visible = false 
		if is_instance_valid(type_image_node): type_image_node.visible = false

	# print(name, ": Visual state updated. Is face down: ", is_face_down)

#-----------------------------------------------------------------------------
# INPUT HANDLERS (Specific to Player Card)
#-----------------------------------------------------------------------------
func _on_area_2d_mouse_entered() -> void:
	var mulligan_manager = get_node_or_null("../../MulliganManager") # Path might need adjustment from Main
	var in_mulligan_phase = is_instance_valid(mulligan_manager) and mulligan_manager.mull_phase
	
	if not card_is_in_slot and not in_mulligan_phase and state_machine.get_current_state() == state_machine.State.IN_HAND:
		# This hover logic is now primarily handled by PlayerHand.gd
		# This card can emit a signal, but PlayerHand decides the "true" hover.
		# state_machine.transition_to(state_machine.State.HOVERING) # Let PlayerHand manage this transition
		pass
	
	emit_signal("hovered", self)

func _on_area_2d_mouse_exited() -> void:
	emit_signal("hovered_off", self)
