lume = require "lib.lume"

love.draw = ->
  msg = [[Hello world! Hello world! Hello world!
    Hello world! Hello world! Hello world! Hello world!
    Hello world! Hello world! Hello world! Hello world!
    Hello world! Hello world! Hello world! Hello world!
    Hello world! Hello world! Hello world! Hello world!
    Hello world! Hello world! Hello world! Hello world!
    Hello world! Hello world! Hello world! Hello world!
    Hello world! Hello world! Hello world! Hello world!]]
  love.graphics.print lume.wordwrap(msg, 20), 400, 300
