-- Gravel bicycle profile.
--
-- Thin shim: all logic lives in lib/bike_common.lua. This file only supplies the
-- gravel-profile config and delegates to BikeCommon.make_profile(cfg). Structured
-- identically to bicycle.lua (road shim) — only speeds, surface tables, and the
-- allowed-surface gate differ.
--
-- Speed model: OSRM weights by duration, so higher speed = preferred route.
-- GRAVEL_SPEED (45) >> default_speed (10) = gravel surfaces strongly preferred over asphalt.
-- Bare track/path ride at default_speed; a track+surface=gravel rides at GRAVEL_SPEED.

api_version = 4

local BikeCommon = require('lib/bike_common')

local default_speed  = 10   -- asphalt/connector baseline; lower than road's 25 so paved = connector, not preferred
local GRAVEL_SPEED1   = 50   -- preferred gravel surfaces; clearly faster than asphalt AND paved tracks (15) so
                            -- real gravel is strongly preferred even at a detour. At 45 vs a paved track's 15
                            -- (3x), a gravel road wins over a parallel asphalt track within ~20% extra distance
                            -- (Leipzig way 1246026219 vs asphalt track 23547831) — see PAVED_TRACK_SPEED below.
local GRAVEL_SPEED2   = 40  -- second highest priority - roads which we still want to prefer but to lose to GRAVEL_SPEED1
local MEDIUM_SPEED   = 10   -- rough-but-rideable gravel (sand/grade5/rough smoothness): kept at the asphalt
                            -- base (NOT bumped with the rest of the gravel tier) — deep sand / grade5 is
                            -- genuinely a last resort, worse than a smooth paved track, so it stays at ~10.
                            -- LOW_SPEED stays punitive for genuinely-avoid cases (expressway/NHS/cobblestone).
local LOW_SPEED      = 3
local VERY_LOW_SPEED = 0.5
local ROUGH_SPEED    = 10   -- smoothness=very_bad: rideable on a gravel bike, but nothing like a compacted or
                            -- good-smoothness gravel road, so it is demoted to a plain CONNECTOR. Sits exactly
                            -- at the asphalt baseline (default_speed 10) — below a paved track (15) and below
                            -- an unpaved footway (20), and 4x below GRAVEL_SPEED2 (40), so real gravel always
                            -- wins the tie and a rough track is ridden only when it genuinely shortcuts.
local HORRIBLE_SPEED = 5   -- smoothness=horrible: a notch below very_bad (10) and HALF the asphalt baseline,
                            -- so it is ridden only when it shortcuts more sharply still.
local IMPASSABLE_SPEED = 2  -- smoothness=impassable: the bottom rung, but still a SPEED, not a ban. The rungs
                            -- above are applied as a hard ceiling at the end of process_way, and OSRM costs a
                            -- way by length/speed, so a low-but-nonzero speed is self-limiting: at 2 km/h a
                            -- 100 m stretch already costs 180 s, so nothing but a few-metre connector is ever
                            -- worth riding. VERY_LOW_SPEED (0.5) crossed the line from "avoid" into a de-facto
                            -- ban — the way stays in the graph and routable, it is simply priced out of every
                            -- route: OSM way 1104143938 is a 4.5 m highway=path link tagged
                            -- smoothness=impassable that stitches together the gravel network west of Leipzig,
                            -- and pricing it at 0.5 km/h cost 32 s to cross 4.5 m — enough to push the whole
                            -- corridor from 256 s to over 278 s and send the route down bridleway 114840900
                            -- instead (LeipzigRoutesTest.testHorseRoads). Same reasoning that retuned
                            -- very_bad/horrible off their dead-table values; those two rungs simply were not
                            -- carried down to the bottom of the ladder when the table went live.
local FOOTWAY_UNPAVED_SPEED = 20  -- unpaved footway (surface=compacted/gravel/dirt): rideable park/greenway
                                  -- path. Well above asphalt (default_speed) and a paved footway (VERY_LOW)
                                  -- so it competes with a parallel gravel road, but clearly below a real
                                  -- gravel road/track (GRAVEL_SPEED 40) — a footway is still narrow pedestrian
                                  -- infra. Paved footways stay VERY_LOW. Tunable; the dispatch caps here.
local PAVED_TRACK_SPEED = 15  -- a PAVED track/path with a tracktype (e.g. asphalt grade1 field/riverside path,
                              -- OSM ways 844496273 / 23547831): a usable connector — above the asphalt base
                              -- (default_speed 10) — but clearly WORSE for a gravel bike than a real unpaved
                              -- gravel road. Lowered 20->15 so the gravel/asphalt-track gap widens to 3x
                              -- (45 vs 15): a parallel real-gravel road now out-weighs a shorter asphalt track
                              -- even when the gravel is a ~17% detour (Leipzig way 1246026219 vs asphalt track
                              -- 23547831). Before the ladder, is_gravel_paved_track gave it the full tracktype
                              -- speed (30), tying the parallel gravel and letting the shorter asphalt win.
                              -- Speed ladder: rough-gravel/asphalt 10 < paved-track 15 < footway 20 < gravel 45.

local cfg = {
  profile = "gravel",

  default_speed  = default_speed,
  medium_speed   = MEDIUM_SPEED,
  low_speed      = LOW_SPEED,
  very_low_speed = VERY_LOW_SPEED,
  footway_unpaved_speed = FOOTWAY_UNPAVED_SPEED,
  paved_track_speed = PAVED_TRACK_SPEED,

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
    tertiary        = default_speed / 2,
    tertiary_link   = default_speed / 3,
    residential     = default_speed,
    living_street   = default_speed,
    road            = default_speed,
    unclassified    = default_speed + default_speed / 2,
    service         = MEDIUM_SPEED,    -- gravel override: was LOW_SPEED (road bike treats service as
                                       -- driveways/parking). Rural service roads are the farm/field-access
                                       -- gravel these rides routinely use, so treat as unknown-gravel tier:
                                       -- rideable, just above asphalt, below known-good gravel. Private/
                                       -- driveway access is still gated by the access rules.
    track           = default_speed,   -- gravel override: was LOW_SPEED in road
    path            = default_speed,   -- gravel override: was LOW_SPEED in road
    bridleway       = VERY_LOW_SPEED,   -- gravel addition: not present in bicycle.lua
    footway         = VERY_LOW_SPEED
  },

  -- Surface speeds. Same key set as bicycle.lua; values tuned for gravel preference.
  -- Keys not explicitly listed in the spec but present in bicycle.lua are noted:
  --   "concrete:plates", "concrete:lanes", "paving_stones:lanes", "cobblestone:flattened"
  --   → assigned per the paved-family / discouraged rules in the spec.
  surface_speeds = {
    -- Preferred gravel surfaces (GRAVEL_SPEED >> asphalt → OSRM strongly prefers these)
    gravel              = GRAVEL_SPEED2,
    fine_gravel         = GRAVEL_SPEED2,
    compacted           = GRAVEL_SPEED1,
    dirt                = GRAVEL_SPEED2,
    ground              = GRAVEL_SPEED2,
    earth               = GRAVEL_SPEED2,
    soil                = GRAVEL_SPEED2,  -- synonym for earth (Java maps it to DIRT)
    clay                = GRAVEL_SPEED2,  -- firm when dry; a real unpaved gravel surface (Java maps it to DIRT)
    rock                = GRAVEL_SPEED2,  -- rocky doubletrack: rideable gravel/adventure surface
    rocks               = GRAVEL_SPEED2,
    unpaved             = GRAVEL_SPEED2,
    laterite            = GRAVEL_SPEED2,  -- lateritic-soil road/track: a real unpaved gravel surface
    pebblestone         = GRAVEL_SPEED2,
    grass_paver         = GRAVEL_SPEED2,
    shells              = GRAVEL_SPEED2,  -- crushed/whole seashells (NL cycleways): firm, gravel-friendly
    chipseal            = GRAVEL_SPEED2,  -- sealed but treated as compacted: good gravel surface
    grass               = GRAVEL_SPEED2,  -- grass tracks/field edges are ordinary gravel-bike terrain and are
                                         -- ridden routinely; at MEDIUM_SPEED they capped their own grade4
                                         -- tracks back to 11 (see tracktype_speeds) and lost to asphalt

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
    sett                     = default_speed,

    -- Rough / soft surfaces: rideable but not preferred (mud is the only hard block)
    mud                 = VERY_LOW_SPEED,
    sand                = MEDIUM_SPEED,  -- firm sand forest roads are ridden; rideable, slightly below good gravel
    woodchips           = MEDIUM_SPEED   -- soft but rideable forest-path surface; below good gravel
  },

  -- Gravel bikes handle rough tracks well; avoid only the worst. grade1-4 are one case: ordinary
  -- gravel-bike terrain, all at GRAVEL_SPEED. grade4 ("mostly soft, unpaved") used to sit at
  -- MEDIUM_SPEED, which made the SAME forest track 3x slower than its grade3 neighbour and, once the
  -- traffic CSV applied its unridden /2.5, slower than asphalt (11/2.5 = 4.4 vs 10) — recorded gravel
  -- rides on grade4 tracks measured 4-7 km/h in GravelGpxSpeedValidator. Only grade5 (roughest
  -- two-track) stays a notch lower. Genuinely-impassable tracks are still gated by smoothness
  -- (horrible/impassable->0) and mtb:scale (>=2 LOW, >=3 forbidden), and a soft surface still caps the
  -- speed (a grade4 track tagged surface=sand/woodchips keeps MEDIUM_SPEED via the surface min).
  tracktype_speeds = {
    grade1 = GRAVEL_SPEED1,
    grade2 = GRAVEL_SPEED1,
    grade3 = GRAVEL_SPEED1,
    grade4 = GRAVEL_SPEED2,
    grade5 = MEDIUM_SPEED
  },

  -- Smoothness: gravel bikes ride comfortably up to "bad" (rough but rideable doubletrack/gravel — a
  -- gravel bike's home turf, so it rides at GRAVEL_SPEED, not a crawl; penalising it to LOW_SPEED made
  -- ridden gravel tracks like OSM way 711541590 a 3 km/h chokepoint and pushed routes onto parallel
  -- asphalt). "very_bad" and below are genuinely rough terrain and are held down to the ROUGH_SPEED rungs.
  --
  -- The four ROUGH values (very_bad and worse) are applied by bike_common as a CAP (math.min) on the final
  -- way speed; the smoother entries stay informational, read only by the legacy `== 0` branch. Before that,
  -- only the `== 0` case was ever consulted, so on gravel — where no entry is 0 — the whole table was dead:
  -- a grade4 grass track tagged smoothness=very_bad rode the full GRAVEL_SPEED2 40, indistinguishable from
  -- clean gravel (OSM ways 296107005 / 435708230 / 34229737). The old very_bad=3 / horrible=0.5 /
  -- impassable=0.5 values were written for a table that never fired; applying them literally would have
  -- banned such ways outright, hence the retune to "usable but clearly worse" — see IMPASSABLE_SPEED for the
  -- bottom rung, where a ban-level value cost a Leipzig gravel corridor a 4.5 m connector. Capping the smooth
  -- end is deliberately NOT done: it would make an explicitly-tagged way slower than an identical untagged one.
  --
  -- Resulting ladder: impassable 2 < very_horrible 3 < horrible 5 < asphalt 10 = very_bad 10
  --                   < paved track 15 < unpaved footway 20 < grade4/dirt 40 < compacted/grade1-3 50.
  -- So a very_bad way is held to the asphalt/connector rung, NOT to a gravel rung: it keeps its place in
  -- the graph but stops competing with real gravel. This is why a grade4 track that also carries
  -- smoothness=very_bad no longer rides at gravel speed — see the GRADE4_CASES note in
  -- OsrmRoutingGermanyGravelTest, which deliberately samples only grade4 ways WITHOUT a rough tag.
  smoothness_speeds = {
    excellent       = GRAVEL_SPEED1,
    good            = GRAVEL_SPEED1,
    very_good       = GRAVEL_SPEED1,
    intermediate    = GRAVEL_SPEED1,
    bad             = GRAVEL_SPEED2,
    very_bad        = ROUGH_SPEED,
    horrible        = HORRIBLE_SPEED,
    very_horrible   = LOW_SPEED,
    impassable      = IMPASSABLE_SPEED
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
