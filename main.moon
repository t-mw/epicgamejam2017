inspect = require "lib.inspect"
Gamestate = require "lib.hump.gamestate"
Timer = require "lib.hump.timer"
lume = require "lib.lume"
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
NUM_VILLAGE_TYPES = 3
INFECTION_CRITICAL = 100

TILE_SCALE = 48 / 32

GFX = {}

AUDIO =
  infection: love.audio.newSource "music/infection.wav", "static"
  infection_complete: love.audio.newSource "music/InfectionComplete.wav", "static"
  heal: love.audio.newSource "music/Heal.wav", "static"
  play_theme_loop: love.audio.newSource "music/playthemeLoopFull.wav"

JOB =
  block: "block"
  rotate: "rotate"
  dig: "dig"

local *

state = nil
gfx = nil

export game_states = {
  game: {}
  win: {}
}

love.load = ->
  love.window.setMode 800, 600, highdpi: true

  math.randomseed os.time!

  -- load tile images
  --  grass
  GFX.grass = new_image_no_filter "graphics/grass.png"

  --  village houses
  h = new_image_no_filter "graphics/houses.png"
  qs = {}
  qs[0] = love.graphics.newQuad(32*0, 0, 32, 32, h\getDimensions!)
  qs[1] = love.graphics.newQuad(32*1, 0, 32, 32, h\getDimensions!)
  qs[2] = love.graphics.newQuad(32*2, 0, 32, 32, h\getDimensions!)
  GFX.houses_qs = qs
  GFX.houses_image = h

  --  paths
  h = new_image_no_filter "graphics/path2.png"
  qs = {}
  qs[0] = love.graphics.newQuad(32*0, 0, 32, 32, h\getDimensions!)
  qs[1] = love.graphics.newQuad(32*1, 0, 32, 32, h\getDimensions!)
  qs[2] = love.graphics.newQuad(32*2, 0, 32, 32, h\getDimensions!)
  qs[3] = love.graphics.newQuad(32*3, 0, 32, 32, h\getDimensions!)
  qs[4] = love.graphics.newQuad(32*4, 0, 32, 32, h\getDimensions!)
  GFX.paths_qs = qs
  GFX.paths_image = h

  --  doctors
  GFX.doctorleft = new_image_no_filter "graphics/doctorleft.png"
  GFX.doctorback = new_image_no_filter "graphics/doctorback.png"
  GFX.doctorfront = new_image_no_filter "graphics/doctorfront.png"

  GFX.glow = new_image_no_filter "graphics/glow.png"

  Gamestate.registerEvents!
  Gamestate.switch game_states.game

new_image_no_filter = (path) ->
  with love.graphics.newImage path
    \setFilter "nearest", "nearest"

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
  level >= INFECTION_CRITICAL

map_tile = (i) ->
  -- village/houses
  has_village = math.random! < 0.1

  --  type of village
  village_idx = -1
  if has_village
    village_idx = math.floor(math.random! * NUM_VILLAGE_TYPES)

  x, y = from_1d_to_2d_idx i, MAP_SIZE
  max_rate = math.max MAP_SIZE - x, MAP_SIZE - y

  infection_rate = has_village and lume.round(lume.random 10, max_rate) or 0

  {
    idx: i
    north: false
    west: false
    south: false
    east: false
    :has_village
    :village_idx
    infection_level: infection_rate
    :infection_rate
  }

set_infection_level = (t, v) ->
  t.infection_level = v

  g = gfx.infection_level[t.idx] or {:v, timer: nil}

  Timer.cancel g.timer if g.timer
  g.timer = Timer.tween 2, g, {:v}, "out-expo"

  gfx.infection_level[t.idx] = g

calculate_win_conditions = (agents, map) ->
  village_tiles = lume.filter map, (t) -> t.has_village
  infected_tiles = lume.filter village_tiles, (t) -> is_infection_critical(t.infection_level)
  clear_tiles = lume.filter village_tiles, (t) -> t.infection_level == 0

  {
    all_count: #village_tiles
    infected_count: #infected_tiles
    clear_count: #clear_tiles
    time: get_time!
    used_count: #filter_inactive_agents(agents)
  }

are_win_conditions_complete = (conditions) ->
  conditions.all_count == conditions.infected_count + conditions.clear_count

generate_map = (size) ->
  result = {}

  for i = 1, size * size
    t = map_tile(i)
    table.insert result, t

    -- initialise gfx
    set_infection_level t, t.infection_level

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

add_agent = (agents) ->
  id = #agents + 1

  table.insert agents, {
    :id
    active: true
    created_at: get_time!
    inactive_since: 0
    source: 0
    destination: 0
    is_stationary: false,
    position: vector(0, 0),
    job: nil
    dig_tile_indices: {}
    digging_since: 0
    blocking_time: BLOCKING_TIME
    blocked: false
  }

  agents

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

world_pos_to_tile_idx = (v) ->
  x, y = world_pos_to_tile_pos v
  from_2d_to_1d_idx x, y, MAP_SIZE

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
    speed = a.job == "dig" and 80 or 40

    -- affects the pause between moves
    NORMALIZE_TO = 35

    diff = dest_pos - position
    diff = (diff\trimmed NORMALIZE_TO) / NORMALIZE_TO

    a.position = position + diff * speed * dt

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

are_connected_along = (dir, idx1, idx2, map) ->
  t1 = map[idx1]
  t2 = map[idx2]

  switch dir
    when "east"
      are_neighbours_along(dir, idx1, idx2, map) and t1.east and t2.west
    when "west"
      are_neighbours_along(dir, idx1, idx2, map) and t1.west and t2.east
    when "south"
      are_neighbours_along(dir, idx1, idx2, map) and t1.south and t2.north
    when "north"
      are_neighbours_along(dir, idx1, idx2, map) and t1.north and t2.south

are_neighbours_along = (dir, idx1, idx2, map) ->
  t1 = map[idx1]
  t2 = map[idx2]

  x1, y1 = from_1d_to_2d_idx idx1, MAP_SIZE
  x2, y2 = from_1d_to_2d_idx idx2, MAP_SIZE

  switch dir
    when "east"
      x1 + 1 == x2 and y1 == y2
    when "west"
      x1 - 1 == x2 and y1 == y2
    when "south"
      x1 == x2 and y1 + 1 == y2
    when "north"
      x1 == x2 and y1 - 1 == y2

connect_tiles = (idx1, idx2, map) ->
  t1 = map[idx1]
  t2 = map[idx2]

  if are_neighbours_along "east", idx1, idx2, map
    t1.east = true
    t2.west = true
  elseif are_neighbours_along "west", idx1, idx2, map
    t1.west = true
    t2.east = true
  elseif are_neighbours_along "south", idx1, idx2, map
    t1.south = true
    t2.north = true
  elseif are_neighbours_along "north", idx1, idx2, map
    t1.north = true
    t2.south = true

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
  {:source, :destination, :job, :dig_tile_indices} = a

  new_destination = destination

  if destination == 0
    new_destination = 1
  else
    if job == "dig"
      new_destination = table.remove(dig_tile_indices, 1) or destination
    else
      neighbors = get_map_tile_neighbor_indices destination, map

      if #neighbors > 0
        -- avoid critical infections
        neighbors = lume.reject neighbors, (n) ->
            is_infection_critical map[n].infection_level

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
    calculate_new_agent_destination(a, map, time), true
  else
    a.destination, false

update_agent_destination = (a, map, blockers, time) ->
  return if a.job == "block"

  new_destination, reached_old = calculate_agent_destination a, map, time

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

  if new_destination == a.destination and reached_old
    a.is_stationary = true

  elseif new_destination != a.destination
    a.source = a.destination
    a.destination = new_destination
    a.is_stationary = false

calculate_dig_tile_indices = (source_x, source_y, target_x, target_y, map) ->
  result = {}

  diff = vector(target_x, target_y) - vector(source_x, source_y)

  if diff.x != 0 or diff.y != 0
    idx = from_2d_to_1d_idx source_x, source_y, MAP_SIZE

    dir, max = if diff.x > 0
      "east", math.abs diff.x
    elseif diff.x < 0
      "west", math.abs diff.x
    elseif diff.y > 0
      "south", math.abs diff.y
    elseif diff.y < 0
      "north", math.abs diff.y

    n = 0

    while n < max
      n += 1
      idx_n = get_map_tile_neighbor_dir dir, idx, map

      if not idx_n or are_connected_along dir, idx, idx_n, map
        break
      else
        table.insert result, idx_n
        idx = idx_n

  result

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

      set_infection_level post_tile, math.max(infection_level - 10, 0)

apply_digging = (a, pre_move, map) ->
  if not a.job == "dig"
    return

  pre_tile_idx = world_pos_to_tile_idx pre_move
  post_tile_idx = world_pos_to_tile_idx a.position

  pre_tile = map[pre_tile_idx]
  post_tile = map[post_tile_idx]

  if post_tile and (not pre_tile or pre_tile.idx != post_tile.idx)
    connect_tiles pre_tile_idx, post_tile_idx, map

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


draw_agent = (a, x, y, time) ->
  {:source, :destination} = a

  x_source, y_source = from_1d_to_2d_idx source, MAP_SIZE
  x_dest, y_dest = from_1d_to_2d_idx destination, MAP_SIZE

  sprite, dx, scale_x = if x_source == x_dest and y_source == y_dest
    GFX.doctorfront, 0, 1
  elseif x_source > x_dest
    GFX.doctorleft, 0, 1
  elseif x_source < x_dest
    GFX.doctorleft, TILE_SIZE, -1
  elseif y_source > y_dest
    GFX.doctorback, 0, 1
  else
    GFX.doctorfront, 0, 1

  x = lume.round x - TILE_SIZE / 2 + dx

  FEET_OFFSET = 15
  y = lume.round y - TILE_SIZE + FEET_OFFSET


  dy = if a.job == "dig"
    digging_since = time - a.digging_since

    BOUNCE_DURATION = 0.1
    BOUNCE_HEIGHT = 2

    bounce = 2 * ((digging_since / BOUNCE_DURATION) % 1)
    bounce = 2 - bounce if bounce > 1

    bounce * BOUNCE_HEIGHT
  else
    0

  love.graphics.draw sprite, x, y + dy, 0, scale_x * TILE_SCALE, TILE_SCALE

draw_tile_path = (tile, x, y, x0, y0) ->
  x1 = TILE_SIZE * x
  y1 = TILE_SIZE * y

  x2 = TILE_SIZE * (x + 0.5)
  y2 = TILE_SIZE * (y + 0.5)

  x1, y1 = project_to_screen x1, y1
  x2, y2 = project_to_screen x2, y2

  path_idx = -1
  angle = 0
  sum = 0
  x_off = 0
  y_off = 0
  sum += 1 if tile.north
  sum += 1 if tile.west
  sum += 1 if tile.south
  sum += 1 if tile.east

  if sum == 4
    path_idx = 0

  elseif sum == 3
    path_idx = 3
    if not tile.east
      angle = 0
    else if not tile.south
      angle = 90
      x_off = TILE_SIZE
    else if not tile.west
      angle = 180
      x_off = TILE_SIZE
      y_off = TILE_SIZE
    else if not tile.north
      angle = 270
      y_off = TILE_SIZE

  elseif sum == 2
    if tile.north and tile.south
      path_idx = 2
    else if tile.west and tile.east
      path_idx = 2
      angle = 90
      x_off = TILE_SIZE
    else if tile.east and tile.south
      path_idx = 1
    else if tile.south and tile.west
      path_idx = 1
      angle = 90
      x_off = TILE_SIZE
    else if tile.west and tile.north
      path_idx = 1
      angle = 180
      x_off = TILE_SIZE
      y_off = TILE_SIZE
    else if tile.north and tile.east
      path_idx = 1
      angle = 270
      y_off = TILE_SIZE
      --x_off = TILE_SIZE

  else if sum == 1
    path_idx = 4
    if tile.north
      angle = 0
    else if tile.east
      angle = 90
      x_off = TILE_SIZE
    else if tile.south
      angle = 180
      x_off = TILE_SIZE
      y_off = TILE_SIZE
    else if tile.west
      angle = 270
      y_off = TILE_SIZE


  --  ii = math.floor(math.random! * 4)

  -- draw path depending on index
  if path_idx ~= -1
    love.graphics.setColor 100, 100, 100
    love.graphics.draw(GFX.paths_image, GFX.paths_qs[path_idx], x0+x_off, y0+y_off, math.rad(angle), TILE_SCALE, TILE_SCALE)

  --love.graphics.setColor 200, 200, 0
  --love.graphics.line x1, y1, x1, y0 if tile.north
  --love.graphics.line x1, y1, x0, y1 if tile.west
  --love.graphics.line x1, y1, x1, y2 if tile.south
  --love.graphics.line x1, y1, x2, y1 if tile.east

draw_tile = (idx, tile) ->
  x, y = from_1d_to_2d_idx idx, MAP_SIZE

  x0 = TILE_SIZE * (x - 0.5)
  y0 = TILE_SIZE * (y - 0.5)

  x0, y0 = project_to_screen x0, y0


  love.graphics.setColor 50, 100 + ((idx * 124290) % 100), 50
  love.graphics.rectangle "fill", x0, y0, TILE_SIZE, TILE_SIZE

  --draw grass graphics

  img_scale = TILE_SIZE / IMAGE_SIZE
  love.graphics.draw(GFX.grass, x0, y0, 0, TILE_SCALE, TILE_SCALE)

  draw_tile_path(tile, x, y, x0, y0)

  if tile.has_village
    l = gfx.infection_level[idx].v
    frac = l / INFECTION_CRITICAL

    love.graphics.setColor 100, 100, 100
    --love.graphics.rectangle "fill", x0, y0, TILE_SIZE, TILE_SIZE

    love.graphics.setColor 50 + l, 50, 50
    love.graphics.rectangle "fill", x0, y0 + TILE_SIZE * (1 - frac), TILE_SIZE, TILE_SIZE * frac

    --draw village (one of the houses) graphics
    love.graphics.draw(GFX.houses_image, GFX.houses_qs[tile.village_idx], x0, y0, math.rad(0), TILE_SCALE, TILE_SCALE)

  --love.graphics.setColor 0, 0, 0
  --love.graphics.rectangle "line", x0, y0, TILE_SIZE, TILE_SIZE

game_states.game.enter = ->

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
    win_conditions: nil

  gfx =
    glows: {}
    infection_level: {}

  state.map_start_time = love.timer.getTime!
  state.map = generate_map MAP_SIZE

  generate_map_routes 1, 1, state.map

  MAX_COUNT = 20
  count = 0
  handle = Timer.every 3, () ->
    add_agent state.agents

    count += 1
    count < MAX_COUNT

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

game_states.game.update = (self, dt) ->
  time = get_time!

  agents = filter_active_agents state.agents
  blockers = lume.filter agents, (a) -> a.job == JOB.block

  for a in *agents
    pre_move = a.position

    update_agent_position a, dt
    update_agent_destination a, state.map, blockers, time

    apply_healing a, pre_move, state.map
    apply_digging a, pre_move, state.map

    if a.job == "dig" and a.is_stationary
      deactivate_agent a, time

  x, y =  love.mouse.getPosition!
  x, y = project_to_world x, y

  hover_agent = find_agent_at x, y, agents
  state.hover_agent_id = hover_agent and not hover_agent.job and hover_agent.id

  state.infection_timer -= dt

  if state.infection_timer < 0

    state.infection_timer_max = math.max state.infection_timer_max *
      INFECTION_TIMER_DECAY, INFECTION_TIMER_MIN

    state.infection_timer = state.infection_timer_max

    any_critical = false

    for t in *state.map
      if t.infection_level > 0
        infection_level1 = t.infection_level
        infection_level2 = math.min infection_level1 + t.infection_rate, INFECTION_CRITICAL

        if infection_level2 != infection_level1
          set_infection_level t, infection_level2
          any_critical = any_critical or is_infection_critical infection_level2

    if any_critical
      AUDIO.infection_complete\play!
    else
      AUDIO.infection\play!

  if not state.win_conditions
    win_conditions = calculate_win_conditions state.agents, state.map

    if are_win_conditions_complete win_conditions
      state.win_conditions = win_conditions

      Gamestate.switch game_states.win

  Timer.update(dt)

game_states.game.keypressed = (self, key) ->
  agents = filter_active_agents state.agents

  hover_agent = find_agent state.select_agent_id, agents

  switch key
    when "1"
      state.active_job = "block"
    when "2"
      state.active_job = "dig"
    when "3"
      state.active_job = "rotate"

game_states.game.mousepressed = (self, x, y, button) ->
  agents = filter_active_agents state.agents

  if button != 1
    return

  x, y = project_to_world x, y
  active_job = state.active_job

  if active_job
    select_agent = find_agent_at x, y, agents

    if select_agent and not select_agent.job
      if active_job == "dig"
        state.dig_agent_id = select_agent.id
      else
        select_agent.job = active_job if not select_agent.job

game_states.game.mousereleased = (self, x, y, button) ->
  if button != 1
    return

  {:agents, :map} = state

  if dig_agent = find_agent state.dig_agent_id, agents
    x, y = project_to_world x, y

    source_x, source_y = world_pos_to_tile_pos dig_agent.position
    target_x, target_y = world_pos_to_tile_pos vector(x, y)

    dig_tile_indices = calculate_dig_tile_indices source_x, source_y, target_x, target_y, state.map

    if #dig_tile_indices > 0
      dig_agent.job = "dig"
      dig_agent.dig_tile_indices = dig_tile_indices
      dig_agent.digging_since = get_time!

  state.dig_agent_id = nil

game_states.game.draw = ->
  time = get_time!

  mouse_x, mouse_y = love.mouse.getPosition!

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

    DURATION = 2
    duration = math.min((time - a.created_at) / DURATION, 1)

    color = if state.hover_agent_id == a.id
      {180 * duration, 255 * duration, 180 * duration}
    else
      {255 * duration, 255 * duration, 255 * duration}

    love.graphics.setColor color
    draw_agent a, x, y, time

  if dig_agent = find_agent state.dig_agent_id, agents
    mouse_world_x, mouse_world_y = project_to_world mouse_x, mouse_y

    source_x, source_y = world_pos_to_tile_pos dig_agent.position
    target_x, target_y = world_pos_to_tile_pos vector(mouse_world_x, mouse_world_y)

    dig_tile_indices = calculate_dig_tile_indices source_x, source_y, target_x, target_y, state.map
    valid = #dig_tile_indices > 0

    x1, y1, x2, y2 = unless valid
      v1 = dig_agent.position

      v1.x, v1.y, mouse_world_x, mouse_world_y
    else
      v1 = tile_pos_to_world_pos source_x, source_y

      last_idx = lume.last dig_tile_indices
      x2, y2 = from_1d_to_2d_idx last_idx, MAP_SIZE
      v2 = tile_pos_to_world_pos x2, y2

      v1.x, v1.y, v2.x, v2.y

    x1, y1 = project_to_screen x1, y1
    x2, y2 = project_to_screen x2, y2

    STEP_SIZE = 10

    src = vector(x1, y1)
    dest = vector(x2, y2)
    diff = dest - src
    len = diff\len!
    norm = diff / len
    steps = len / STEP_SIZE

    color = valid and {100, 255, 100} or {255, 100, 100}
    love.graphics.setColor color

    for i = 1, steps + 1
      draw = src + norm * (i - 1) * STEP_SIZE
      love.graphics.rectangle "fill", draw.x - 1, draw.y - 1, 2, 2

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
      love.graphics.draw(GFX.glow, x, y, e, TILE_SCALE, TILE_SCALE, 0.5 * TILE_SIZE / TILE_SCALE, 0.5 * TILE_SIZE / TILE_SCALE)

  bar_width = 500
  love.graphics.translate 0.5 * (width - bar_width), height - 40
  love.graphics.setColor 50, 50, 50
  love.graphics.rectangle "fill", 0, 0, bar_width, 20
  love.graphics.setColor 255, 0, 0
  love.graphics.rectangle "fill", 0, 0, bar_width * (state.infection_timer_max - state.infection_timer) / state.infection_timer_max, 20

game_states.win.draw = ->
  print "WIN"
