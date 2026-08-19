class_name Transport
extends RefCounted

## The one place that knows what kind of MultiplayerPeer this game speaks.
##
## Everything above it deals in peer ids and RPCs, which are transport-agnostic, so swapping
## ENet for a SteamMultiplayerPeer later means editing this file and nothing else. That is the
## whole reason it exists as a seam rather than two lines inlined in NetworkManager.

const DEFAULT_PORT := 27015
const MAX_PEERS := 4


static func create_server(port: int = DEFAULT_PORT) -> MultiplayerPeer:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PEERS)
	if err != OK:
		push_error("Transport: could not host on port %d (%s)" % [port, error_string(err)])
		return null
	return peer


static func create_client(address: String, port: int = DEFAULT_PORT) -> MultiplayerPeer:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		push_error("Transport: could not reach %s:%d (%s)" % [address, port, error_string(err)])
		return null
	return peer
