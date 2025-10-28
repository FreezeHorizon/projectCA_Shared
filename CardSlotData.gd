class_name CardSlotData
extends RefCounted

# The name/ID of the slot, e.g., "A1", "C4"
var slot_name: StringName

var is_occupied: bool = false
var card_in_slot: BaseCard = null

func _init(name: StringName):
	self.slot_name = name
