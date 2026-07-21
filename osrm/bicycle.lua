-- Bicycle profile (road bike).
--
-- Thin shim: all logic lives in lib/bike_common.lua. This file only supplies the
-- road-profile config and delegates to BikeCommon.make_profile(cfg). A separate
-- gravel.lua shim reuses the same module with different cfg values.
--
-- Every value below is copied VERBATIM from the original road-only bicycle.lua.

api_version = 4

local BikeCommon = require('lib/bike_common')

local default_speed = 25
local LOW_SPEED = 3
local VERY_LOW_SPEED = 0.5

local cfg = {
  profile = "road",

  default_speed = default_speed,
  low_speed = LOW_SPEED,
  very_low_speed = VERY_LOW_SPEED,

  -- Allowed-surface gate (verbatim body of the original is_road_surface).
  is_allowed_surface = function(surface)
    if not surface then
      return false
    end

    local allowed_surfaces = {
      "asphalt",
      "paved",
      "concrete",
      "concrete:plates",
      "concrete:lanes",
      "chipseal",
      "tarmac",
      "sealed",
      "paving_stones",
      "paving_stones:lanes",
      "cobblestone:flattened",
      "metal",
      "wood"
    }

    for _, allowed_surface in ipairs(allowed_surfaces) do
      if surface == allowed_surface then
        return true
      end
    end

    return false
  end,

  bicycle_speeds = {
    motorway = 0,
    cycleway = default_speed * 1.2, --2mil
    primary = default_speed, --3.8mil
    trunk = default_speed, --1.8mil TODO: make it low - test in SPB and other areas. check roads in overpass
    trunk_link = default_speed / 3,
    primary_link = default_speed / 3, --469k
    secondary = default_speed, --5.4mil
    secondary_link = default_speed, --366k
    tertiary = default_speed, --8.5mil
    tertiary_link = default_speed, --267k
    residential = default_speed, --68mil
    living_street = default_speed, --2.2 mil
    road = default_speed, --43k
    unclassified = default_speed, --18mil
    service = LOW_SPEED,         --60 mil TODO: try with good surface
    track = VERY_LOW_SPEED,   --28 mil
    path = LOW_SPEED,            --15mil TODO: make LOW_SPEED
    footway = LOW_SPEED          --27 mil (pedestrian footBRIDGES are penalized separately in speed_handler)
  },

  surface_speeds = {
    asphalt = default_speed,
    chipseal = default_speed,
    concrete = default_speed,
    paved = default_speed,
    concrete = default_speed,
    ["concrete:plates"] = default_speed,
    ["concrete:lanes"] = default_speed,
    tarmac = default_speed,
    sealed = default_speed,
    wood = LOW_SPEED,
    metal = LOW_SPEED,
    ["cobblestone:flattened"] = LOW_SPEED,
    paving_stones = 10,
    ["paving_stones:lanes"] = LOW_SPEED,
    compacted = LOW_SPEED,
    cobblestone = LOW_SPEED,
    unpaved = 0,
    laterite = 0,
    fine_gravel = LOW_SPEED,
    gravel = LOW_SPEED,
    pebblestone = LOW_SPEED,
    grass_paver = 0,
    ground = LOW_SPEED,
    dirt = 0,
    earth = 0,
    grass = 0,
    mud = 0,
    sand = 0,
    shells = 0,
    woodchips = 0,
    sett = LOW_SPEED
  },

  tracktype_speeds = {
    grade1 = default_speed / 2,   -- unsurfaced grade1 track: half speed (was default_speed)
    grade2 = 0,   -- Speed 0 for grade2 (avoid)
    grade3 = 0,   -- Speed 0 for grade3 (avoid)
    grade4 = 0,   -- Speed 0 for grade4 (avoid)
    grade5 = 0    -- Speed 0 for grade5 (avoid)
  },

  smoothness_speeds = {
    excellent = default_speed,
    good = default_speed,
    very_good = default_speed,
    intermediate = default_speed,
    bad = LOW_SPEED,
    -- https://www.openstreetmap.org/way/25809230 - can't ride here
    very_bad = LOW_SPEED,
    horrible = 0,
    very_horrible = 0,
    impassable = 0
  },

  avoid = Set {
    'impassable',
    'construction',
    'proposed',
--       'path',
--       'track',
--       'footway',
--       'bridleway'
  },
}

return BikeCommon.make_profile(cfg)
