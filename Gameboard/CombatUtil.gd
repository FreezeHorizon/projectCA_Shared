class_name CombatUtil
extends Node

# Reference to the managers (Assign these in _ready or initialize)
var card_manager: Node2D
var client_event_handler: Node # If needed for callbacks

var combat_queue: Array = []
var processing_paused: bool = false

# --- PUBLIC API (Called by ClientEventHandler) ---

func queue_combat_sequence(data: Dictionary):
	data["type"] = "combat"
	combat_queue.append(data)
	_process_queue()

func queue_flip(card_name: String, is_face_down: bool):
	combat_queue.append({
		"type": "flip",
		"card": card_name,
		"face_down": is_face_down
	})
	_process_queue()

# --- INTERNAL PROCESSING ---

func _process_queue():
	if processing_paused or combat_queue.is_empty(): return
	
	processing_paused = true
	var event = combat_queue.pop_front()
	
	match event.type:
		"combat":
			await _play_combat_sequence(event)
		"flip":
			await _play_flip_animation(event.card, event.face_down)
	
	processing_paused = false
	_process_queue() # Next!

# --- ANIMATION LOGIC ---

func _play_combat_sequence(data: Dictionary):
	var attacker = _find_card(data.atk) as BaseCard
	var defender = _find_card(data.def) as BaseCard
	if not attacker or not defender: return

	# --- PRE-STEP: DATA PREPARATION (Silent) ---
	# If this is a reveal, load the visual data for the defender now.
	# We also set the final health value. No visual updates happen yet.
	if not data.reveal_data.is_empty():
		var r_data = data.reveal_data
		if r_data.has("db_key"):
			defender.sync_state_from_data(r_data)
	defender.current_health = data.def_hp

	# --- PHASE 1: THE ATTACK ---
	if attacker.state_machine:
		attacker.state_machine.transition_to(attacker.state_machine.State.ATTACKING)
		
	var dir_anim = attacker.get_attack_animation_direction(defender.card_is_in_slot)
	
	if attacker.has_node("AnimationPlayer"):
		var anim = attacker.get_node("AnimationPlayer")
		if anim.has_animation(dir_anim):
			attacker.prime_health_update(data.atk_hp) # Load retaliation damage
			anim.play(dir_anim)
			
			if attacker.has_signal("attack_impact_moment"):
				await attacker.attack_impact_moment
			else:
				await get_tree().create_timer(0.2).timeout
				
			# At Impact:
			# - Attacker's animation called apply_primed_health_update(), so its HP is visually correct.
			# - If defender was already face up, update their HP now for simultaneous feel.
			if data.reveal_data.is_empty():
				defender.update_health_display(data.def_hp, data.def_dead)
			
			await anim.animation_finished # Wait for retract

	if attacker.state_machine:
		attacker.state_machine.transition_to(attacker.state_machine.State.ON_BOARD_IDLE)

	# --- PHASE 2: THE REVEAL & DAMAGE DISPLAY ---
	if not data.reveal_data.is_empty():
		# Play the smooth flip animation
		defender._update_health_visual()
		
		await _play_flip_animation(defender.name, false)
		
		# Now that it's face up, call the visual update to show the red text
		
		
		await get_tree().create_timer(0.5).timeout
		
	# --- PHASE 3: DEATH ---
	if data.def_dead: await _kill_unit(defender)
	if data.atk_dead: await _kill_unit(attacker)
	
	# Final Refresh
	card_manager.board_state.precompute_all_movement_maps()
	if card_manager.has_node("CardSelectionManager"):
		card_manager.get_node("CardSelectionManager").refresh_selection_overlays()

func _kill_unit(card: BaseCard):
	print("CombatUtil: Killing ", card.name)

	# 1. Clear Slot Logic Immediately (prevents further interaction)
	if is_instance_valid(card.card_is_in_slot):
		card.card_is_in_slot.is_occupied = false
		card.card_is_in_slot.card_in_slot = null
	
	if card.has_node("Area2D/CollisionShape2D"):
		card.get_node("Area2D/CollisionShape2D").set_deferred("disabled", true)
	
	_toggle_shader_inheritance(card, true)
	
	var sel_mgr = card_manager.get_node("CardSelectionManager")
	if sel_mgr.get_selected_card() == card:
		sel_mgr.deselect_all_cards()
	
	# 2. Play Death Animation
	if card.has_node("AnimationPlayer"):
		var anim = card.get_node("AnimationPlayer")
		if anim.has_animation("Actions/Death"):
			anim.play("Actions/Death")
			await anim.animation_finished # WAIT for the dissolve
	card.queue_free()

func _play_flip_animation(card_name: String, target_is_face_down: bool):
	var card = _find_card(card_name)
	if not card: 
		print("CombatUtil: Flip failed. Card not found: ", card_name)
		return
	
	var anim_name = "Actions/FaceUpToFaceDown" if target_is_face_down else "Actions/FaceDownToFaceUp"
	print("CombatUtil: Attempting flip anim: ", anim_name, " on ", card.name)	
	
	
	if card.has_node("AnimationPlayer"):
		var anim = card.get_node("AnimationPlayer")
		if anim.has_animation(anim_name):
			anim.play(anim_name)
			await anim.animation_finished
		else:
			print("CombatUtil: Animation missing: ", anim_name)
			card.is_face_down = target_is_face_down
	else:
		print("CombatUtil: No AnimationPlayer on card.")
		card.is_face_down = target_is_face_down
	card_manager.board_state.precompute_all_movement_maps()
	if card_manager.has_node("CardSelectionManager"):
		card_manager.get_node("CardSelectionManager").refresh_selection_overlays()

func _toggle_shader_inheritance(card: Node, enable: bool):
	# List the specific visual nodes that need to dissolve
	# Adjust paths based on your exact tree structure
	var visual_paths = [
		"CardImage",
		"CardBackImage",
		"CardImage/Stats",
		"ApCostImage",
		"CardImage/Stats/AttackImage",
		"CardImage/Stats/HealthImage",
		"CardOutline",
		"TypeImage"
	]
	
	for path in visual_paths:
		var node = card.get_node_or_null(path)
		if node and node is CanvasItem:
			node.use_parent_material = enable

# In CombatUtil.gd

# Add references for the hands
var player_hand: Node2D
var enemy_hand: Node2D

# Helper to find any card, anywhere
func _find_card(card_name: String) -> BaseCard:
	if not is_instance_valid(card_manager): 
		printerr("CombatUtil CRITICAL ERROR: card_manager reference is NULL!")
		return null
	# 1. Search board (most common)
	for child in card_manager.get_children():
		if child.name == card_name:
			return child as BaseCard
	print("CombatUtil: FAILED TO FIND CARD: ", card_name)
	print("  Available children in CardManager:")
	for child in card_manager.get_children():
		print("    - ", child.name)
	return null
