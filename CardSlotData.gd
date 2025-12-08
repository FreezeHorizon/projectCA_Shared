class_name CardSlotData
extends RefCounted

# The name/ID of the slot, e.g., "A1", "C4"
var slot_name: StringName

var is_occupied: bool = false
var card_in_slot: BaseCard = null
var grid_position: Vector2i 

func _init(name: StringName, pos: Vector2i):
	self.slot_name = name
	self.grid_position = pos
