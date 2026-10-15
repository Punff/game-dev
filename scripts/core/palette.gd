class_name Palette
extends RefCounted

## Noir-jazz colour language: inky blacks, nicotine paper, mustard, rust,
## burgundy and a cold teal, like a '70s jazz record sleeve.

const INK := Color("0e0c0b")
const INK_SOFT := Color("1d1a18")
const SMOKE := Color("34302c")
const PAPER := Color("ece2c8")
const PAPER_DIM := Color("a89e86")
const MUSTARD := Color("e3a92c")
const RUST := Color("d2532a")
const BURGUNDY := Color("7e1f2c")
const TEAL := Color("2f7473")
const NAVY := Color("1a2433")

# UI aliases
const BG_DEEP := INK
const BG := INK_SOFT
const PANEL := INK_SOFT
const PANEL_HI := SMOKE
const LINE := PAPER_DIM
const TEXT := PAPER
const TEXT_DIM := PAPER_DIM
const ACCENT := MUSTARD
const ACCENT_2 := RUST
const GOOD := Color("8fb04a")
const LAVA := RUST
const POOF := Color("f08cb4")   ## pink "you're out" poof

const PLAYER_COLORS: Array[Color] = [
	Color("e8452c"), # red
	Color("3a9ad9"), # blue
	Color("f2c230"), # yellow
	Color("62b46a"), # green
	Color("b06ad9"), # violet
	Color("ef8a2e"), # orange
	Color("3fc6c0"), # cyan
	Color("ec6fa0"), # pink
]

const PLAYER_COLOR_NAMES: Array[String] = ["Red", "Blue", "Yellow", "Green", "Violet", "Orange", "Cyan", "Pink"]

## Block colours: [face, accent] keyed by block id.
const BLOCKS := {
	"static_platform": [Color("7a7266"), Color("d8cdb0")],
	"bounce_pad": [Color("5f8a3c"), Color("b8d46a")],
	"speed_block": [Color("e3a92c"), Color("0e0c0b")],
	"breakable_block": [Color("c9b993"), Color("6d6250")],
	"conveyor_block": [Color("2f7473"), Color("9fd3cc")],
	"push_zone": [Color("d2532a"), Color("f3c29a")],
	"vanishing_block": [Color("51657a"), Color("b8c8d8")],
	"ice_block": [Color("9cc8d8"), Color("ffffff")],
	"moving_platform": [Color("4b6a8c"), Color("d8e4f0")],
	"reverse_block": [Color("7e1f2c"), Color("f08a9a")],
	"hazard_block": [Color("d83a2c"), Color("0e0c0b")],
}
