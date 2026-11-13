-- Foot profile for RouteCycle walking / running routes (graph ~/data/osrm_walk).
--
-- Upstream osrm-backend profiles/foot.lua with these changes (marked RouteCycle below):
--   * highway=cycleway is walkable, unless foot=no: slower, except with foot=designated;
--   * highway=steps are walkable but slow;
--   * primary bridges and tunnels without a sidewalk are not walkable (a trunk is unroutable without
--     explicit foot access anyway, as upstream);
--   * a traffic signal ADDS its penalty to the turn instead of overwriting it.
-- Preferences (heatmap, parks, water, big roads) are not here: they come from the per-segment
-- traffic_final_walk.csv (TrafficDumpCsvTask / WalkCsvRates) applied by osrm-customize.

api_version = 2

Set = require('lib/set')
Sequence = require('lib/sequence')
Handlers = require("lib/way_handlers")
find_access_tag = require("lib/access").find_access_tag

function setup()
  local walking_speed = 5
  return {
    properties = {
      weight_name                   = 'duration',
      max_speed_for_map_matching    = 40/3.6, -- kmph -> m/s
      call_tagless_node_function    = false,
      traffic_signal_penalty        = 2,
      u_turn_penalty                = 2,
      continue_straight_at_waypoint = false,
      use_turn_restrictions         = false,
      -- preserve short road crossings for pedestrian safety analysis
      max_collapse_distance         = 10,
    },

    default_mode            = mode.walking,
    default_speed           = walking_speed,
    oneway_handling         = 'specific',     -- respect 'oneway:foot' but not 'oneway'

    barrier_blacklist = Set {
      'yes',
      'wall',
      'fence'
    },

    access_tag_whitelist = Set {
      'yes',
      'foot',
      'permissive',
      'designated'
    },

    access_tag_blacklist = Set {
      'no',
      'agricultural',
      'forestry',
      'private',
      'delivery',
      -- When a way is tagged with `foot=use_sidepath` a parallel way suitable
      -- for pedestrians is mapped and must be used instead (by law in some
      -- countries). For purposes of routing pedestrians, this value should be
      -- treated as 'no access for pedestrians'.
      'use_sidepath',
    },

    restricted_access_tag_list = Set { },

    restricted_highway_whitelist = Set { },

    construction_whitelist = Set {},

    access_tags_hierarchy = Sequence {
      'foot',
      'access'
    },

    -- tags disallow access to in combination with highway=service
    service_access_tag_blacklist = Set { },

    restrictions = Sequence {
      'foot'
    },

    -- list of suffixes to suppress in name change instructions
    suffix_list = Set {
      'N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW', 'North', 'South', 'West', 'East'
    },

    avoid = Set {
      'impassable',
      'proposed',
      'motorroad'
    },

    speeds = Sequence {
      highway = {
        primary         = walking_speed,
        primary_link    = walking_speed,
        secondary       = walking_speed,
        secondary_link  = walking_speed,
        tertiary        = walking_speed,
        tertiary_link   = walking_speed,
        unclassified    = walking_speed,
        residential     = walking_speed,
        living_street   = walking_speed,
        service         = walking_speed,
        track           = walking_speed,
        path            = walking_speed,
        -- RouteCycle: steps are allowed but slow
        steps           = walking_speed*0.5,
        pedestrian      = walking_speed,
        platform        = walking_speed,
        footway         = walking_speed,
        pier            = walking_speed,
        -- RouteCycle: cycleways are walkable when foot isn't forbidden (foot=no still blocks them through the
        -- access blacklist); a bit slower, so a parallel footway wins
        cycleway        = walking_speed*0.8,
      },

      railway = {
        platform        = walking_speed
      },

      amenity = {
        parking         = walking_speed,
        parking_entrance= walking_speed
      },

      man_made = {
        pier            = walking_speed
      }
    },

    route_speeds = {
      ferry = 5
    },

    bridge_speeds = {
    },

    surface_speeds = {
      fine_gravel =   walking_speed*0.75,
      gravel =        walking_speed*0.75,
      pebblestone =   walking_speed*0.75,
      mud =           walking_speed*0.5,
      sand =          walking_speed*0.5
    },

    tracktype_speeds = {
    },

    smoothness_speeds = {
    }
  }
end

function process_node(profile, node, result)
  -- parse access and barrier tags
  local access = find_access_tag(node, profile.access_tags_hierarchy)
  if access then
    if profile.access_tag_blacklist[access] then
      result.barrier = true
    end
  else
    local barrier = node:get_value_by_key("barrier")
    if barrier then
      --  make an exception for rising bollard barriers
      local bollard = node:get_value_by_key("bollard")
      local rising_bollard = bollard and "rising" == bollard

      -- make an exception for fence with sensory=audible/audio (virtual livestock fences)
      local sensory = node:get_value_by_key("sensory")
      local audible_fence = barrier == "fence" and sensory and (sensory == "audible" or sensory == "audio")

      if profile.barrier_blacklist[barrier] and not rising_bollard and not audible_fence then
        result.barrier = true
      end
    end
  end

  -- check if node is a traffic light
  local tag = node:get_value_by_key("highway")
  if "traffic_signals" == tag then
    -- Direction should only apply to vehicles
    result.traffic_lights = true
  end
end

-- Block ways where the sidewalk is mapped as a separate parallel way.
-- Tags like `sidewalk=separate`, `sidewalk:both=separate`, or
-- `sidewalk:left/right=separate` indicate that the pedestrian path is
-- already captured by a distinct OSM way, so routing along this
-- carriageway would duplicate it. Explicit `foot=yes/permissive/designated`
-- can still override this inference.
local function handle_sidewalk_separate(profile, way, result, data)
  local sidewalk = way:get_value_by_key('sidewalk')
  local sidewalk_both = way:get_value_by_key('sidewalk:both')
  local sidewalk_left = way:get_value_by_key('sidewalk:left')
  local sidewalk_right = way:get_value_by_key('sidewalk:right')

  if sidewalk ~= 'separate' and sidewalk_both ~= 'separate'
      and sidewalk_left ~= 'separate' and sidewalk_right ~= 'separate' then
    return
  end

  -- An explicit non-blacklisted foot access tag (e.g. foot=yes/permissive/destination)
  -- overrides the sidewalk inference for each direction independently.
  if not (data.forward_access and not profile.access_tag_blacklist[data.forward_access]) then
    result.forward_mode = mode.inaccessible
  end
  if not (data.backward_access and not profile.access_tag_blacklist[data.backward_access]) then
    result.backward_mode = mode.inaccessible
  end

  if result.forward_mode == mode.inaccessible and result.backward_mode == mode.inaccessible then
    return false
  end
end

-- RouteCycle: a cycleway designated for walkers (foot=designated) is a real foot path, so it keeps the full speed.
-- foot=yes / permissive only allow walking: it stays at the slower cycleway speed, so a parallel sidewalk wins.
-- (Limassol Coastal Road Cycling Lane, way 27452366, foot=yes: at full speed it tied with sidewalk 300837624
-- beside it and walks went down the cycle lane.)
local function handle_cycleway_with_foot_access(profile, way, result, data)
  if data.highway ~= 'cycleway' then
    return
  end
  if data.forward_access == 'designated' then
    result.forward_speed = profile.default_speed
  end
  if data.backward_access == 'designated' then
    result.backward_speed = profile.default_speed
  end
end

-- RouteCycle: a trunk/primary bridge or tunnel without a sidewalk is no place to walk (no verge to step onto).
-- An explicit foot=yes/permissive/designated keeps it walkable.
local big_road_highways = Set { 'trunk', 'trunk_link', 'primary', 'primary_link' }
local sidewalk_present = Set { 'yes', 'both', 'left', 'right' }

local function has_sidewalk(way)
  return sidewalk_present[way:get_value_by_key('sidewalk')]
      or sidewalk_present[way:get_value_by_key('sidewalk:both')]
      or sidewalk_present[way:get_value_by_key('sidewalk:left')]
      or sidewalk_present[way:get_value_by_key('sidewalk:right')]
end

local function handle_big_road_bridge_tunnel(profile, way, result, data)
  if not big_road_highways[data.highway] then
    return
  end
  local bridge = way:get_value_by_key('bridge')
  local tunnel = way:get_value_by_key('tunnel')
  local is_bridge = bridge and bridge ~= 'no'
  local is_tunnel = tunnel and tunnel ~= 'no'
  if not (is_bridge or is_tunnel) or has_sidewalk(way) then
    return
  end
  if profile.access_tag_whitelist[data.forward_access] or profile.access_tag_whitelist[data.backward_access] then
    return
  end
  return false
end

-- main entry point for processsing a way
function process_way(profile, way, result)
  -- the intial filtering of ways based on presence of tags
  -- affects processing times significantly, because all ways
  -- have to be checked.
  -- to increase performance, prefetching and intial tag check
  -- is done in directly instead of via a handler.

  -- in general we should  try to abort as soon as
  -- possible if the way is not routable, to avoid doing
  -- unnecessary work. this implies we should check things that
  -- commonly forbids access early, and handle edge cases later.

  -- data table for storing intermediate values during processing
  local data = {
    -- prefetch tags
    highway = way:get_value_by_key('highway'),
    bridge = way:get_value_by_key('bridge'),
    route = way:get_value_by_key('route'),
    man_made = way:get_value_by_key('man_made'),
    railway = way:get_value_by_key('railway'),
    platform = way:get_value_by_key('platform'),
    amenity = way:get_value_by_key('amenity'),
    public_transport = way:get_value_by_key('public_transport')
  }

  -- perform an quick initial check and abort if the way is
  -- obviously not routable. here we require at least one
  -- of the prefetched tags to be present, ie. the data table
  -- cannot be empty
  if next(data) == nil then     -- is the data table empty?
    return
  end

  local handlers = Sequence {
    -- set the default mode for this profile. if can be changed later
    -- in case it turns we're e.g. on a ferry
    WayHandlers.default_mode,

    -- check various tags that could indicate that the way is not
    -- routable. this includes things like status=impassable,
    -- toll=yes and oneway=reversible
    WayHandlers.blocked_ways,

    -- determine access status by checking our hierarchy of
    -- access tags, e.g: motorcar, motor_vehicle, vehicle
    WayHandlers.access,

    -- block ways whose sidewalk is separately mapped (sidewalk:*=separate),
    -- unless foot access is explicitly whitelisted
    handle_sidewalk_separate,

    -- RouteCycle: no trunk/primary bridges or tunnels without a sidewalk
    handle_big_road_bridge_tunnel,

    -- check whether forward/backward directons are routable
    WayHandlers.oneway,

    -- check whether forward/backward directons are routable
    WayHandlers.destinations,

    -- check whether we're using a special transport mode
    WayHandlers.ferries,
    WayHandlers.movables,

    -- compute speed taking into account way type, maxspeed tags, etc.
    WayHandlers.speed,

    -- RouteCycle: cycleways with foot=designated keep the full speed
    handle_cycleway_with_foot_access,
    WayHandlers.surface,

    -- handle conveying tag on escalators and moving walkways
    WayHandlers.conveying,

    -- handle turn lanes and road classification, used for guidance
    WayHandlers.classification,

    -- handle various other flags
    WayHandlers.roundabouts,
    WayHandlers.startpoint,

    -- set name, ref and pronunciation
    WayHandlers.names,

    -- set weight properties of the way
    WayHandlers.weights
  }

  WayHandlers.run(profile, way, result, data, handlers)
end

function process_turn (profile, turn)
  turn.duration = 0.

  if turn.direction_modifier == direction_modifier.u_turn then
     turn.duration = turn.duration + profile.properties.u_turn_penalty
  end

  if turn.has_traffic_light then
     -- RouteCycle: add the signal penalty; upstream overwrote the turn duration with it, dropping the u-turn
     -- penalty above
     turn.duration = turn.duration + profile.properties.traffic_signal_penalty
  end
  if profile.properties.weight_name == 'routability' then
      -- penalize turns from non-local access only segments onto local access only tags
      if not turn.source_restricted and turn.target_restricted then
          turn.weight = turn.weight + 3000
      end
  end
end

return {
  setup = setup,
  process_way =  process_way,
  process_node = process_node,
  process_turn = process_turn
}
