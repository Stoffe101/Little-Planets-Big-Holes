class_name Pal
extends RefCounted
## The one shared colour palette for everything that is modelled in code (tools, machines,
## base structures, props, robots, artifacts, effects). See docs/ART_DIRECTION.md.
##
## Rule of thumb: neutrals carry the form, AMBER marks "ours / interactive / upgradeable",
## TEAL marks energy, screens and scanning, and strong hues belong to valuable resources only.
## If you need a new colour, add it here with a reason - do not sprinkle hex codes in models.

# ---- painted equipment and architecture
const HULL := Color("#e6e3dc")          ## warm off-white painted panels (dominant machine colour)
const HULL_SHADE := Color("#c9c6be")    ## recessed / secondary painted panels
const GRAPHITE := Color("#32363c")      ## frames, housings, vents, dark trim
const CHARCOAL := Color("#23262b")      ## deepest dark: louvres, inside of nozzles, tyres
const RUBBER := Color("#2b2d31")        ## grips, hoses, seals, feet
const STEEL := Color("#aab0b6")         ## bare machined metal
const STEEL_DARK := Color("#727981")    ## cast / unpolished metal
const STEEL_BLUE := Color("#6f8296")    ## blued tool steel (mid tier blades and bits)
const CONCRETE := Color("#a3a39c")      ## pads and foundations
const CONCRETE_DARK := Color("#85857f")
const GLASS := Color("#5f9bbd")         ## glazing, lenses, sight glasses
const GLASS_DARK := Color("#25404f")

# ---- signal colours (use sparingly)
const AMBER := Color("#f0a22e")         ## brand accent: stripes, handles, interactive parts
const AMBER_DARK := Color("#c47c18")
const TEAL := Color("#39c4b4")          ## energy, screens, scanner, status lights
const TEAL_DARK := Color("#1f7f78")
const RED := Color("#d4523f")           ## hazard / warning / "too hard"
const GREEN := Color("#62c483")         ## confirmation (sell pad, positive numbers)

# ---- humble starter-tool materials
const WOOD := Color("#8f6e4c")
const WOOD_DARK := Color("#6f4f31")
const RUST := Color("#8c563c")
const RUST_DARK := Color("#6a402e")
const TAPE := Color("#c9c2b2")          ## worn cloth grip tape
const BRASS := Color("#b99547")

# ---- natural props
const ROCK := Color("#8d9097")
const ROCK_WARM := Color("#978f86")
const ROCK_DARK := Color("#6c7078")
const BARK := Color("#6a5a4c")

# ---- light colours
const LAMP_WARM := Color("#ffe2b0")
const LAMP_COOL := Color("#cfe6ff")

## Accent colour that identifies a tool tier on the model and in the UI (1-based tier).
const TIER_ACCENTS: Array[Color] = [Color("#9a5a3a"), Color("#6f8296"), Color("#f0a22e"), Color("#39c4b4")]


static func tier_accent(tier: int) -> Color:
	return TIER_ACCENTS[clampi(tier - 1, 0, TIER_ACCENTS.size() - 1)]
