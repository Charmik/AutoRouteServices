-- Gravel bicycle profile.
--
-- Thin shim: all logic lives in lib/bike_common.lua. This file only supplies the
-- gravel-profile config and delegates to BikeCommon.make_profile(cfg). Structured
-- identically to bicycle.lua (road shim) — only speeds, surface tables, and the
-- allowed-surface gate differ.
--
-- Speed model: OSRM weights by duration, so higher speed = preferred route.
-- GRAVEL_SPEED (30) >> default_speed (15) = gravel surfaces strongly preferred over asphalt.
-- Bare track/path ride at default_speed; a track+surface=gravel rides at GRAVEL_SPEED.

api_version = 4

local BikeCommon = require('lib/bike_common')

local default_speed  = 15   -- asphalt/connector baseline; lower than road's 25 so paved = connector, not preferred
local GRAVEL_SPEED   = 30   -- preferred gravel surfaces; clearly faster than asphalt → strongly preferred
local MEDIUM_SPEED   = 16   -- rough-but-rideable gravel (sand/grass/grade4/rough smoothness): just ABOVE asphalt
                            -- so OSRM follows recorded gravel rides instead of detouring via faster paved roads,
                            -- yet still below good gravel (30). LOW_SPEED stays punitive for genuinely-avoid cases
                            -- (expressway/NHS/cobblestone) so "avoid traffic" is preserved.
local LOW_SPEED      = 3
local VERY_LOW_SPEED = 0.5

local cfg = {
  profile = "gravel",

  default_speed  = default_speed,
  medium_speed   = MEDIUM_SPEED,
  low_speed      = LOW_SPEED,
  very_low_speed = VERY_LOW_SPEED,

  -- Gravel bikes do NOT prefer paved cycleways: no cycleway speed boost (road uses the default x2). A paved
  -- cycleway keeps its paved base speed (15), a connector below GRAVEL_SPEED (30), never rivalling gravel.
  cycleway_multiplier = 1,

  -- Allowed-surface gate. Gravel accepts road surfaces AND gravel-preferred surfaces;
  -- only truly unrideable surfaces are rejected.
  is_allowed_surface = function(surface)
    if surface == nil then return true end
    if surface == "mud" then return false end
    return true
  end,

  -- Highway-type speed table. Copied from bicycle.lua with gravel-relevant overrides:
  --   track, path → default_speed (was LOW_SPEED in road; gravel uses them routinely)
  --   bridleway   → default_speed (added; not present in bicycle.lua)
  -- GRAVEL_SPEED is reserved for explicit surface=gravel tags via surface_speeds, NOT
  -- bare highway types, so a bare `track` costs default_speed, `track surface=gravel`
  -- gets GRAVEL_SPEED via the surface_speeds override in speed_handler.
  bicycle_speeds = {
    motorway        = 0,
    cycleway        = default_speed * 1.2,   -- 2 mil ways
    primary         = default_speed / 2,   -- gravel override: discourage high-traffic through-roads so
    trunk           = default_speed / 2,   -- quieter parallel alternatives win, but keep them usable as
                                           -- short connectors (LOW_SPEED detoured recorded rides ~2.5x).
                                           -- Road keeps these at its own default_speed (25), untouched.
    trunk_link      = default_speed / 3,
    primary_link    = default_speed / 3,
    secondary       = default_speed,
    secondary_link  = default_speed,
    tertiary        = default_speed,
    tertiary_link   = default_speed,
    residential     = default_speed,
    living_street   = default_speed,
    road            = default_speed,
    unclassified    = default_speed,
    service         = MEDIUM_SPEED,    -- gravel override: was LOW_SPEED (road bike treats service as
                                       -- driveways/parking). Rural service roads are the farm/field-access
                                       -- gravel these rides routinely use, so treat as unknown-gravel tier:
                                       -- rideable, just above asphalt, below known-good gravel. Private/
                                       -- driveway access is still gated by the access rules.
    track           = default_speed,   -- gravel override: was LOW_SPEED in road
    path            = default_speed,   -- gravel override: was LOW_SPEED in road
    bridleway       = default_speed,   -- gravel addition: not present in bicycle.lua
    footway         = VERY_LOW_SPEED
  },

  -- Surface speeds. Same key set as bicycle.lua; values tuned for gravel preference.
  -- Keys not explicitly listed in the spec but present in bicycle.lua are noted:
  --   "concrete:plates", "concrete:lanes", "paving_stones:lanes", "cobblestone:flattened"
  --   → assigned per the paved-family / discouraged rules in the spec.
  surface_speeds = {
    -- Preferred gravel surfaces (GRAVEL_SPEED >> asphalt → OSRM strongly prefers these)
    gravel              = GRAVEL_SPEED,
    fine_gravel         = GRAVEL_SPEED,
    compacted           = GRAVEL_SPEED,
    dirt                = GRAVEL_SPEED,
    ground              = GRAVEL_SPEED,
    earth               = GRAVEL_SPEED,
    soil                = GRAVEL_SPEED,  -- synonym for earth (Java maps it to DIRT)
    clay                = GRAVEL_SPEED,  -- firm when dry; a real unpaved gravel surface (Java maps it to DIRT)
    rock                = GRAVEL_SPEED,  -- rocky doubletrack: rideable gravel/adventure surface
    rocks               = GRAVEL_SPEED,
    unpaved             = GRAVEL_SPEED,
    laterite            = GRAVEL_SPEED,  -- lateritic-soil road/track: a real unpaved gravel surface
    pebblestone         = GRAVEL_SPEED,
    grass_paver         = GRAVEL_SPEED,
    shells              = GRAVEL_SPEED,  -- crushed/whole seashells (NL cycleways): firm, gravel-friendly
    chipseal            = GRAVEL_SPEED,  -- sealed but treated as compacted: good gravel surface

    -- Connector surfaces (paved family; usable but not preferred)
    asphalt             = default_speed,
    paved               = default_speed,
    concrete            = default_speed,
    ["concrete:plates"] = default_speed,
    ["concrete:lanes"]  = default_speed,
    tarmac              = default_speed,
    sealed              = default_speed,
    paving_stones       = default_speed,

    -- Marginal paved / mixed surfaces
    ["paving_stones:lanes"]  = LOW_SPEED,
    wood                     = LOW_SPEED,
    metal                    = LOW_SPEED,

    -- Discouraged (rough paved)
    cobblestone              = LOW_SPEED,
    ["cobblestone:flattened"]= LOW_SPEED,
    sett                     = LOW_SPEED,

    -- Rough / soft surfaces: rideable but not preferred (mud is the only hard block)
    mud                 = 0,
    sand                = MEDIUM_SPEED,  -- firm sand forest roads are ridden; rideable, slightly below good gravel
    grass               = MEDIUM_SPEED,  -- grass tracks are ridden; rideable, slightly below good gravel
    woodchips           = MEDIUM_SPEED   -- soft but rideable forest-path surface; below good gravel
  },

  -- Gravel bikes handle rough tracks well; avoid only the worst.
  tracktype_speeds = {
    grade1 = GRAVEL_SPEED,
    grade2 = GRAVEL_SPEED,
    grade3 = GRAVEL_SPEED,
    grade4 = MEDIUM_SPEED,  -- rough track but ridden; rideable, slightly below good gravel
    grade5 = MEDIUM_SPEED   -- roughest two-track, but rideable on a gravel bike. Was LOW_SPEED, which
                            -- crushed a `track+grade5` to 3 while an `unclassified+grade5` kept the
                            -- surface speed (30) — a 10x asymmetry that made OSRM detour around recorded
                            -- gravel corridors (grevel_1). Genuinely-impassable tracks are still gated by
                            -- smoothness (horrible/impassable->0) and mtb:scale (>=2 LOW, >=3 forbidden).
  },

  -- Smoothness: gravel bikes ride comfortably up to "intermediate"; bad/very_bad passable at LOW_SPEED.
  smoothness_speeds = {
    excellent       = GRAVEL_SPEED,
    good            = GRAVEL_SPEED,
    very_good       = GRAVEL_SPEED,
    intermediate    = GRAVEL_SPEED,
    bad             = LOW_SPEED,
    very_bad        = LOW_SPEED,
    horrible        = 0,
    very_horrible   = 0,
    impassable      = 0
  },

  -- Verbatim copy of bicycle.lua's avoid set. track/path/bridleway are NOT listed here
  -- (they were commented out in bicycle.lua too), so gravel can use them freely.
  avoid = Set {
    'impassable',
    'construction',
    'proposed',
  },
}

return BikeCommon.make_profile(cfg)
