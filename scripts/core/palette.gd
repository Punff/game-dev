class_name Palette
extends RefCounted

## Shared colour language for UI, world and effects.

const BG_DEEP := Color("100f1f")
const BG := Color("1a1830")
const PANEL := Color("23203d")
const PANEL_HI := Color("2e2a50")
const LINE := Color("4a4475")
const TEXT := Color("f3efff")
const TEXT_DIM := Color("a39dc7")
const ACCENT := Color("ffc94a")     # warm gold, focus / highlights
const ACCENT_2 := Color("ff5e7e")   # hot pink, danger / titles
const GOOD := Color("4ade80")
const LAVA := Color("ff6a2b")

const PLAYER_COLORS: Array[Color] = [
	Color("ff4d6d"), # red
	Color("3fa7ff"), # blue
	Color("ffd23f"), # yellow
	Color("3ee089"), # green
	Color("c77dff"), # purple
	Color("ff8c42"), # orange
	Color("2de2e6"), # cyan
	Color("ff7eb9"), # pink
]

const PLAYER_COLOR_NAMES: Array[String] = ["Red", "Blue", "Yellow", "Green", "Purple", "Orange", "Cyan", "Pink"]

## Block colours: [body, highlight] keyed by block id.
const BLOCKS := {
	"static_platform": [Color("3d4470"), Color("5d6aa8")],
	"bounce_pad": [Color("1f9e5a"), Color("4be38f")],
	"speed_block": [Color("d9822b"), Color("ffbe5c")],
	"breakable_block": [Color("8a5a3c"), Color("b98560")],
	"conveyor_block": [Color("5b45c4"), Color("8b78ff")],
	"push_zone": [Color("c2413d"), Color("ff7a70")],
	"vanishing_block": [Color("2a8fa8"), Color("6fe3ff")],
	"ice_block": [Color("8fc9ef"), Color("e6f6ff")],
	"moving_platform": [Color("596282"), Color("8b95bd")],
	"reverse_block": [Color("b02e7c"), Color("ff6ac1")],
}
