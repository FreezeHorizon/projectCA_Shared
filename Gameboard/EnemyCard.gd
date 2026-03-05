class_name EnemyCard extends BaseCard # Inherits from BaseCard

#-----------------------------------------------------------------------------
# LIFECYCLE METHODS
#-----------------------------------------------------------------------------
func _ready() -> void:
	super._ready() # CORRECTED
	set_owner_is_player(false)
	self.scale = Vector2(0.5, 0.5)
	if scale == Vector2.ONE: 
		scale = Vector2(0.5, 0.5)
	add_to_group("EnemyCards")

#-----------------------------------------------------------------------------
# VISUAL UPDATE IMPLEMENTATIONS (Overrides from BaseCard)
#-----------------------------------------------------------------------------

func _update_visual_state() -> void:
	if not is_instance_valid(card_is_in_slot):
	# --- ENEMY HAND LOGIC (Face Down) ---
		if get_node_or_null("CardImage"): get_node("CardImage").visible = false
		if get_node_or_null("CardBackImage"): get_node("CardBackImage").visible = true
		if get_node_or_null("ApCostImage"): get_node("ApCostImage").visible = false
		if get_node_or_null("TypeImage"): get_node("TypeImage").visible = false
		return

	# --- BOARD LOGIC (Run Base) ---
	super._update_visual_state()
