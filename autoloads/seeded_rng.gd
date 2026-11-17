class_name SeededRng

## Fisher-Yates shuffle using a seeded RNG. Falls back to Array.shuffle() when rng is null.
static func shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	if rng:
		for i in range(arr.size() - 1, 0, -1):
			var j := rng.randi() % (i + 1)
			var tmp = arr[i]
			arr[i] = arr[j]
			arr[j] = tmp
	else:
		arr.shuffle()


## Pick a random element. Falls back to Array.pick_random() when rng is null.
static func pick(arr: Array, rng: RandomNumberGenerator) -> Variant:
	if arr.is_empty():
		return null
	if rng:
		return arr[rng.randi() % arr.size()]
	return arr.pick_random()


## Weighted pick. `weight_of` maps an element to its relative weight; elements
## weighted <= 0 are never chosen. Falls back to an even pick() when every weight
## is <= 0, so a mis-authored weight can't make a whole pool undrawable.
static func pick_weighted(arr: Array, rng: RandomNumberGenerator, weight_of: Callable) -> Variant:
	if arr.is_empty():
		return null
	var total := 0.0
	for e in arr:
		total += maxf(0.0, float(weight_of.call(e)))
	if total <= 0.0:
		return pick(arr, rng)
	var roll := (rng.randf() if rng else randf()) * total
	for e in arr:
		roll -= maxf(0.0, float(weight_of.call(e)))
		if roll < 0.0:
			return e
	# Float rounding only: the roll consumed every weight without going negative.
	return arr[arr.size() - 1]


## Random integer in [lo, hi] inclusive. Falls back to randi_range() when rng is null.
static func irange(rng: RandomNumberGenerator, lo: int, hi: int) -> int:
	if rng:
		return rng.randi_range(lo, hi)
	return randi_range(lo, hi)
