extends Node

## Match-wide state that every system needs and nobody owns: the world seed, the party's
## shared gold, and where the run currently is.

signal phase_changed(phase: Phase)
signal gold_changed(gold: int)
signal seed_changed(world_seed: int)

enum Phase { LOBBY, PLAYING, VICTORY, DEFEAT }

var phase: Phase = Phase.LOBBY:
	set(value):
		if phase != value:
			phase = value
			phase_changed.emit(phase)

## Broadcast by the host at match start. Every peer builds the identical 16-chunk world from
## it -- the map is never streamed, so this number is the entire world transfer.
var world_seed: int = 0

## Gold is a party pool rather than per-player. Four friends arguing over who gets the coin is
## not the game this wants to be.
var gold: int = 0:
	set(value):
		var clamped: int = maxi(0, value)
		if gold != clamped:
			gold = clamped
			gold_changed.emit(gold)


func reset_for_match(new_seed: int) -> void:
	world_seed = new_seed
	gold = 0
	seed_changed.emit(world_seed)


func roll_seed() -> int:
	return abs(int(Time.get_unix_time_from_system() * 1000.0)) % 2147483647


## Every chunk derives its own generator from the world seed and its index, so chunk 7 looks
## the same whether it was built first or last, on the host or on a client.
func chunk_rng(chunk_index: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(world_seed) ^ (chunk_index * 2654435761)
	return rng
