class_name Pal
extends RefCounted
## The one shared colour palette for everything that is modelled in code (tools, machines,
## base structures, props, robots, artifacts, effects). See docs/ART_DIRECTION.md, "Our
## equipment": field instruments in kiln-fired enamel, bronze rings and copper hardware.
##
## Rule of thumb: terracotta ENAMEL carries the machines, BRONZE rings join and frame them,
## CREAM is for dial faces and label plates, JADE marks "ours / interactive / upgradeable",
## ION marks energy, screens and scanning, and strong hues belong to valuable resources only.
## If you need a new colour, add it here with a reason - do not sprinkle hex codes in models.

# ---- enamelled equipment and architecture
const ENAMEL := Color("#b6633f")        ## kiln-fired terracotta enamel (dominant machine colour)
const ENAMEL_SHADE := Color("#8d4a31")  ## secondary / recessed enamel panels, lower drums
const CREAM := Color("#e6dac2")         ## glazed ceramic: dial faces, label plates, insulators
const BRONZE := Color("#3d3129")        ## ring frames, bases, housings (never pure black)
const DEEP := Color("#231c18")          ## deepest dark: grille holes, nozzle insides, tyres
const RUBBER := Color("#2f2a26")        ## grips, hoses, seals, feet
const COPPER := Color("#c27c4c")        ## exposed pipework, coils, bus bars
const STEEL := Color("#aab0b6")         ## bare machined metal
const STEEL_DARK := Color("#727981")    ## cast / unpolished metal
const STEEL_BLUE := Color("#6f8296")    ## blued tool steel (mid tier blades and bits)
const CONCRETE := Color("#a7a196")      ## pads and foundations (warm stone)
const CONCRETE_DARK := Color("#8a847a")
const GLASS := Color("#5f9bbd")         ## glazing, lenses, sight glasses
const GLASS_DARK := Color("#25404f")

# ---- signal colours (use sparingly)
const JADE := Color("#55c09a")          ## our accent: handles, interactive parts, "yours" (verdigris)
const JADE_DARK := Color("#2e8a6b")
const ION := Color("#5cb7ea")           ## energy, screens, scanner, status lights
const ION_DARK := Color("#2d79a8")
const RED := Color("#d4523f")           ## hazard / warning / "too hard"
const GREEN := Color("#62c483")         ## confirmation (sell pad, positive numbers)

# ---- humble starter-tool materials
const WOOD := Color("#8f6e4c")
const WOOD_DARK := Color("#6f4f31")
const RUST := Color("#8c563c")
const RUST_DARK := Color("#6a402e")
const TAPE := Color("#c9c2b2")          ## worn cloth grip tape
const BRASS := Color("#b99547")
const LEATHER := Color("#7a5236")       ## work gloves, straps
const LEATHER_DARK := Color("#583a27")

# ---- natural props
const ROCK := Color("#8d9097")
const ROCK_WARM := Color("#978f86")
const ROCK_DARK := Color("#6c7078")
const BARK := Color("#6a5a4c")

# ---- light colours
const LAMP_WARM := Color("#ffe2b0")
const LAMP_COOL := Color("#cfe6ff")

## Accent colour that identifies a tool tier on the model and in the UI (1-based tier):
## rust (scavenged), blued steel, brass, ion.
const TIER_ACCENTS: Array[Color] = [Color("#9a5a3a"), Color("#6f8296"), Color("#c9a24a"), Color("#5cb7ea")]


static func tier_accent(tier: int) -> Color:
	return TIER_ACCENTS[clampi(tier - 1, 0, TIER_ACCENTS.size() - 1)]
