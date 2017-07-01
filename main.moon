inspect = require "lib.inspect"
lume = require "lib.lume"
vector = require "lib.hump.vector"

state =
  map_start_time: 0
  map: {}
  agents: {}

MAP_SIZE = 10
TILE_SIZE = 50

AUDIO =
  play_theme_loop: love.audio.newSource "music/playThemeLoop.wav"

local *

filled_array = (size, val = 0) ->
  result = {}
  for i = 1, size
    table.insert result, val
  result

from_2d_to_1d_idx = (x, y, width) ->
  ((x - 1) * width) + y

from_1d_to_2d_idx = (i, width) ->
  math.floor((i - 1) / width) + 1, ((i - 1) % width) + 1

generate_map = (size) ->
  result = {}

  for i = 1, size * size
    table.insert result, {
      idx: i
      north: false
      west: false
      south: false
      east: false
    }

  result

generate_map_route = (start_idx, branch_count, map) ->
  idx = start_idx

  while true
    tile = map[idx]
    rand1 = math.random!
    rand2 = math.random!

    idx_e = get_map_tile_neighbor_dir "east", idx, map
    idx_w = get_map_tile_neighbor_dir "west", idx, map
    idx_s = get_map_tile_neighbor_dir "south", idx, map
    idx_n = get_map_tile_neighbor_dir "north", idx, map

    count = (idx_e and 1 or 0) +
      (idx_w and 1 or 0) +
      (idx_s and 1 or 0) +
      (idx_n and 1 or 0)

    inv_count = 1 / count

    generate_branch = branch_count > 0 and math.random! < 0.4

    if rand1 < inv_count and idx_e
      n_tile = map[idx_e]

      if not n_tile.west and not tile.east
        n_tile.west = true
        tile.east = true

        idx = idx_e

        generate_map_route(idx, branch_count - 1, map) if generate_branch
        continue

    elseif rand1 < inv_count * 2 and idx_w
      n_tile = map[idx_w]

      if not n_tile.east and not tile.west
        n_tile.east = true
        tile.west = true

        idx = idx_w

        generate_map_route(idx, branch_count - 1, map) if generate_branch
        continue

    elseif rand1 < inv_count * 3 and idx_s
      n_tile = map[idx_s]

      if not n_tile.north and not tile.south
        n_tile.north = true
        tile.south = true

        idx = idx_s

        generate_map_route(idx, branch_count - 1, map) if generate_branch
        continue

    elseif idx_n
      n_tile = map[idx_n]

      if not n_tile.south and not tile.north
        n_tile.south = true
        tile.north = true

        idx = idx_n

        generate_map_route(idx, branch_count - 1, map) if generate_branch
        continue

    break

generate_map_routes = (start_x, start_y, map) ->
  start_idx = from_2d_to_1d_idx start_x, start_y, MAP_SIZE

  generate_map_route start_idx, 10, map

generate_agents = () ->
  result = {}

  for i = 1, 10
    table.insert result, {
      start_order: i
      source: 0
      destination: 0
      position: vector(0, 0)
    }

  result

tile_pos_to_world = (x, y) ->
  vector(x, y) * TILE_SIZE

calculate_start_time = (a) ->
  a.start_order * 2

update_agent_position = (a, dt) ->
  {:source, :destination, :position} = a

  x_source, y_source = from_1d_to_2d_idx source, MAP_SIZE
  x_dest, y_dest = from_1d_to_2d_idx destination, MAP_SIZE

  source_pos = tile_pos_to_world x_source, y_source
  dest_pos = tile_pos_to_world x_dest, y_dest

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

calculate_agent_destination = (a, map, time) ->
  {:source, :destination} = a

  source_tile = map[source]
  dest_tile = map[destination]

  if source == destination and time > calculate_start_time a
    if destination == 0
      return 1
    else
      neighbors = get_map_tile_neighbor_indices destination, map
      return lume.randomchoice(neighbors) or destination
  else
    return destination

update_agent_destination = (a, map, time) ->
  {:source, :destination, :position} = a

  x_dest, y_dest = from_1d_to_2d_idx destination, MAP_SIZE
  dest_pos = tile_pos_to_world x_dest, y_dest

  dest_dist2 = (dest_pos - position)\len2!

  DIST_THRESHOLD = 5

  if dest_dist2 < DIST_THRESHOLD
    a.source = a.destination

  a.destination = calculate_agent_destination a, map, time

project_to_screen = (x, y) ->
  x + 40, y + 40

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

  love.graphics.setColor 0, 0, 0
  love.graphics.rectangle "line", x0, y0, TILE_SIZE, TILE_SIZE

  love.graphics.setColor 200, 200, 0

  love.graphics.line x1, y1, x1, y0 if tile.north
  love.graphics.line x1, y1, x0, y1 if tile.west
  love.graphics.line x1, y1, x1, y2 if tile.south
  love.graphics.line x1, y1, x2, y1 if tile.east

love.load = ->
  math.randomseed os.time!

  state.map_start_time = love.timer.getTime!
  state.map = generate_map MAP_SIZE
  state.agents = generate_agents!

  generate_map_routes 1, 1, state.map

  love.audio.play AUDIO.play_theme_loop

love.update = (dt) ->
  time = love.timer.getTime! - state.map_start_time

  for a in *state.agents

    update_agent_position a, dt
    update_agent_destination a, state.map, time

love.draw = ->

  for idx, tile in ipairs state.map
    draw_tile idx, tile

  for a in *state.agents
    {:x, :y} = a.position
    x, y = project_to_screen x, y

    love.graphics.setColor 255, 0, 0
    love.graphics.circle "fill", x, y, 7
