inspect = require "lib.inspect"
lume = require "lib.lume"
Timer = require "lib.hump.timer"
vector = require "lib.hump.vector"

MAP_SIZE = 10
TILE_SIZE = 48
IMAGE_SIZE = 32
AGENT_MATCH_RADIUS2 = 200
AGENT_BLOCK_RADIUS2 = 200
INFECTION_TIMER_START = 20
INFECTION_TIMER_DECAY = 0.8
INFECTION_TIMER_MIN = 5
BLOCKING_TIME = 3

TILE_SCALE = 48 / 32

AUDIO =
  infection_complete: love.audio.newSource "music/InfectionComplete.wav", "static"
  heal: love.audio.newSource "music/Heal.wav", "static"
  play_theme_loop: love.audio.newSource "music/playThemeLoopFull.wav"

JOB =
  block: "block"
  rotate: "rotate"
  dig: "dig"

local *

state =
  map_start_time: 0
  map: {}
  tiles: {}
  gfx: {}
  agents: {}
  hover_agent_id: nil
  dig_agent_id: nil
  active_job: nil
  infection_timer: INFECTION_TIMER_START
  infection_timer_max: INFECTION_TIMER_START

gfx =
  glows: {}

filled_array = (size, val = 0) ->
  result = {}
  for i = 1, size
    table.insert result, val
  result

from_2d_to_1d_idx = (x, y, width) ->
  ((x - 1) * width) + y

from_1d_to_2d_idx = (i, width) ->
  math.floor((i - 1) / width) + 1, ((i - 1) % width) + 1

get_time = ->
  love.timer.getTime! - state.map_start_time

is_infection_critical = (level) ->
  level == 100

map_tile = (i) ->
  has_village = math.random! < 0.1

  x, y = from_1d_to_2d_idx i, MAP_SIZE
  max_rate = math.max MAP_SIZE - x, MAP_SIZE - y

  infection_rate = has_village and lume.round(math.random! * max_rate) or 0

  {
    idx: i
    north: false
    west: false
    south: false
    east: false
    :has_village
    infection_level: infection_rate
    :infection_rate
  }

generate_map = (size) ->
  result = {}

  for i = 1, size * size
    table.insert result, map_tile(i)

  result

clear_map = (map) ->
  for t in *map
    t.north = false
    t.west = false
    t.south = false
    t.east = false

generate_map_route = (start_idx, length, branch_count, visited, map) ->
  idx = start_idx
  n = 0

  while n < length
    n += 1
    visited[idx] = true

    tile = map[idx]

    rand1 = math.random!
    rand2 = math.random!

    idx_e = get_map_tile_neighbor_dir "east", idx, map
    idx_w = get_map_tile_neighbor_dir "west", idx, map
    idx_s = get_map_tile_neighbor_dir "south", idx, map
    idx_n = get_map_tile_neighbor_dir "north", idx, map

    free_e = idx_e and not map[idx_e].west and not tile.east and not visited[idx_e]
    free_w = idx_w and not map[idx_w].east and not tile.west and not visited[idx_w]
    free_s = idx_s and not map[idx_s].north and not tile.south and not visited[idx_s]
    free_n = idx_n and not map[idx_n].south and not tile.north and not visited[idx_n]

    count = (free_e and 1 or 0) +
      (free_w and 1 or 0) +
      (free_s and 1 or 0) +
      (free_n and 1 or 0)

    inv_count = 1 / count

    generate_branch = branch_count > 0 and math.random! < 0.4

    if rand1 < inv_count and free_e
      n_tile = map[idx_e]

      n_tile.west = true
      tile.east = true

      idx = idx_e

      generate_map_route(idx, 4, branch_count - 1, visited, map) if generate_branch
      continue

    elseif rand1 < inv_count * 2 and free_w
      n_tile = map[idx_w]

      n_tile.east = true
      tile.west = true

      idx = idx_w

      generate_map_route(idx, 4, branch_count - 1, visited, map) if generate_branch
      continue

    elseif rand1 < inv_count * 3 and free_s
      n_tile = map[idx_s]

      n_tile.north = true
      tile.south = true

      idx = idx_s

      generate_map_route(idx, 4, branch_count - 1, visited, map) if generate_branch
      continue

    elseif free_n
      n_tile = map[idx_n]

      n_tile.south = true
      tile.north = true

      idx = idx_n

      generate_map_route(idx, 4, branch_count - 1, visited, map) if generate_branch
      continue

    break

generate_map_routes = (start_x, start_y, map) ->
  start_idx = from_2d_to_1d_idx start_x, start_y, MAP_SIZE

  while true
    clear_map map

    visited = {}
    generate_map_route start_idx, 20, 2, visited, map

    -- avoid lume.count treating visited as array
    visited[1] = nil

    if lume.count(visited) + 1 > 40
      break

generate_agents = () ->
  result = {}

  for i = 1, 10
    table.insert result, {
      id: i
      active: true
      inactive_since: 0
      start_order: i
      source: 0
      destination: 0
      position: vector(0, 0),
      job: nil
      blocking_time: BLOCKING_TIME
      blocked: false
    }

  result

deactivate_agent = (a, time) ->
  a.active = false
  a.inactive_since = time

filter_active_agents = (agents) ->
  lume.filter agents, (a) -> a.active

filter_inactive_agents = (agents) ->
  lume.filter agents, (a) -> not a.active

tile_pos_to_world_pos = (x, y) ->
  vector(x, y) * TILE_SIZE

world_pos_to_tile_pos = (v) ->
  v = v / TILE_SIZE
  lume.round(v.x), lume.round(v.y)

calculate_start_time = (a) ->
  a.start_order * 2

agent_distance2 = (a, b) ->
  (a.position - b.position)\len2!

update_agent_position = (a, dt) ->
  {:source, :destination, :position} = a

  return if a.job == JOB.block

  x_source, y_source = from_1d_to_2d_idx source, MAP_SIZE
  x_dest, y_dest = from_1d_to_2d_idx destination, MAP_SIZE

  dest_pos = tile_pos_to_world_pos x_dest, y_dest

  if source == destination
    a.position = vector(x, y)

  else
    SPEED = 20

    diff = dest_pos - position
    diff\trimInplace SPEED

    a.position = position + diff * dt

get_map_tile_neighbor_dir = (dir, idx, map) ->
  tile = map[idx]
  x0, y0 = from_1d_to_2d_idx idx, MAP_SIZE

  n_idx = nil

  switch dir
    when "east"
      xn, yn = x0 + 1, y0
      if xn >= 1 and xn <= MAP_SIZE and yn >= 1 and yn <= MAP_SIZE
        n_idx = from_2d_to_1d_idx xn, yn, MAP_SIZE

    when "west"
      xn, yn = x0 - 1, y0
      if xn >= 1 and xn <= MAP_SIZE and yn >= 1 and yn <= MAP_SIZE
        n_idx = from_2d_to_1d_idx xn, yn, MAP_SIZE

    when "south"
      xn, yn = x0, y0 + 1
      if xn >= 1 and xn <= MAP_SIZE and yn >= 1 and yn <= MAP_SIZE
        n_idx = from_2d_to_1d_idx xn, yn, MAP_SIZE

    when "north"
      xn, yn = x0, y0 - 1
      if xn >= 1 and xn <= MAP_SIZE and yn >= 1 and yn <= MAP_SIZE
        n_idx = from_2d_to_1d_idx xn, yn, MAP_SIZE

  n_idx

get_map_tile_neighbor_indices = (idx, map) ->
  tile = map[idx]
  x0, y0 = from_1d_to_2d_idx idx, MAP_SIZE

  result = {}

  if n_idx = get_map_tile_neighbor_dir "east", idx, map
    n_tile = map[n_idx]
    if n_tile.west and tile.east
      table.insert result, n_idx

  if n_idx = get_map_tile_neighbor_dir "west", idx, map
    n_tile = map[n_idx]
    if n_tile.east and tile.west
      table.insert result, n_idx

  if n_idx = get_map_tile_neighbor_dir "south", idx, map
    n_tile = map[n_idx]
    if n_tile.north and tile.south
      table.insert result, n_idx

  if n_idx = get_map_tile_neighbor_dir "north", idx, map
    n_tile = map[n_idx]
    if n_tile.south and tile.north
      table.insert result, n_idx

  result

calculate_new_agent_destination = (a, map, time) ->
  {:source, :destination} = a

  new_destination = destination

  if time > calculate_start_time a
    if destination == 0
      new_destination = 1
    else
      neighbors = get_map_tile_neighbor_indices destination, map

      if #neighbors > 0
        -- avoid backtracking
        lume.remove neighbors, source if #neighbors > 1
        new_destination = lume.randomchoice(neighbors) or destination

  new_destination

calculate_agent_destination = (a, map, time) ->
  {:source, :destination, :position} = a

  x_dest, y_dest = from_1d_to_2d_idx destination, MAP_SIZE
  dest_pos = tile_pos_to_world_pos x_dest, y_dest

  dest_dist2 = (dest_pos - position)\len2!

  DIST_THRESHOLD = 5

  if destination == 0 or dest_dist2 < DIST_THRESHOLD
    calculate_new_agent_destination a, map, time
  else
    a.destination

update_agent_destination = (a, map, blockers, time) ->
  return if a.job == "block"

  new_destination = calculate_agent_destination a, map, time

  if not a.blocked and
    lume.match blockers, (b) -> agent_distance2(a, b) < AGENT_BLOCK_RADIUS2

    tmp = a.source
    a.source = a.destination
    a.destination = tmp

    a.blocked = true
    -- add delay to avoid agents getting stuck
    Timer.after 0.05, () -> a.blocked = false

    return

  new_destination_tile = map[new_destination]
  is_critical = new_destination_tile and
    is_infection_critical new_destination_tile.infection_level

  if new_destination != a.destination and not is_critical
    a.source = a.destination
    a.destination = new_destination

apply_dig_agent = (agent, target_x, target_y, map) ->

  source_tile = (() ->
    x, y = world_pos_to_tile_pos agent.position
    idx = from_2d_to_1d_idx x, y, MAP_SIZE
    map[idx]
  )()

  target_tile = (() ->
    x, y = world_pos_to_tile_pos vector(target_x, target_y)
    idx = from_2d_to_1d_idx x, y, MAP_SIZE
    map[idx]
  )()

  if source_tile and target_tile
    source_idx = source_tile.idx
    target_idx = target_tile.idx

    idx_e = get_map_tile_neighbor_dir "east", source_idx, map
    idx_w = get_map_tile_neighbor_dir "west", source_idx, map
    idx_n = get_map_tile_neighbor_dir "north", source_idx, map
    idx_s = get_map_tile_neighbor_dir "south", source_idx, map

    if target_idx == idx_e
      source_tile.east = true
      target_tile.west = true

    if target_idx == idx_w
      source_tile.west = true
      target_tile.east = true

    if target_idx == idx_n
      source_tile.north = true
      target_tile.south = true

    if target_idx == idx_s
      source_tile.south = true
      target_tile.north = true

apply_healing = (a, pre_move, map) ->

  pre_tile = (() ->
    x, y = world_pos_to_tile_pos pre_move
    idx = from_2d_to_1d_idx x, y, MAP_SIZE
    map[idx]
  )()

  post_tile = (() ->
    x, y = world_pos_to_tile_pos a.position
    idx = from_2d_to_1d_idx x, y, MAP_SIZE
    map[idx]
  )()

  if post_tile and (not pre_tile or pre_tile.idx != post_tile.idx)
    infection_level = post_tile.infection_level

    if infection_level > 0
      AUDIO.heal\play!
      table.insert gfx.glows, tile_idx: post_tile.idx, since: get_time!

      post_tile.infection_level = math.max infection_level - 10, 0

find_agent_at = (world_x, world_y, agents) ->
  w = vector world_x, world_y
  for a in *agents
    if (a.position - w)\len2! < AGENT_MATCH_RADIUS2
      return a

  nil

project_to_screen = (x, y) ->
  scale = love.window.getPixelScale!

  width = love.graphics.getWidth! / scale
  height = love.graphics.getHeight! / scale

  size = (1 + MAP_SIZE) * TILE_SIZE
  x += (width - size) / 2
  y += (height - size) / 2

  x, y

project_to_world = (x, y) ->
  scale = love.window.getPixelScale!

  width = love.graphics.getWidth! / scale
  height = love.graphics.getHeight! / scale

  x /= scale
  y /= scale

  size = (1 + MAP_SIZE) * TILE_SIZE
  x -= (width - size) / 2
  y -= (height - size) / 2

  x, y

find_agent = (id, agents) ->
  lume.match agents, (a) -> a.id == id


draw_agent = (a, x, y) ->
  {:source, :destination} = a

  x_source, y_source = from_1d_to_2d_idx source, MAP_SIZE
  x_dest, y_dest = from_1d_to_2d_idx destination, MAP_SIZE

  sprite, dx, scale_x = if x_source == x_dest and y_source == y_dest
    state.gfx.doctorfront, 0, 1
  elseif x_source > x_dest
    state.gfx.doctorleft, 0, 1
  elseif x_source < x_dest
    state.gfx.doctorleft, TILE_SIZE, -1
  elseif y_source > y_dest
    state.gfx.doctorback, 0, 1
  else
    state.gfx.doctorfront, 0, 1

  x = lume.round x - TILE_SIZE / 2 + dx
  y = lume.round y - TILE_SIZE / 2

  love.graphics.draw sprite, x, y, 0, scale_x * TILE_SCALE, TILE_SCALE

draw_tile_path = (tile, x0, y0, x1, y1, x2, y2) ->
  love.graphics.setColor 200, 200, 0
  love.graphics.line x1, y1, x1, y0 if tile.north
  love.graphics.line x1, y1, x0, y1 if tile.west
  love.graphics.line x1, y1, x1, y2 if tile.south
  love.graphics.line x1, y1, x2, y1 if tile.east

draw_tile = (idx, tile) ->
  x, y = from_1d_to_2d_idx idx, MAP_SIZE

  x0 = TILE_SIZE * (x - 0.5)
  y0 = TILE_SIZE * (y - 0.5)

  x1 = TILE_SIZE * x
  y1 = TILE_SIZE * y

  x2 = TILE_SIZE * (x + 0.5)
  y2 = TILE_SIZE * (y + 0.5)

  x0, y0 = project_to_screen x0, y0
  x1, y1 = project_to_screen x1, y1
  x2, y2 = project_to_screen x2, y2

  love.graphics.setColor 50, 100 + ((idx * 124290) % 100), 50
  love.graphics.rectangle "fill", x0, y0, TILE_SIZE, TILE_SIZE

  --draw grass graphics

  img_scale = TILE_SIZE / IMAGE_SIZE
  love.graphics.draw(state.tiles.grass, x0, y0, 0, TILE_SCALE, TILE_SCALE)
--  ii = math.floor(math.random! * 4)
  --love.graphics.draw(state.tiles.paths_image, state.tiles.paths_qs[ii], x0, y0, math.rad(0), TILE_SCALE, TILE_SCALE)

  if tile.has_village
    l = lume.round tile.infection_level
    frac = tile.infection_level / 100

    love.graphics.setColor 100, 100, 100
    love.graphics.rectangle "fill", x0, y0, TILE_SIZE, TILE_SIZE

    love.graphics.setColor 50 + l, 50, 50
    love.graphics.rectangle "fill", x0, y0 + TILE_SIZE * (1 - frac), TILE_SIZE, TILE_SIZE * frac

    --draw village (one of the houses) graphics
    love.graphics.draw(state.tiles.houses_image, state.tiles.houses_qs[2], x0, y0, math.rad(0), TILE_SCALE, TILE_SCALE)

  --love.graphics.setColor 0, 0, 0
  --love.graphics.rectangle "line", x0, y0, TILE_SIZE, TILE_SIZE

  draw_tile_path(tile, x0, y0, x1, y1, x2, y2)

love.load = ->
  love.window.setMode 800, 600, highdpi: true

  math.randomseed os.time!

  state.map_start_time = love.timer.getTime!
  state.map = generate_map MAP_SIZE
  state.agents = generate_agents!

  generate_map_routes 1, 1, state.map

  -- load tile images

  --  grass
  state.tiles.grass = love.graphics.newImage("graphics/grass.png")

  --  village houses
  h = love.graphics.newImage("graphics/houses.png")
  h\setFilter("nearest", "nearest")
  qs = {}
  qs[0] = love.graphics.newQuad(32*0, 0, 32, 32, h\getDimensions())
  qs[1] = love.graphics.newQuad(32*1, 0, 32, 32, h\getDimensions())
  qs[2] = love.graphics.newQuad(32*2, 0, 32, 32, h\getDimensions())
  state.tiles.houses_qs = qs
  state.tiles.houses_image = h

  --  paths
  state.tiles.paths_image = love.graphics.newImage("graphics/path2.png")
  qs = {}
  qs[0] = love.graphics.newQuad(32*0, 0, 32, 32, h\getDimensions())
  qs[1] = love.graphics.newQuad(32*1, 0, 32, 32, h\getDimensions())
  qs[2] = love.graphics.newQuad(32*2, 0, 32, 32, h\getDimensions())
  qs[3] = love.graphics.newQuad(32*3, 0, 32, 32, h\getDimensions())
  state.tiles.paths_qs = qs

  --  doctors
  state.gfx.doctorleft = love.graphics.newImage("graphics/doctorleft.png")
  state.gfx.doctorback = love.graphics.newImage("graphics/doctorback.png")
  state.gfx.doctorfront = love.graphics.newImage("graphics/doctorfront.png")

  state.gfx.glow = love.graphics.newImage("graphics/glow.png")

  with AUDIO.play_theme_loop
    \setLooping true
    \play!
    \setVolume 0
    Timer.script (wait) ->
      t = 0
      wait 1
      Timer.during 2, (dt) ->
        t += dt
        volume = t / 2
        \setVolume volume * volume

love.update = (dt) ->
  time = get_time!

  agents = filter_active_agents state.agents
  blockers = lume.filter agents, (a) -> a.job == JOB.block

  for a in *agents
    pre_move = a.position

    update_agent_position a, dt
    update_agent_destination a, state.map, blockers, time

    apply_healing a, pre_move, state.map

  for a in *blockers
    a.blocking_time -= dt
    if a.blocking_time < 0
      deactivate_agent a, time

  x, y =  love.mouse.getPosition!
  x, y = project_to_world x, y

  hover_agent = find_agent_at x, y, agents
  state.hover_agent_id = hover_agent and hover_agent.id

  state.infection_timer -= dt

  if state.infection_timer < 0
    AUDIO.infection_complete\play!

    state.infection_timer_max = math.max state.infection_timer_max *
      INFECTION_TIMER_DECAY, INFECTION_TIMER_MIN

    state.infection_timer = state.infection_timer_max

    for t in *state.map
      if t.infection_level > 0
        infection_level1 = t.infection_level
        infection_level2 = math.min infection_level1 + t.infection_rate, 100

        if infection_level2 != infection_level1
          Timer.tween 2, t, {infection_level: infection_level2}, "expo"

  Timer.update(dt)

love.keypressed = (key) ->
  agents = filter_active_agents state.agents

  hover_agent = find_agent state.select_agent_id, agents

  switch key
    when "1"
      state.active_job = "block"
    when "2"
      state.active_job = "dig"
    when "3"
      state.active_job = "rotate"

love.mousepressed = (x, y, button) ->
  agents = filter_active_agents state.agents

  if button != 1
    return

  x, y = project_to_world x, y
  active_job = state.active_job

  if active_job
    select_agent = find_agent_at x, y, agents

    if select_agent
      if active_job == "dig"
        state.dig_agent_id = select_agent.id
      else
        select_agent.job = active_job if not select_agent.job

love.mousereleased = (x, y, button) ->
  if button != 1
    return

  {:agents, :map} = state

  if dig_agent = find_agent state.dig_agent_id, agents
    x, y = project_to_world x, y
    apply_dig_agent dig_agent, x, y, map

    deactivate_agent dig_agent, get_time!

  state.dig_agent_id = nil

love.draw = ->
  time = get_time!

  agents = filter_active_agents state.agents

  -- sort by depth
  table.sort agents, (a, b) -> a.position.y < b.position.y

  scale = love.window.getPixelScale!
  love.graphics.scale scale

  width = love.graphics.getWidth! / scale
  height = love.graphics.getHeight! / scale

  for idx, tile in ipairs state.map
    draw_tile idx, tile

  for a in *agents
    {:x, :y} = a.position
    x, y = project_to_screen x, y

    color = if state.hover_agent_id == a.id
      {255, 200, 200}
    else
      {255, 255, 255}

    love.graphics.setColor color
    draw_agent a, x, y

    if a.id == state.dig_agent_id
      x1, y1 = love.mouse.getPosition!

      x1 /= scale
      y1 /= scale

      love.graphics.line x, y, x1, y1

  inactive_agents = filter_inactive_agents state.agents

  for a in *inactive_agents
    duration = time - a.inactive_since

    DURATION = 2

    if duration < DURATION
      {:x, :y} = a.position
      x, y = project_to_screen x, y

      e = 1 - duration / DURATION
      e = 1 - e * e * e * e * e

      love.graphics.setColor 128, 128, 128, (1 - e) * 255
      love.graphics.circle "fill", x + 4, y - e * 30, 5
      love.graphics.circle "fill", x - 3, y - e * 40, 4
      love.graphics.circle "fill", x + 7, y - e * 40, 2
      love.graphics.setColor 255, 255, 255, (1 - e) * 255
      love.graphics.circle "fill", x - 10, y - e * 20, 8
      love.graphics.circle "fill", x + 8, y - e * 20, 6
      love.graphics.circle "fill", x - 5, y - e * 30, 5

  for g in *gfx.glows
    duration = time - g.since

    DURATION = 2

    if duration < DURATION
      tile_idx = g.tile_idx

      x, y = from_1d_to_2d_idx tile_idx, MAP_SIZE
      x, y = TILE_SIZE * x, TILE_SIZE * y
      x, y = project_to_screen x, y

      e = 1 - duration / DURATION
      e = 1 - e * e * e * e * e

      love.graphics.setColor 255, 255, 255, (1 - e) * 255
      love.graphics.draw(state.gfx.glow, x, y, e, TILE_SCALE, TILE_SCALE, 0.5 * TILE_SIZE / TILE_SCALE, 0.5 * TILE_SIZE / TILE_SCALE)

  bar_width = 500
  love.graphics.translate 0.5 * (width - bar_width), height - 40
  love.graphics.setColor 50, 50, 50
  love.graphics.rectangle "fill", 0, 0, bar_width, 20
  love.graphics.setColor 255, 0, 0
  love.graphics.rectangle "fill", 0, 0, bar_width * (state.infection_timer_max - state.infection_timer) / state.infection_timer_max, 20
