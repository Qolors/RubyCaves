class_name DuelMap
extends RefCounted
## Graph of cells loaded from a map JSON (see data/figure8.json).

var map_name := ""
var cells: Array[MapCell] = []
## [{cell, facing}, {cell, facing}] for player 1 and 2 (the first spawn pair).
var spawns: Array = [{}, {}]
## Every spawn pair the map offers; the two spawns of a pair sit on opposite sides of the map.
var spawn_pairs: Array = []
var _by_id := {}


func get_cell(id: String) -> MapCell:
	if not _by_id.has(id):
		push_error("Map has no cell '%s'." % id)
		return null
	return _by_id[id]


func min_col() -> int:
	return cells.map(func(c): return c.col).min()


func max_col() -> int:
	return cells.map(func(c): return c.col).max()


func min_row() -> int:
	return cells.map(func(c): return c.row).min()


func max_row() -> int:
	return cells.map(func(c): return c.row).max()


static func from_json(text: String) -> DuelMap:
	var dto: Dictionary = JSON.parse_string(text)
	var map := DuelMap.new()
	map.map_name = dto.get("name", "Unnamed")

	for n in dto["nodes"]:
		if not n.get("passable", true):
			continue
		var cell := MapCell.new(n["id"], int(n["col"]), int(n["row"]))
		map.cells.append(cell)
		map._by_id[cell.id] = cell

	# "merged_with" names an alias for the same physical cell (where the two rings overlap).
	for n in dto["nodes"]:
		if n.get("passable", true) and n.get("merged_with", "") != "":
			map._by_id[n["merged_with"]] = map._by_id[n["id"]]

	for e in dto["edges"]:
		var a := map.get_cell(e[0])
		var b := map.get_cell(e[1])
		var d := Dirs.from_delta(b.col - a.col, b.row - a.row)
		a.link(d, b)
		b.link(Dirs.opposite(d), a)

	if dto.has("spawn_pairs"):
		for pair in dto["spawn_pairs"]:
			map.spawn_pairs.append([map._spawn(pair[0]["cell"], pair[0]["facing"]), map._spawn(pair[1]["cell"], pair[1]["facing"])])
	else:
		map.spawn_pairs.append([
			map._spawn(dto["spawn_points"]["player1"], dto["spawn_facing"]["player1"]),
			map._spawn(dto["spawn_points"]["player2"], dto["spawn_facing"]["player2"])])
	map.spawns = map.spawn_pairs[0]
	return map


func _spawn(cell_id: String, facing_name: String) -> Dictionary:
	var cell := get_cell(cell_id)
	var facing := Dirs.parse(facing_name)
	if not cell.is_open(facing):
		facing = first_open(cell, facing)
	return {"cell": cell, "facing": facing}


## First open direction, trying the given one, then right, left, back.
static func first_open(cell: MapCell, preferred: int) -> int:
	for d in [preferred, Dirs.right(preferred), Dirs.left(preferred), Dirs.opposite(preferred)]:
		if cell.is_open(d):
			return d
	return preferred


## Cells visible straight ahead, nearest first, stopping at the first wall.
static func sight_line(from: MapCell, facing: int, max_range := 16) -> Array[MapCell]:
	var result: Array[MapCell] = []
	var cur := from
	for i in max_range:
		if not cur.is_open(facing):
			break
		cur = cur.neighbor(facing)
		if cur == from:
			break
		result.append(cur)
	return result


## Shortest-path first step from a to b (BFS). Returns -1 when a == b or unreachable.
static func first_step_toward(a: MapCell, b: MapCell) -> int:
	if a == b:
		return -1
	var prev := {a: [a, Dirs.NORTH]}
	var queue: Array[MapCell] = [a]
	while not queue.is_empty():
		var cur: MapCell = queue.pop_front()
		if cur == b:
			break
		for d in 4:
			var n := cur.neighbor(d)
			if n == null or prev.has(n):
				continue
			prev[n] = [cur, d]
			queue.append(n)
	if not prev.has(b):
		return -1
	var step := b
	while prev[step][0] != a:
		step = prev[step][0]
	return prev[step][1]
