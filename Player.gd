class_name Player
extends Node

var player_id: int
var current_ap: int = 0
var max_ap: int = 0
var emperor_on_board: bool = false
var has_used_extra_draw: bool = false
var extra_draw_cost: int = 2

# References to this player's nodes
var hand_node: Node
var deck_node: Node
