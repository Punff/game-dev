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

const PLAYER_COLORS: Array[Color] = [
	Color("c9503a"), # red
	Color("4f86b0"), # blue
	Color("d9b043"), # yellow
	Color("6e9a5c"), # green
	Color("8f6aa6"), # violet
	Color("cf7d3c"), # orange
	Color("5aa3a0"), # cyan
	Color("c47490"), # pink
]

const PLAYER_COLOR_NAMES: Array[String] = ["Red", "Blue", "Yellow", "Green", "Violet", "Orange", "Cyan", "Pink"]

## Block colours: [face, accent] keyed by block id.
const BLOCKS := {
	"static_platform": [Color("7a7266"), Color("d8cdb0")],
	"bounce_pad": [Color("5d7a45"), Color("b7c98a")],
	"speed_block": [Color("c99a3e"), Color("0e0c0b")],
	"breakable_block": [Color("c9b993"), Color("6d6250")],
	"conveyor_block": [Color("2f7473"), Color("9fd3cc")],
	"push_zone": [Color("b5573a"), Color("ecc6a4")],
	"vanishing_block": [Color("51657a"), Color("b8c8d8")],
	"ice_block": [Color("a3bfc8"), Color("f2efe6")],
	"moving_platform": [Color("4b6a8c"), Color("d8e4f0")],
	"reverse_block": [Color("7e1f2c"), Color("f08a9a")],
}
