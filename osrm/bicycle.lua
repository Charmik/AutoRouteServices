-- Bicycle profile

api_version = 4

Set = require('lib/set')
Sequence = require('lib/sequence')
Handlers = require("lib/way_handlers")
Relations = require("lib/relations")
TrafficSignal = require("lib/traffic_signal")
find_access_tag = require("lib/access").find_access_tag
limit = require("lib/maxspeed").limit
Measure = require("lib/measure")

function is_road_surface(surface)
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
end

function isRoadBicycleAllowed(highway_tag, bicycle_tag, bicycle_road_tag, cyclestreet_tag, cycleway_tag, cycleway_left_tag, cycleway_right_tag)
  local allowed_bicycle_tags = {
    "yes",
    "designated",
    "lane",
    "track",
    "shared_lane",
    "share_busway",
    "shoulder",
    "separate",
    "opposite"
  }

  local allowed_cycleway_tags = {
    "lane",
    "track",
    "shared_lane",
    "share_busway",
    "shoulder",
    "separate",
    "opposite",
    "opposite_lane",
    "opposite_track"
  }

  if ("cycleway" == highway_tag) then
    return true
  end

  if bicycle_tag then
    for _, tag in ipairs(allowed_bicycle_tags) do
      if bicycle_tag == tag then
        return true
      end
    end
  end

  if bicycle_road_tag == "yes" then
    return true
  end

  if cyclestreet_tag == "yes" then
    return true
  end

  if cycleway_tag then
    for _, tag in ipairs(allowed_cycleway_tags) do
      if cycleway_tag == tag then
        return true
      end
    end
  end

  if cycleway_left_tag then
    for _, tag in ipairs(allowed_cycleway_tags) do
      if cycleway_left_tag == tag then
        return true
      end
    end
  end

  if cycleway_right_tag then
    for _, tag in ipairs(allowed_cycleway_tags) do
      if cycleway_right_tag == tag then
        return true
      end
    end
  end

  return false
end

function setup()
  local default_speed = 25
  local walking_speed = 1

  mode = {
      inaccessible = 0,
      cycling = 1,
      pushing_bike = 2,
      ferry = 3,
      train = 4,
      highway_cycling = 5,
    }

  return {
    properties = {
      u_turn_penalty                = 20,
      traffic_light_penalty         = 10,
      --weight_name                   = 'cyclability',
      weight_name                   = 'duration',
      process_call_tagless_node     = false,
      max_speed_for_map_matching    = 110/3.6, -- kmph -> m/s
      use_turn_restrictions         = false,
      continue_straight_at_waypoint = false,
      mode_change_penalty           = 30,
      use_relations                 = true,
    },

    default_mode              = mode.cycling,
    default_speed             = default_speed,
    walking_speed             = walking_speed,
    oneway_handling           = true,
    turn_penalty              = 12,
    turn_bias                 = 2.0,
    use_public_transport      = false,

    -- Exclude narrow ways, in particular to route with cargo bike
    width                     = nil, -- Cargo bike could 0.5 width, in meters
    exclude_cargo_bike        = false,

    allowed_start_modes = Set {
      mode.cycling,
      mode.pushing_bike,
      mode.highway_cycling
    },

    barrier_blacklist = Set {
      'yes',
      'wall',
      'fence'
    },

    access_tag_whitelist = Set {
      'yes',
      'permissive',
      'designated'
    },

    access_tag_blacklist = Set {
      'no',
      'private',
      'agricultural',
      'forestry',
      'delivery',
      -- When a way is tagged with `use_sidepath` a parallel way suitable for
      -- cyclists is mapped and must be used instead (by law). This tag is
      -- used on ways that normally may be used by cyclists, but not when
      -- a signposted parallel cycleway is available. For purposes of routing
      -- cyclists, this value should be treated as 'no access for bicycles'.
      'use_sidepath',
      'hiking',
      'trail',
      'foot',
      'pedestrian'
    },

    restricted_access_tag_list = Set { },

    restricted_highway_whitelist = Set { },

    -- tags disallow access to in combination with highway=service
    service_access_tag_blacklist = Set { },

    construction_whitelist = Set {
      'no',
      'widening',
      'minor',
    },

    access_tags_hierarchy = Sequence {
      'bicycle',
      'vehicle',
      'access'
    },

    restrictions = Set {
      'bicycle'
    },

    cycleway_tags = Set {
--       'track',
      'lane',
      'share_busway',
      'sharrow',
      'shared',
      'shared_lane'
    },

    opposite_cycleway_tags = Set {
      'opposite',
      'opposite_lane',
      'opposite_track',
    },

    cycleway_relation_types = Set {
      'route',
      'network'
    },

    cycleway_route_types = Set {
      'bicycle',
      'bike'
    },

    cycleway_network_types = Set {
      'lcn',  -- local cycling network
      'rcn',  -- regional cycling network
      'ncn',  -- national cycling network
      'icn'   -- international cycling network
    },

    relation_types = Sequence {
      "route",        -- Individual cycling routes
      "route_master", -- Groups of related cycling routes
      "network"       -- Bicycle networks
    },

    -- reduce the driving speed by 30% for unsafe roads
    -- only used for cyclability metric
    unsafe_highway_list = {
      primary = 0.5,
      trunk = 0.5,
      secondary = 0.65,
      tertiary = 0.8,
      primary_link = 0.5,
      secondary_link = 0.65,
      tertiary_link = 0.8,
    },

    service_penalties = {
      alley             = 0.5,
    },

    bicycle_speeds = {
      cycleway = default_speed * 1.2, --2mil
      primary = default_speed, --3.8mil
      trunk = default_speed, --1.8mil TODO: make it low - test in SPB and other areas. check roads in overpass
      trunk_link = default_speed,
      primary_link = 1, --469k
      secondary = default_speed, --5.4mil
      secondary_link = default_speed, --366k
      tertiary = default_speed, --8.5mil
      tertiary_link = default_speed, --267k
      residential = default_speed, --68mil
      living_street = default_speed, --2.2 mil
      road = default_speed, --43k
      unclassified = 0.01, --18mil TODO: remove with bad surface?
      service = 1,         --60 mil TODO: try with good surface
      track = 0.01,        --28 mil
      path = 0,            --15mil
      footway = 0          --27 mil
    },

    pedestrian_speeds = {
      footway = walking_speed,
      pedestrian = walking_speed,
      steps = 1
    },

    railway_speeds = {
      train = 0,
      railway = 0,
      subway = 0,
      light_rail = 0,
      monorail = 0,
      tram = 0
    },

    platform_speeds = {
      platform = 0;
    },

    amenity_speeds = {
      parking = 10,
      parking_entrance = 10
    },

    man_made_speeds = {
      pier = walking_speed
    },

    route_speeds = {
      ferry = 0
    },

    bridge_speeds = {
      movable = 5
    },

    surface_speeds = {
      asphalt = default_speed,
      chipseal = default_speed,
      concrete = default_speed,
      concrete_lanes = default_speed,
      wood = 10,
      metal = 10,
      ["cobblestone:flattened"] = 10,
      paving_stones = 10,
      compacted = 0,
      cobblestone = 6,
      unpaved = 0,
      fine_gravel = 0,
      gravel = 0,
      pebblestone = 0,
      grass_paver = 0,
      ground = 0,
      dirt = 0,
      earth = 0,
      grass = 0,
      mud = 0,
      sand = 0,
      woodchips = 0,
      sett = 6
    },

    classes = Sequence {
        'ferry', 'tunnel'
    },

    -- Which classes should be excludable
    -- This increases memory usage so its disabled by default.
    excludable = Sequence {
--        Set {'ferry'}
    },

    tracktype_speeds = {
--       grade1 = default_speed,  -- Default speed for grade1
      grade1 = 0.01,
      grade2 = 0,   -- Speed 0 for grade2 (avoid)
      grade3 = 0,   -- Speed 0 for grade3 (avoid)
      grade4 = 0,   -- Speed 0 for grade4 (avoid)
      grade5 = 0    -- Speed 0 for grade5 (avoid)
    },

    smoothness_speeds = {
      excellent = default_speed,
      good = default_speed,
      intermediate = default_speed,
      bad = 0,
      very_bad = 0,
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
    }
  }
end

function process_node(profile, node, result)
  -- parse access and barrier tags
  local highway = node:get_value_by_key("highway")
  local is_crossing = highway and highway == "crossing"

  local access = find_access_tag(node, profile.access_tags_hierarchy)
  if access and access ~= "" then
    -- access restrictions on crossing nodes are not relevant for
    -- the traffic on the road
    if profile.access_tag_blacklist[access] and not is_crossing then
      result.barrier = true
    end
  else
    local barrier = node:get_value_by_key("barrier")
    if barrier and "" ~= barrier then
      if profile.barrier_blacklist[barrier] then
        result.barrier = true
      end
    end
  end

  if profile.exclude_cargo_bike then
    local cargo_bike = node:get_value_by_key("cargo_bike")
    if cargo_bike and cargo_bike == "no" then
      result.barrier = true
    end
  end

  -- width
  if profile.width then
    -- From barrier=cycle_barrier or other barriers
    local maxwidth_physical = node:get_value_by_key("maxwidth:physical")
    local maxwidth_physical_meter = maxwidth_physical and Measure.parse_value_meters(maxwidth_physical) or 99
    local opening = node:get_value_by_key("opening")
    local opening_meter = opening and Measure.parse_value_meters(opening) or 99
    local width_meter = math.min(maxwidth_physical_meter, opening_meter)

    if width_meter and width_meter < profile.width then
      result.barrier = true
    end
  end

  -- check if node is a traffic light
  result.traffic_lights = TrafficSignal.get_value(node)
end

local function parse_maxspeed(way)
    local max_speed = way:get_value_by_key ("maxspeed")
    local max_speed_type = way:get_value_by_key ("maxspeed:type")

    if (max_speed and string.match(max_speed, "^%w%w:urban$")) then
        return 50
    elseif (max_speed_type and string.match(max_speed_type, "^%w%w:urban$")) then
        return 50
    elseif (max_speed and string.match(max_speed, "^%w%w:rural$")) then
        return 101
    elseif (max_speed_type and string.match(max_speed_type, "^%w%w:rural$")) then
        return 101
    else
        return Measure.get_max_speed(max_speed) or 0
    end
end

function handle_bicycle_tags(profile,way,result,data)
    -- initial routability check, filters out buildings, boundaries, etc
  data.route = way:get_value_by_key("route")
  data.man_made = way:get_value_by_key("man_made")
  data.railway = way:get_value_by_key("railway")
  data.amenity = way:get_value_by_key("amenity")
  data.public_transport = way:get_value_by_key("public_transport")
  data.bridge = way:get_value_by_key("bridge")

  if (not data.highway or data.highway == '') and
  (not data.route or data.route == '') and
  (not profile.use_public_transport or not data.railway or data.railway=='') and
  (not data.amenity or data.amenity=='') and
  (not data.man_made or data.man_made=='') and
  (not data.public_transport or data.public_transport=='') and
  (not data.bridge or data.bridge=='')
  then
    return false
  end

  -- access
  data.access = find_access_tag(way, profile.access_tags_hierarchy)
  if data.access and profile.access_tag_blacklist[data.access] then
    return false
  end

  -- other tags
  data.junction = way:get_value_by_key("junction")
  data.maxspeed = parse_maxspeed(way)
  data.maxspeed_forward = Measure.get_max_speed(way:get_value_by_key("maxspeed:forward")) or 0
  data.maxspeed_backward = Measure.get_max_speed(way:get_value_by_key("maxspeed:backward")) or 0
  data.barrier = way:get_value_by_key("barrier")
  data.oneway = way:get_value_by_key("oneway")
  data.oneway_bicycle = way:get_value_by_key("oneway:bicycle")
  data.cycleway = way:get_value_by_key("cycleway")
  data.cycleway_left = way:get_value_by_key("cycleway:left")
  data.cycleway_right = way:get_value_by_key("cycleway:right")
  data.cycleway_surface = way:get_value_by_key("cycleway:surface")
  data.duration = way:get_value_by_key("duration")
  data.service = way:get_value_by_key("service")
  data.tracktype = way:get_value_by_key("tracktype")
  data.foot = way:get_value_by_key("foot")
  data.foot_forward = way:get_value_by_key("foot:forward")
  data.foot_backward = way:get_value_by_key("foot:backward")
  data.bicycle = way:get_value_by_key("bicycle")
  data.bicycle_road = way:get_value_by_key("bicycle_road")
  data.cyclestreet = way:get_value_by_key("cyclestreet")
  data.lanes = way:get_value_by_key("lanes")

  --cycleway_handler(profile,way,result,data)
  speed_handler(profile,way,result,data)

  oneway_handler(profile,way,result,data)

  bike_push_handler(profile,way,result,data)

  -- width should be after bike_push
  --width_handler(profile,way,result,data)

  -- maxspeed
  limit( result, data.maxspeed, data.maxspeed_forward, data.maxspeed_backward )

  -- not routable if no speed assigned
  -- this avoid assertions in debug builds
  if result.forward_speed <= 0 and result.duration <= 0 then
    result.forward_mode = mode.inaccessible
  end
  if result.backward_speed <= 0 and result.duration <= 0 then
    result.backward_mode = mode.inaccessible
  end

  safety_handler(profile,way,result,data)
end



function speed_handler(profile,way,result,data)

  data.way_type_allows_pushing = false
  --DEBUG: if way:id() == 442985813 then
  -- speed
  local bridge_speed = profile.bridge_speeds[data.bridge]
  local tracktype = data.tracktype
  local lanes = data.lanes and tonumber(data.lanes) or 0

  if ((data.highway == "primary" or data.highway == "trunk") and (data.oneway == "yes" and lanes >= 2 and (data.maxspeed > 80))) then
    result.forward_speed = 1  -- Slower than default but not unusable
    result.backward_speed = 1
    result.forward_rate = 0.0001
    result.backward_rate = 0.0001
    result.forward_mode = mode.highway_cycling
    result.backward_mode = mode.highway_cycling
  elseif isRoadBicycleAllowed(data.highway, data.bicycle, data.bicycle_road, data.cyclestreet, data.cycleway, data.cycleway_left, data.cycleway_right) and (is_road_surface(data.surface) or is_road_surface(data.cycleway_surface)) then
    local cycleWayMultiplicator = 2
    if (data.highway == "cycleway" or data.bicycle == "designated") then --https://www.openstreetmap.org/way/1052708536
      result.forward_speed = profile.default_speed * cycleWayMultiplicator
      result.backward_speed = profile.default_speed * cycleWayMultiplicator
    elseif (data.bicycle_road == "yes" or data.cyclestreet == "yes") and ((data.cycleway_left == "track" and is_road_surface(data.cycleway_surface)) or (data.cycleway_right == "track" and is_road_surface(data.cycleway_surface))) then --https://www.openstreetmap.org/way/11550988
      result.forward_speed = profile.default_speed * cycleWayMultiplicator
      result.backward_speed = profile.default_speed * cycleWayMultiplicator
    else --https://www.openstreetmap.org/way/970634864
      result.forward_speed = profile.default_speed
      result.backward_speed = profile.default_speed
    end
  elseif (data.highway == "unclassified" and (((data.maxspeed >= 40 and data.maxspeed < 100) and not data.surface) or is_road_surface(data.surface))) then
    result.forward_speed = profile.default_speed
    result.backward_speed = profile.default_speed
  elseif ((data.highway == "service" or data.highway == "tertiary") and (is_road_surface(data.surface))) then
    result.forward_speed = profile.default_speed
    result.backward_speed = profile.default_speed
  elseif ((data.highway == "footway") and (is_road_surface(data.surface))) then
    result.forward_speed = 5
    result.backward_speed = 5
  elseif (bridge_speed and bridge_speed > 0) then
    data.highway = data.bridge
    if data.duration and durationIsValid(data.duration) then
      result.duration = math.max( parseDuration(data.duration), 1 )
    end
    result.forward_speed = bridge_speed
    result.backward_speed = bridge_speed
    data.way_type_allows_pushing = true
  elseif tracktype and profile.tracktype_speeds[tracktype] then
    result.forward_speed = profile.tracktype_speeds[tracktype]
    result.backward_speed = profile.tracktype_speeds[tracktype]
    data.way_type_allows_pushing = true
  elseif profile.route_speeds[data.route] then
    -- ferries (doesn't cover routes tagged using relations)
    result.forward_mode = mode.ferry
    result.backward_mode = mode.ferry
    -- Never use ferries for bicycle routing
    result.forward_speed = 0
    result.backward_speed = 0
  -- railway platforms (old tagging scheme)
  elseif data.railway and profile.platform_speeds[data.railway] then
    result.forward_speed = profile.platform_speeds[data.railway]
    result.backward_speed = profile.platform_speeds[data.railway]
    data.way_type_allows_pushing = true
  -- public_transport platforms (new tagging platform)
  elseif data.public_transport and profile.platform_speeds[data.public_transport] then
    result.forward_speed = profile.platform_speeds[data.public_transport]
    result.backward_speed = profile.platform_speeds[data.public_transport]
    data.way_type_allows_pushing = true
  -- railways
  elseif profile.use_public_transport and data.railway and profile.railway_speeds[data.railway] and profile.access_tag_whitelist[data.access] then
    result.forward_mode = mode.train
    result.backward_mode = mode.train
    result.forward_speed = profile.railway_speeds[data.railway]
    result.backward_speed = profile.railway_speeds[data.railway]
  elseif data.amenity and profile.amenity_speeds[data.amenity] then
    -- parking areas
    result.forward_speed = profile.amenity_speeds[data.amenity]
    result.backward_speed = profile.amenity_speeds[data.amenity]
    data.way_type_allows_pushing = true
  elseif data.highway == "footway" and data.bicycle == "permissive" then --https://www.openstreetmap.org/way/249681202
    result.forward_speed = 5
    result.backward_speed = 5
    data.way_type_allows_pushing = true
  elseif profile.bicycle_speeds[data.highway] then
    local speed = profile.bicycle_speeds[data.highway]
    if speed == profile.default_speed and not data.surface then
      speed = speed / 3
    end
    if (data.surface and profile.surface_speeds[data.surface] and profile.surface_speeds[data.surface] < speed) then
      speed = profile.surface_speeds[data.surface]
    end
    result.forward_speed = speed
    result.backward_speed = speed
    data.way_type_allows_pushing = true
  elseif data.access and profile.access_tag_whitelist[data.access]  then
    -- unknown way, but valid access tag
    local speed = profile.default_speed
    if not data.surface then
      speed = speed / 3
    end
    result.forward_speed = speed
    result.backward_speed = speed
    data.way_type_allows_pushing = true
  end

  -- Apply smoothness blocking - set speed to 0 for bad smoothness roads
  if data.smoothness and profile.smoothness_speeds[data.smoothness] ~= nil then
    local smoothness_speed = profile.smoothness_speeds[data.smoothness]
    if smoothness_speed == 0 then
      result.forward_speed = 0
      result.backward_speed = 0
    end
  end
end

function oneway_handler(profile,way,result,data)
  -- oneway
  data.implied_oneway = data.junction == "roundabout" or data.junction == "circular" or data.highway == "motorway"
  data.reverse = false

  if data.oneway_bicycle == "yes" or data.oneway_bicycle == "1" or data.oneway_bicycle == "true" then
    result.backward_mode = mode.inaccessible
  elseif data.oneway_bicycle == "no" or data.oneway_bicycle == "0" or data.oneway_bicycle == "false" then
   -- prevent other cases
  elseif data.oneway_bicycle == "-1" then
    result.forward_mode = mode.inaccessible
    data.reverse = true
  elseif data.oneway == "yes" or data.oneway == "1" or data.oneway == "true" then
    result.backward_mode = mode.inaccessible
  elseif data.oneway == "no" or data.oneway == "0" or data.oneway == "false" then
    -- prevent other cases
  elseif data.oneway == "-1" then
    result.forward_mode = mode.inaccessible
    data.reverse = true
  elseif data.implied_oneway then
    result.backward_mode = mode.inaccessible
  end
end

function cycleway_handler(profile,way,result,data)
  -- cycleway
  data.has_cycleway_forward = false
  data.has_cycleway_backward = false
--data.is_twoway = result.forward_mode ~= mode.inaccessible and result.backward_mode ~= mode.inaccessible and not data.implied_oneway https://github.com/Project-OSRM/osrm-backend/issues/7138
  data.is_twoway = data.forward_mode ~= mode.inaccessible and data.backward_mode ~= mode.inaccessible and not data.implied_oneway

  -- cycleways on normal roads
  if data.is_twoway then
    if data.cycleway and profile.cycleway_tags[data.cycleway] then
      data.has_cycleway_backward = true
      data.has_cycleway_forward = true
    end
    if (data.cycleway_right and profile.cycleway_tags[data.cycleway_right]) or (data.cycleway_left and profile.opposite_cycleway_tags[data.cycleway_left]) then
      data.has_cycleway_forward = true
    end
    if (data.cycleway_left and profile.cycleway_tags[data.cycleway_left]) or (data.cycleway_right and profile.opposite_cycleway_tags[data.cycleway_right]) then
      data.has_cycleway_backward = true
    end
  else
    local has_twoway_cycleway = (data.cycleway and profile.opposite_cycleway_tags[data.cycleway]) or (data.cycleway_right and profile.opposite_cycleway_tags[data.cycleway_right]) or (data.cycleway_left and profile.opposite_cycleway_tags[data.cycleway_left])
    local has_opposite_cycleway = (data.cycleway_left and profile.opposite_cycleway_tags[data.cycleway_left]) or (data.cycleway_right and profile.opposite_cycleway_tags[data.cycleway_right])
    local has_oneway_cycleway = (data.cycleway and profile.cycleway_tags[data.cycleway]) or (data.cycleway_right and profile.cycleway_tags[data.cycleway_right]) or (data.cycleway_left and profile.cycleway_tags[data.cycleway_left])

    -- set cycleway even though it is an one-way if opposite is tagged
    if has_twoway_cycleway then
      data.has_cycleway_backward = true
      data.has_cycleway_forward = true
    elseif has_opposite_cycleway then
      if not data.reverse then
        data.has_cycleway_backward = true
      else
        data.has_cycleway_forward = true
      end
    elseif has_oneway_cycleway then
      if not data.reverse then
        data.has_cycleway_forward = true
      else
        data.has_cycleway_backward = true
      end

    end
  end

  if data.has_cycleway_backward then
    result.backward_mode = mode.cycling
    result.backward_speed = profile.bicycle_speeds["cycleway"]
  end

  if data.has_cycleway_forward then
    result.forward_mode = mode.cycling
    result.forward_speed = profile.bicycle_speeds["cycleway"]
  end
end

function width_handler(profile,way,result,data)
  if profile.exclude_cargo_bike then
    local cargo_bike = way:get_value_by_key("cargo_bike")
    if cargo_bike and cargo_bike == "no" then
      result.forward_mode = mode.inaccessible
      result.backward_mode = mode.inaccessible
    end
  end

  if profile.width then
    local width = way:get_value_by_key("width")
    if width then
      local width_meter = Measure.parse_value_meters(width)
      if width_meter and width_meter < profile.width then
        result.forward_mode = mode.inaccessible
        result.backward_mode = mode.inaccessible
      end
    end
  end
end

function bike_push_handler(profile,way,result,data)
  -- pushing bikes - if no other mode found
  if result.forward_mode == mode.inaccessible or result.backward_mode == mode.inaccessible or
    result.forward_speed == -1 or result.backward_speed == -1 then
    if data.foot ~= 'no' then
      local push_forward_speed = nil
      local push_backward_speed = nil

      if profile.pedestrian_speeds[data.highway] then
        push_forward_speed = profile.pedestrian_speeds[data.highway]
        push_backward_speed = profile.pedestrian_speeds[data.highway]
      elseif data.man_made and profile.man_made_speeds[data.man_made] then
        push_forward_speed = profile.man_made_speeds[data.man_made]
        push_backward_speed = profile.man_made_speeds[data.man_made]
      else
        if data.foot == 'yes' then
          push_forward_speed = profile.walking_speed
          if not data.implied_oneway then
            push_backward_speed = profile.walking_speed
          end
        elseif data.foot_forward == 'yes' then
          push_forward_speed = profile.walking_speed
        elseif data.foot_backward == 'yes' then
          push_backward_speed = profile.walking_speed
        elseif data.way_type_allows_pushing then
          push_forward_speed = profile.walking_speed
          if not data.implied_oneway then
            push_backward_speed = profile.walking_speed
          end
        end
      end

      if push_forward_speed and (result.forward_mode == mode.inaccessible or result.forward_speed == -1) then
        result.forward_mode = mode.pushing_bike
        result.forward_speed = push_forward_speed
      end
      if push_backward_speed and (result.backward_mode == mode.inaccessible or result.backward_speed == -1)then
        result.backward_mode = mode.pushing_bike
        result.backward_speed = push_backward_speed
      end

    end

  end

  -- dismount
  if data.bicycle == "dismount" then
    result.forward_mode = mode.pushing_bike
    result.backward_mode = mode.pushing_bike
    result.forward_speed = profile.walking_speed
    result.backward_speed = profile.walking_speed
  end
end

function safety_handler(profile,way,result,data)
  -- convert duration into cyclability
  if profile.properties.weight_name == 'cyclability' then
    local safety_penalty = profile.unsafe_highway_list[data.highway] or 1.
    local is_unsafe = safety_penalty < 1

    -- primaries that are one ways are probably huge primaries where the lanes need to be separated
    if is_unsafe and data.highway == 'primary' and not data.is_twoway then
      safety_penalty = safety_penalty * 0.5
    end
    if is_unsafe and data.highway == 'secondary' and not data.is_twoway then
      safety_penalty = safety_penalty * 0.6
    end

    local forward_is_unsafe = is_unsafe and not data.has_cycleway_forward
    local backward_is_unsafe = is_unsafe and not data.has_cycleway_backward
    local is_undesireable = data.highway == "service" and profile.service_penalties[data.service]
    local forward_penalty = 1.
    local backward_penalty = 1.
    if forward_is_unsafe then
      forward_penalty = math.min(forward_penalty, safety_penalty)
    end
    if backward_is_unsafe then
       backward_penalty = math.min(backward_penalty, safety_penalty)
    end

    if is_undesireable then
       forward_penalty = math.min(forward_penalty, profile.service_penalties[data.service])
       backward_penalty = math.min(backward_penalty, profile.service_penalties[data.service])
    end

    if result.forward_speed > 0 then
      -- convert from km/h to m/s
      result.forward_rate = result.forward_speed / 3.6 * forward_penalty
    end
    if result.backward_speed > 0 then
      -- convert from km/h to m/s
      result.backward_rate = result.backward_speed / 3.6 * backward_penalty
    end
    if result.duration > 0 then
      result.weight = result.duration / forward_penalty
    end
  end
end

function get_cycle_network_speed_boost(way, relations, profile)
  local boost = 1.0

  if not relations then
    return boost
  end


  local rel_id_list = relations:get_relations(way)

  for i, rel_id in ipairs(rel_id_list) do
    local rel = relations:relation(rel_id)
    local rel_id_num = rel:id()

    local rel_type = rel:get_value_by_key('type')
    local route_type = rel:get_value_by_key('route')
    local network = rel:get_value_by_key('network')

    local is_cycling_relation = false

    if rel_type == 'route' and profile.cycleway_route_types[route_type] then
      is_cycling_relation = true
    elseif rel_type == 'route_master' and profile.cycleway_route_types[route_type] then
      is_cycling_relation = true
    elseif rel_type == 'network' then
      local network_type = rel:get_value_by_key('network')
      if network_type and profile.cycleway_network_types[network_type] then
        is_cycling_relation = true
        network = network_type  -- Use network type for boost calculation
      end
    end

    if is_cycling_relation then
      if network and profile.cycleway_network_types[network] then
        -- Apply speed boost based on network hierarchy
        if network == 'lcn' then        -- Local cycling network
          boost = 2.1
        elseif network == 'rcn' then    -- Regional cycling network
          boost = 2.2
        elseif network == 'ncn' then    -- National cycling network
          boost = 2.3
        elseif network == 'icn' then    -- International cycling network
          boost = 2.4
        end
      else
        boost = 3
      end
    end
  end
  return boost
end



function process_way(profile, way, result, relations)
  -- the initial filtering of ways based on presence of tags
  -- affects processing times significantly, because all ways
  -- have to be checked.
  -- to increase performance, prefetching and initial tag check
  -- is done directly instead of via a handler.

  -- in general we should try to abort as soon as
  -- possible if the way is not routable, to avoid doing
  -- unnecessary work. this implies we should check things that
  -- commonly forbids access early, and handle edge cases later.

  -- data table for storing intermediate values during processing

  local data = {
    -- prefetch tags
    highway = way:get_value_by_key('highway'),
    surface = way:get_value_by_key('surface'),
    smoothness = way:get_value_by_key('smoothness'),

    route = nil,
    man_made = nil,
    railway = nil,
    amenity = nil,
    public_transport = nil,
    bridge = nil,

    access = nil,

    junction = nil,
    maxspeed = nil,
    maxspeed_forward = nil,
    maxspeed_backward = nil,
    barrier = nil,
    oneway = nil,
    oneway_bicycle = nil,
    cycleway = nil,
    cycleway_left = nil,
    cycleway_right = nil,
    duration = nil,
    service = nil,
    foot = nil,
    foot_forward = nil,
    foot_backward = nil,
    bicycle = nil,

    way_type_allows_pushing = false,
    has_cycleway_forward = false,
    has_cycleway_backward = false,
    is_twoway = true,
    reverse = false,
    implied_oneway = false
  }

  local handlers = Sequence {
    -- set the default mode for this profile. if can be changed later
    -- in case it turns we're e.g. on a ferry
    WayHandlers.default_mode,

    -- check various tags that could indicate that the way is not
    -- routable. this includes things like status=impassable,
    -- toll=yes and oneway=reversible
    WayHandlers.blocked_ways,

    -- compute speed taking into account way type, maxspeed tags, etc.
    WayHandlers.surface,

    -- our main handler
    handle_bicycle_tags,

    -- handle turn lanes and road classification, used for guidance
    WayHandlers.classification,

    -- handle allowed start/end modes
    WayHandlers.startpoint,

    -- handle roundabouts
    WayHandlers.roundabouts,

    -- set name, ref and pronunciation
    WayHandlers.names,

    -- set classes
    WayHandlers.classes,

    -- set weight properties of the way
    WayHandlers.weights,

    --Relations.process_way_refs(way, relations, result)
  }

  WayHandlers.run(profile, way, result, data, handlers)

  if relations and data.highway == "cycleway" then
    local speed_boost = get_cycle_network_speed_boost(way, relations, profile)
    if speed_boost > 1.0 then
      local forward_speed = profile.default_speed
      local backward_speed = profile.default_speed

      if (result.forward_speed < forward_speed) then
        forward_speed = result.forward_speed
      end
      if (result.backward_speed < backward_speed) then
        backward_speed = result.backward_speed
      end
      if forward_speed > 0 then
        result.forward_speed = forward_speed * speed_boost
        result.backward_speed = backward_speed * speed_boost
      else
        -- For ways with 0 speed but part of cycle network, give them basic speed
        result.forward_speed = 5
        result.backward_speed = 5
        result.forward_mode = mode.cycling
        result.backward_mode = mode.cycling
      end
    end
  end
end


function process_turn(profile, turn)
  local normalized_angle = turn.angle / 90.0
  if normalized_angle >= 0.0 then
    turn.duration = normalized_angle * normalized_angle * profile.turn_penalty / profile.turn_bias
  else
    turn.duration = normalized_angle * normalized_angle * profile.turn_penalty * profile.turn_bias
  end

  if turn.is_u_turn then
    turn.duration = turn.duration + profile.properties.u_turn_penalty
  end

  if turn.has_traffic_light then
     turn.duration = turn.duration + profile.properties.traffic_light_penalty
  end

  local source_is_highway = (turn.source_mode == mode.highway_cycling)
  local target_is_highway = (turn.target_mode == mode.highway_cycling)
  if not source_is_highway and target_is_highway then
    turn.duration = turn.duration + 600
  elseif source_is_highway and not target_is_highway then
    turn.duration = turn.duration + 600
  end

  if profile.properties.weight_name == 'cyclability' then
    turn.weight = turn.duration
  end
  if turn.source_mode == mode.cycling and turn.target_mode ~= mode.cycling then
    turn.weight = turn.weight + profile.properties.mode_change_penalty
  end
end

return {
  setup = setup,
  process_way = process_way,
  process_node = process_node,
  process_turn = process_turn
}
