class_name TurnResult
extends RefCounted

var turn: int
var actions: Array[PlayerAction] = []
var events: Array[TurnEvent] = []


func add(kind: int, actor: int, target := -1, amount := 0) -> void:
	events.append(TurnEvent.new(kind, actor, target, amount))


func has(kind: int, actor := -1) -> bool:
	return events.any(func(e: TurnEvent): return e.kind == kind and (actor < 0 or e.actor == actor))
