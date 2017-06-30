lume = require "lib.lume"

state =
  map: {}
  agents: {}

MAP_SIZE = 10
TILE_SIZE = 30

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
      north: math.random! < 0.5
      west: math.random! < 0.5
      south: math.random! < 0.5
      east: math.random! < 0.5
    }

  result

generate_agents = () ->
  filled_array 10, {
    tile_idx: 0
    source: nil
    destination: nil
    fraction: 0
  }

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

  love.graphics.line x1, y1, x1, y2 if tile.north
  love.graphics.line x1, y1, x0, y1 if tile.west
  love.graphics.line x1, y1, x1, y0 if tile.south
  love.graphics.line x1, y1, x2, y1 if tile.east

love.load = ->
  state.map = generate_map MAP_SIZE
  state.agents = generate_agents!

love.draw = ->

  for idx, tile in ipairs state.map
    draw_tile idx, tile

  for a in *state.agents
    idx = a.tile_idx
    x, y = from_1d_to_2d_idx idx, MAP_SIZE
    x, y = project_to_screen x, y

    love.graphics.setColor 0, 255, 0
    love.graphics.circle "fill", x, y, 3
