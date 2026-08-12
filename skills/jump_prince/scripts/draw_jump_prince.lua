local arg_schema = require("arg_schema")
local delay = require("delay")
local display = require("display")
local system = require("system")

package.path = package.path .. ";/fatfs/skills/jump_prince/scripts/?.lua"
local png = require("jump_prince_png")
local sprites = require("jump_prince_assets")

local TAG = "[jump_prince]"

local MAP_W = 16
local MAP_H = 12
local TILE_SRC = sprites.width or 25
local UI_W = 480
local UI_H = 480
local PLAY_X = 40
local PLAY_Y = 78
local PLAY_W = MAP_W * TILE_SRC
local PLAY_H = MAP_H * TILE_SRC
local CONTROL_PAD_Y = 382
local CONTROL_PAD_H = 98
local LEFT_BUTTON_RIGHT_X = 160
local RIGHT_BUTTON_LEFT_X = 320
local PLAYER_HALF_W = 0.3
local PLAYER_HALF_H = 0.4
local GRAVITY = 30.0
local SPEED = 240.0
local JUMP_STRENGTH = 16.5
local BOUNCE_FACTOR_X = 0.45
local STATE_RUNNING = 1
local PHYSICS_STEP = 1.0 / 60.0
local DISPLAY_RGB565_BYTE_SWAP_COMPENSATION = true

local function display_rgb565_value(value)
  if DISPLAY_RGB565_BYTE_SWAP_COMPENSATION then
    return ((value % 256) * 256) + math.floor(value / 256)
  end
  return value
end

local function rgb565_to_display_hex(value, alpha)
  value = display_rgb565_value(value)

  local r5 = math.floor(value / 2048) % 32
  local g6 = math.floor(value / 32) % 64
  local b5 = value % 32
  local r = math.floor(r5 * 255 / 31)
  local g = math.floor(g6 * 255 / 63)
  local b = math.floor(b5 * 255 / 31)

  if not alpha or alpha >= 255 then
    return string.format("#%02x%02x%02x", r, g, b)
  end
  return string.format("#%02x%02x%02x%02x", r, g, b, alpha)
end

local function color_to_rgb565(color)
  local r = tonumber(color:sub(2, 3), 16) or 0
  local g = tonumber(color:sub(4, 5), 16) or 0
  local b = tonumber(color:sub(6, 7), 16) or 0
  return ((r - (r % 8)) * 256) + ((g - (g % 4)) * 8) + math.floor(b / 8)
end

local function pack_rgb565(value)
  value = display_rgb565_value(value)
  return string.char(value % 256, math.floor(value / 256) % 256)
end

local function pack_panel_color(color)
  return pack_rgb565(color_to_rgb565(color))
end

local function pack_native_rgb565(value)
  return string.char(value % 256, math.floor(value / 256) % 256)
end

local function rgb_to_rgb565(r, g, b)
  return ((r - (r % 8)) * 256) + ((g - (g % 4)) * 8) + math.floor(b / 8)
end

local function panel_color(color)
  if type(color) ~= "string" or color:sub(1, 1) ~= "#" or
      (#color ~= 7 and #color ~= 9) then
    return color
  end
  local alpha = #color == 9 and tonumber(color:sub(8, 9), 16) or 255
  return rgb565_to_display_hex(color_to_rgb565(color), alpha)
end

local SCREEN_BG_COLOR = panel_color("#0f052d")

local raw_args = type(args) == "table" and args or {}

local ARG_SCHEMA = {
  frame_delay_ms = arg_schema.int({ default = 10, min = 16, max = 250 }),
  duration_ms = arg_schema.int({ default = 0, min = 0 }),
  seed = arg_schema.int({ default = 0, min = 0 }),
}

local ctx = arg_schema.parse(raw_args, ARG_SCHEMA)
local display_started = false

local TILEMAPS = {
  { "" },
  {
    "################",
    "#              #",
    "# #### #### #  #",
    "# #    #    #  #",
    "# # ## # ## #  #",
    "# #  # #  #    #",
    "# #### #### #  #",
    "#              #",
    "#              #",
    "#              #",
    "#              #",
    "#########      #",
  },
  {
    "#########      #",
    "#########    ###",
    "########      ##",
    "#######       ##",
    "##########     #",
    "##########     #",
    "########     ###",
    "#######       ##",
    "##########    ##",
    "######        ##",
    "###           ##",
    "###         ####",
  },
  {
    "###         ####",
    "###    #### ####",
    "###         ####",
    "###          ###",
    "#####        ###",
    "###          ###",
    "#            ###",
    "##        ######",
    "##         #####",
    "##         #####",
    "######     #####",
    "#####      #####",
  },
  {
    "#####      #####",
    "###      #######",
    "##        ######",
    "##          ####",
    "######      ####",
    "######       ###",
    "######   #   ###",
    "#####    ##  ###",
    "#####        ###",
    "##           ###",
    "##        ######",
    "##    ##########",
  },
  {
    "##    ##########",
    "##            ##",
    "####          ##",
    "########       #",
    "#####          #",
    "##             #",
    "##       #######",
    "#        #######",
    "#         ######",
    "#####     ######",
    "#####     ######",
    "################",
  },
}

local SCREEN_BUFFER_CACHE = {}

local function clamp(value, min_value, max_value)
  if value < min_value then
    return min_value
  end
  if value > max_value then
    return max_value
  end
  return value
end

local function vec2(x, y)
  return { x = x, y = y }
end

local function vec2_len(v)
  return math.sqrt(v.x * v.x + v.y * v.y)
end

local function vec2_scale(v, scale)
  return vec2(v.x * scale, v.y * scale)
end

local function vec2_normalize(v)
  local len = vec2_len(v)
  if len <= 0.0001 then
    return vec2(0, 0)
  end
  return vec2_scale(v, 1.0 / len)
end

local function cleanup()
  if display_started then
    pcall(display.end_frame)
    pcall(display.deinit)
    display_started = false
  end
end

local function init_display()
  local info, err = display.init()
  if not info then
    error("display.init failed: " .. tostring(err))
  end
  display_started = true
  pcall(display.backlight, true)
end

local function floor_to_int(value)
  return math.floor(value)
end

local function update_screen(game)
  local height_index = floor_to_int(-game.position.y / MAP_H)
  local screen_index = #TILEMAPS - height_index - 2
  if screen_index < 0 or screen_index >= #TILEMAPS then
    screen_index = 0
  end
  game.screen_index = screen_index
  game.map_index = screen_index + 1
  game.screen_offset_y = -(height_index + 1) * MAP_H
end

local function get_tile_from_map(map_index, x, y, full_outside)
  if full_outside then
    if x < 0 or x >= MAP_W or y < 0 or y >= MAP_H then
      return "#"
    end
  else
    if x < 0 or x >= MAP_W then
      return "#"
    end
    if y < 0 or y >= MAP_H then
      return " "
    end
  end

  local map = TILEMAPS[map_index]
  if not map then
    return " "
  end
  local row = map[y + 1] or ""
  local tile = row:sub(x + 1, x + 1)
  return tile == "" and " " or tile
end

local function tile_full_at(game, x, y)
  return get_tile_from_map(game.map_index, x, y, false) == "#"
end

local function tile_full_outside(game, x, y)
  return get_tile_from_map(game.map_index, x, y, true) == "#"
end

local function get_tiles_overlapped(center, size)
  return floor_to_int(center.x - size.x),
      floor_to_int(center.y - size.y),
      floor_to_int(center.x + size.x),
      floor_to_int(center.y + size.y)
end

local function box_colliding_with_tilemap(game, tilemap_height, center, size)
  center = vec2(center.x, center.y - tilemap_height)
  local start_x, start_y, end_x, end_y = get_tiles_overlapped(center, size)

  for x = start_x, end_x do
    for y = start_y, end_y do
      if tile_full_at(game, x, y) then
        local box_pos = vec2(0.5 + x, 0.5 + y)
        local size_sum = vec2(size.x + 0.5, size.y + 0.5)
        local surf_dist = vec2(math.abs(center.x - box_pos.x) - size_sum.x,
            math.abs(center.y - box_pos.y) - size_sum.y)
        if surf_dist.x <= 0 and surf_dist.y <= 0 then
          return true
        end
      end
    end
  end

  return false
end

local function resolve_box_collision(game, tilemap_height, center, velocity, size)
  center.y = center.y - tilemap_height
  local start_x, start_y, end_x, end_y = get_tiles_overlapped(center, size)

  for x = start_x, end_x do
    for y = start_y, end_y do
      if tile_full_at(game, x, y) then
        local box_pos = vec2(0.5 + x, 0.5 + y)
        local size_sum = vec2(size.x + 0.5, size.y + 0.5)
        local surf_dist = vec2(math.abs(center.x - box_pos.x) - size_sum.x,
            math.abs(center.y - box_pos.y) - size_sum.y)
        if surf_dist.x <= 0 and surf_dist.y <= 0 then
          local is_x_empty = not tile_full_at(game, x + (center.x > box_pos.x and 1 or -1), y)
          local is_y_empty = not tile_full_at(game, x, y + (center.y > box_pos.y and 1 or -1))
          if is_x_empty or is_y_empty then
            local clip_x = is_x_empty
            if is_x_empty and is_y_empty then
              clip_x = surf_dist.x > surf_dist.y
            end

            if clip_x then
              if center.x > box_pos.x then
                center.x = box_pos.x + size_sum.x
                if velocity.x < 0 then
                  velocity.x = -velocity.x * BOUNCE_FACTOR_X
                end
              else
                center.x = box_pos.x - size_sum.x
                if velocity.x > 0 then
                  velocity.x = -velocity.x * BOUNCE_FACTOR_X
                end
              end
            else
              if center.y > box_pos.y then
                center.y = box_pos.y + size_sum.y
                if velocity.y < 0 then
                  velocity.y = 0
                end
              else
                center.y = box_pos.y - size_sum.y
                if velocity.y > 0 then
                  velocity.y = 0
                end
              end
            end
          end
        end
      end
    end
  end

  center.y = center.y + tilemap_height
end

local function update_player(game, delta)
  local jump_released = game.prev_input_jump and not game.input_jump

  game.velocity.y = game.velocity.y + GRAVITY * delta
  game.is_on_ground = box_colliding_with_tilemap(game, game.screen_offset_y,
      vec2(game.position.x, game.position.y + PLAYER_HALF_H), vec2(0.1, 0.05))

  if game.is_on_ground then
    game.velocity.x = 0

    if jump_released then
      local jump_strength = clamp(game.jump_hold_time * 2.6, 1.1, 2.0) / 2.0
      local dir = vec2(0, -1)
      local x_move_strength = 0.85 - (jump_strength * 0.45)

      if game.input_right then
        dir.x = dir.x + x_move_strength
        game.is_facing_right = true
      end
      if game.input_left then
        dir.x = dir.x - x_move_strength
        game.is_facing_right = false
      end

      dir = vec2_normalize(dir)
      game.velocity = vec2_scale(dir, jump_strength * JUMP_STRENGTH)
    end

    if game.input_jump then
      game.jump_hold_time = game.jump_hold_time + delta
    else
      game.jump_hold_time = 0
      if game.input_right then
        game.velocity.x = game.velocity.x + SPEED * delta
        game.is_facing_right = true
      end
      if game.input_left then
        game.velocity.x = game.velocity.x - SPEED * delta
        game.is_facing_right = false
      end
    end
  else
    game.jump_hold_time = 0
  end

  local speed = vec2_len(game.velocity)
  if speed > 25 then
    game.velocity = vec2_scale(vec2_normalize(game.velocity), 25)
  end

  game.position.x = game.position.x + game.velocity.x * delta
  game.position.y = game.position.y + game.velocity.y * delta
  game.prev_input_jump = game.input_jump
  game.anim_time = game.anim_time + delta
end

local function game_start()
  local game = {
    position = vec2(8.0, 6.0),
    velocity = vec2(0, 0),
    jump_hold_time = 0,
    anim_time = 0,
    is_on_ground = false,
    is_facing_right = true,
    input_left = false,
    input_right = false,
    input_jump = false,
    prev_input_jump = false,
    screen_index = 1,
    map_index = 2,
    screen_offset_y = 0,
    state = STATE_RUNNING,
    touch_active = false,
    touch_dir = 0,
    active_control = 0,
    release_clear_inputs = false,
    exit_requested = false,
    top_action = nil,
    rendered_once = false,
    rendered_map_index = nil,
    prev_charge_key = nil,
  }
  update_screen(game)
  return game
end

local function restart_game(game)
  local fresh = game_start()
  for key in pairs(game) do
    game[key] = nil
  end
  for key, value in pairs(fresh) do
    game[key] = value
  end
end

local function set_input(game, left, right, jump)
  game.input_left = left
  game.input_right = right
  game.input_jump = jump
end

local function ui_hit(layout, touch, x, y, w, h)
  local ux = (touch.x - layout.x0) / layout.scale
  local uy = (touch.y - layout.y0) / layout.scale
  return ux >= x and ux < x + w and uy >= y and uy < y + h
end

local function update_touch_input(game, layout)
  local t = display.poll_touch()
  if not t then
    return false
  end

  if t.just_pressed and ui_hit(layout, t, 18, 12, 72, 42) then
    game.top_action = "exit"
    return true
  end

  if t.just_pressed and ui_hit(layout, t, 374, 12, 88, 42) then
    game.top_action = "restart"
    return true
  end

  if game.top_action and t.just_released then
    local action = game.top_action
    game.top_action = nil
    if action == "exit" and ui_hit(layout, t, 18, 12, 72, 42) then
      game.exit_requested = true
    elseif action == "restart" and ui_hit(layout, t, 374, 12, 88, 42) then
      restart_game(game)
    end
    return true
  end

  if game.top_action and t.pressed then
    return true
  end

  local ux = (t.x - layout.x0) / layout.scale
  local uy = (t.y - layout.y0) / layout.scale
  local in_control_area = uy >= CONTROL_PAD_Y and uy < CONTROL_PAD_Y + CONTROL_PAD_H
  if t.pressed and in_control_area then
    if t.just_pressed or not game.touch_active then
      local dir = 0
      if ux < LEFT_BUTTON_RIGHT_X then
        dir = -1
      elseif ux > RIGHT_BUTTON_LEFT_X then
        dir = 1
      end
      game.touch_active = true
      game.touch_dir = dir
      game.active_control = dir
    end

    local dir = game.touch_dir
    set_input(game, dir < 0, dir > 0, true)
    return true
  end

  if game.touch_active and (t.just_released or not t.pressed) then
    local dir = game.touch_dir
    game.touch_active = false
    game.active_control = 0
    game.touch_dir = 0
    game.release_clear_inputs = true
    set_input(game, dir < 0, dir > 0, false)
    return true
  end

  return false
end

local function game_update(game, layout, elapsed_ms)
  if game.state ~= STATE_RUNNING then
    return
  end

  local delta = clamp(elapsed_ms / 1000.0, 0.0001, 0.1)
  update_touch_input(game, layout)
  if game.exit_requested then
    return
  end

  local remaining = delta
  while remaining > 0 do
    local step = math.min(remaining, PHYSICS_STEP)
    update_screen(game)
    update_player(game, step)
    resolve_box_collision(game, game.screen_offset_y, game.position, game.velocity,
        vec2(PLAYER_HALF_W, PLAYER_HALF_H))
    update_screen(game)
    remaining = remaining - step
  end

  if game.release_clear_inputs then
    set_input(game, false, false, false)
    game.release_clear_inputs = false
  end
end

local function get_tile_sprite(game, x, y)
  if not tile_full_at(game, x, y) then
    return 1, 1
  end

  local top = tile_full_outside(game, x, y - 1)
  local bottom = tile_full_outside(game, x, y + 1)
  local right = tile_full_outside(game, x + 1, y)
  local left = tile_full_outside(game, x - 1, y)
  local top_right = tile_full_outside(game, x + 1, y - 1)
  local bottom_right = tile_full_outside(game, x + 1, y + 1)
  local top_left = tile_full_outside(game, x - 1, y - 1)
  local bottom_left = tile_full_outside(game, x - 1, y + 1)

  local sx = 1
  local sy = 1
  if top then
    sy = sy + 1
  end
  if bottom then
    sy = sy - 1
  end
  if right then
    sx = sx - 1
  end
  if left then
    sx = sx + 1
  end

  if not top and not bottom and not right and not left then
    sx = 3
    sy = 3
  end
  if not left and not right and sx == 1 then
    sx = 3
  end
  if not top and not bottom and sy == 1 then
    sy = 3
  end

  if sx == 1 and sy == 1 then
    if not top_right and bottom_right and top_left and bottom_left then
      sx = 4
      sy = 2
    end
    if top_right and not bottom_right and top_left and bottom_left then
      sx = 4
      sy = 0
    end
    if top_right and bottom_right and not top_left and bottom_left then
      sx = 6
      sy = 2
    end
    if top_right and bottom_right and top_left and not bottom_left then
      sx = 6
      sy = 0
    end
  end

  return sx + 1, sy + 1
end

local function get_player_sprite(game)
  if game.is_on_ground then
    if game.jump_hold_time > 0.001 then
      return 5
    end
    if math.abs(game.velocity.x) > 0.01 then
      return 2 + (math.floor(game.anim_time * 6.0) % 2)
    end
    return 1
  end

  return game.velocity.y > 0 and 6 or 7
end

local function choose_layout()
  local scale = math.min(display.width / UI_W, display.height / UI_H)
  if scale <= 0 then
    scale = 1
  end
  local ui_w = math.floor(UI_W * scale + 0.5)
  local ui_h = math.floor(UI_H * scale + 0.5)
  return {
    scale = scale,
    pixel_scale = scale,
    tile = math.floor(TILE_SRC * scale + 0.5),
    x0 = math.floor((display.width - ui_w) / 2),
    y0 = math.floor((display.height - ui_h) / 2),
  }
end

local function ui_rect(layout, x, y, w, h)
  local x0 = layout.x0 + math.floor(x * layout.scale + 0.5)
  local y0 = layout.y0 + math.floor(y * layout.scale + 0.5)
  local x1 = layout.x0 + math.floor((x + w) * layout.scale + 0.5)
  local y1 = layout.y0 + math.floor((y + h) * layout.scale + 0.5)
  return x0, y0, math.max(1, x1 - x0), math.max(1, y1 - y0)
end

local function ui_xy(layout, x, y)
  return layout.x0 + math.floor(x * layout.scale + 0.5),
      layout.y0 + math.floor(y * layout.scale + 0.5)
end

local function scaled_rect(layout, x, y, w, h)
  local x0 = math.floor(x * layout.pixel_scale + 0.5)
  local y0 = math.floor(y * layout.pixel_scale + 0.5)
  local x1 = math.floor((x + w) * layout.pixel_scale + 0.5)
  local y1 = math.floor((y + h) * layout.pixel_scale + 0.5)
  local rw = x1 - x0
  local rh = y1 - y0
  if rw < 1 then
    rw = 1
  end
  if rh < 1 then
    rh = 1
  end
  return x0, y0, rw, rh
end

local function load_sheet_data(sheet)
  if sheet.image then
    return sheet.image
  end

  local decoded = png.load(sheet.path)
  if decoded.width ~= sheet.width or decoded.height ~= sheet.height then
    error(string.format("invalid PNG sprite sheet size: %s is %dx%d, expected %dx%d",
        sheet.path, decoded.width, decoded.height, sheet.width, sheet.height))
  end

  sheet.image = decoded
  return sheet.image
end

local function ensure_sprite_data(sprite)
  if sprite.data then
    return sprite.data
  end

  local sheet = sprite.sheet
  if not sheet then
    error("sprite asset is missing a sheet")
  end

  local sheet_image = load_sheet_data(sheet)
  local src_w = sprite.src_width or sprite.width
  local src_h = sprite.src_height or sprite.height
  local channels = sheet_image.channels
  local pixels = sheet_image.pixels
  local rows = {}
  local mask = sprite.opaque and nil or {}

  for y = 0, sprite.height - 1 do
    local source_y = sprite.y + math.floor(y * src_h / sprite.height)
    local row_parts = {}
    local row_runs = {}
    local run_start = nil
    for x = 0, sprite.width - 1 do
      local source_x = math.floor(x * src_w / sprite.width)
      if sprite.flip_x then
        source_x = src_w - 1 - source_x
      end
      source_x = sprite.x + source_x

      local i = (source_y * sheet_image.width + source_x) * channels + 1
      local r = pixels[i] or 0
      local g = pixels[i + 1] or 0
      local b = pixels[i + 2] or 0
      local a = channels == 4 and (pixels[i + 3] or 255) or 255
      row_parts[x + 1] = pack_native_rgb565(rgb_to_rgb565(r, g, b))

      if not sprite.opaque then
        if a >= 128 then
          if not run_start then
            run_start = x
          end
        elseif run_start then
          row_runs[#row_runs + 1] = { run_start, x - run_start }
          run_start = nil
        end
      end
    end
    if run_start then
      row_runs[#row_runs + 1] = { run_start, sprite.width - run_start }
    end
    if mask then
      mask[y + 1] = row_runs
    end
    rows[y + 1] = table.concat(row_parts)
  end

  if mask then
    sprite.mask = mask
  end
  sprite.data = table.concat(rows)
  return sprite.data
end

local function sprite_is_opaque(sprite, x, y)
  if sprite.opaque then
    return true
  end
  local row = sprite.mask and sprite.mask[y + 1]
  if not row then
    return false
  end
  for _, run in ipairs(row) do
    if x >= run[1] and x < run[1] + run[2] then
      return true
    end
  end
  return false
end

local function release_sheet_images()
  for _, sheet in pairs(sprites.sheets or {}) do
    sheet.image = nil
  end
  collectgarbage("collect")
end

local function preload_sprite_data()
  for _, frames in pairs(sprites.players or {}) do
    for _, sprite in ipairs(frames) do
      ensure_sprite_data(sprite)
    end
  end

  for _, col in ipairs(sprites.tiles or {}) do
    for _, sprite in ipairs(col) do
      ensure_sprite_data(sprite)
    end
  end

  release_sheet_images()
end

local function sprite_pixel(image, pixel_index)
  local data = ensure_sprite_data(image)
  local width = image.width or sprites.width
  local height = image.height or sprites.height
  if pixel_index < 0 or pixel_index >= width * height then
    return nil
  end

  local x = pixel_index % width
  local y = math.floor(pixel_index / width)
  if not sprite_is_opaque(image, x, y) then
    return nil
  end

  local color_index = pixel_index * 2 + 1
  local lo = data:byte(color_index) or 0
  local hi = data:byte(color_index + 1) or 0
  return lo + hi * 256, 255
end

local function native_alpha_plane_color(image, pixel_index)
  local color, alpha = sprite_pixel(image, pixel_index)
  if not color then
    return nil
  end
  return rgb565_to_display_hex(color, alpha)
end

local function sprite_raw_rows(image, fallback_pixel)
  if image._raw_rows then
    return image._raw_rows
  end

  local rows = {}
  local width = image.width or sprites.width
  local height = image.height or sprites.height

  for y = 0, height - 1 do
    local parts = {}
    for x = 0, width - 1 do
      local color = sprite_pixel(image, y * width + x)
      parts[x + 1] = color and pack_rgb565(color) or fallback_pixel
    end
    rows[y + 1] = table.concat(parts)
  end

  image._raw_rows = rows
  return rows
end

local function sprite_runs(image)
  if image._runs then
    return image._runs
  end

  local runs = {}
  local width = image.width or sprites.width
  local height = image.height or sprites.height
  local out = 1

  for y = 0, height - 1 do
    local x = 0
    while x < width do
      local pixel_index = y * width + x
      local color = native_alpha_plane_color(image, pixel_index)
      if not color then
        x = x + 1
      else
        local start_x = x
        x = x + 1
        while x < width do
          local next_index = y * width + x
          if native_alpha_plane_color(image, next_index) ~= color then
            break
          end
          x = x + 1
        end
        runs[out] = { start_x, y, x - start_x, color }
        out = out + 1
      end
    end
  end

  image._runs = runs
  return runs
end

local function draw_sprite(layout, origin_x, origin_y, image)
  for _, run in ipairs(sprite_runs(image)) do
    local x, y, w, h = scaled_rect(layout, run[1], run[2], run[3], 1)
    display.fill_rect(origin_x + x, origin_y + y, w, h, run[4])
  end
end

local function draw_ui_text(layout, x, y, w, h, text, font_size, color)
  if not display.draw_text_aligned then
    return
  end

  local rx, ry, rw, rh = ui_rect(layout, x, y, w, h)
  local size = math.max(1, math.floor(font_size * layout.scale + 0.5))
  display.draw_text_aligned(rx, ry, rw, rh, text, {
    color = panel_color(color),
    font_size = size,
    align = "center",
    valign = "middle",
  })
end

local function draw_ui_label(layout, x, y, text, font_size, color)
  if not display.draw_text then
    return
  end

  local tx, ty = ui_xy(layout, x, y)
  local size = math.max(1, math.floor(font_size * layout.scale + 0.5))
  display.draw_text(tx, ty, text, {
    color = panel_color(color),
    font_size = size,
  })
end

local function draw_ui_button(layout, x, y, w, h, label, color)
  local sx, sy, sw, sh = ui_rect(layout, x + 2, y + 3, w, h)
  local bx, by, bw, bh = ui_rect(layout, x, y, w, h)
  local radius = math.max(1, math.floor(8 * layout.scale + 0.5))
  local border = math.max(1, math.floor(2 * layout.scale + 0.5))

  if display.fill_round_rect then
    display.fill_round_rect(sx, sy, sw, sh, radius, panel_color("#00000078"))
    display.fill_round_rect(bx, by, bw, bh, radius, panel_color(color))
  else
    display.fill_rect(sx, sy, sw, sh, panel_color("#00000078"))
    display.fill_rect(bx, by, bw, bh, panel_color(color))
  end
  if display.draw_round_rect then
    display.draw_round_rect(bx, by, bw, bh, radius, panel_color("#000000"))
    if border > 1 then
      display.draw_round_rect(bx + 1, by + 1, math.max(1, bw - 2), math.max(1, bh - 2), math.max(1, radius - 1), panel_color("#000000"))
    end
  end
  draw_ui_text(layout, x, y, w, h, label, 20, "#111111")
end

local function draw_charge_slot(layout, x, active_width)
  local bx, by, bw, bh = ui_rect(layout, x, 388, 76, 8)
  local radius = math.max(1, math.floor(4 * layout.scale + 0.5))
  if display.fill_round_rect then
    display.fill_round_rect(bx, by, bw, bh, radius, panel_color("#352b69"))
  else
    display.fill_rect(bx, by, bw, bh, panel_color("#352b69"))
  end

  if active_width > 0 then
    local ax, ay, aw, ah = ui_rect(layout, x, 388, active_width, 8)
    if display.fill_round_rect then
      display.fill_round_rect(ax, ay, aw, ah, radius, panel_color("#f7c35f"))
    else
      display.fill_rect(ax, ay, aw, ah, panel_color("#f7c35f"))
    end
  end
end

local function charge_ui_state(game)
  local charge = game.input_jump and clamp(game.jump_hold_time * 2.6, 0, 2.0) / 2.0 or 0
  local charge_w = math.floor(charge * 70.0)
  local active_bar = game.input_left and 1 or (game.input_right and 3 or 2)
  return active_bar, charge_w
end

local function charge_ui_key(game)
  local active_bar, charge_w = charge_ui_state(game)
  return tostring(active_bar) .. ":" .. tostring(charge_w)
end

local function draw_static_ui_base(layout, game)
  draw_ui_text(layout, 0, 14, 480, 34, "Jump Prince", 28, "#fefdf9")
  draw_ui_label(layout, 196, 50, "Stage " .. tostring(game.screen_index), 18, "#d8f5a2")

  draw_ui_button(layout, 18, 12, 72, 42, "Exit", "#fefdf9")
  draw_ui_button(layout, 374, 12, 88, 42, "Restart", "#dfe7fc")
  draw_ui_button(layout, 40, 400, 96, 58, "Left", "#c7f0bd")
  draw_ui_button(layout, 192, 400, 96, 58, "Jump", "#f8dfa5")
  draw_ui_button(layout, 344, 400, 96, 58, "Right", "#c7f0bd")
end

local function draw_charge_ui(layout, game)
  local active_bar, charge_w = charge_ui_state(game)
  local xs = { 50, 202, 354 }
  for i = 1, 3 do
    draw_charge_slot(layout, xs[i], i == active_bar and charge_w or 0)
  end
end

local function draw_static_ui(layout, game)
  draw_static_ui_base(layout, game)
  draw_charge_ui(layout, game)
end

local function map_tile_rows(image)
  local empty_image = sprites.tiles[2][2]
  local fallback_pixel = pack_panel_color("#180e45")
  if image == empty_image then
    return sprite_raw_rows(empty_image, fallback_pixel)
  end
  if image._map_rows then
    return image._map_rows
  end

  local empty_rows = sprite_raw_rows(empty_image, fallback_pixel)
  local width = image.width or sprites.width
  local height = image.height or sprites.height
  local rows = {}

  for y = 0, height - 1 do
    local parts = {}
    for x = 0, width - 1 do
      local color = sprite_pixel(image, y * width + x)
      if color then
        parts[x + 1] = pack_rgb565(color)
      else
        local byte_index = x * 2 + 1
        parts[x + 1] = empty_rows[y + 1]:sub(byte_index, byte_index + 1)
      end
    end
    rows[y + 1] = table.concat(parts)
  end

  image._map_rows = rows
  return rows
end

local function screen_buffer_for(map_index)
  if SCREEN_BUFFER_CACHE[map_index] then
    return SCREEN_BUFFER_CACHE[map_index]
  end

  local map_game = {
    map_index = map_index,
  }
  local empty_image = sprites.tiles[2][2]
  local rows = {}

  for tile_y = 0, MAP_H - 1 do
    local tile_rows = {}
    for tile_x = 0, MAP_W - 1 do
      local image = empty_image
      if tile_full_at(map_game, tile_x, tile_y) then
        local sx, sy = get_tile_sprite(map_game, tile_x, tile_y)
        image = sprites.tiles[sx][sy]
      end
      tile_rows[tile_x + 1] = map_tile_rows(image)
    end

    for pixel_y = 1, TILE_SRC do
      local row_parts = {}
      for tile_x = 1, MAP_W do
        row_parts[tile_x] = tile_rows[tile_x][pixel_y]
      end
      rows[#rows + 1] = table.concat(row_parts)
    end
  end

  SCREEN_BUFFER_CACHE[map_index] = table.concat(rows)
  return SCREEN_BUFFER_CACHE[map_index]
end

local function draw_map_slow(layout, game)
  local px, py, pw, ph = ui_rect(layout, PLAY_X, PLAY_Y, PLAY_W, PLAY_H)
  display.fill_rect(px, py, pw, ph, SCREEN_BG_COLOR)
  local empty_image = sprites.tiles[2][2]
  for y = 0, MAP_H - 1 do
    for x = 0, MAP_W - 1 do
      local ox, oy = ui_xy(layout, PLAY_X + x * TILE_SRC, PLAY_Y + y * TILE_SRC)
      draw_sprite(layout, ox, oy, empty_image)
      if tile_full_at(game, x, y) then
        local sx, sy = get_tile_sprite(game, x, y)
        local image = sprites.tiles[sx][sy]
        draw_sprite(layout, ox, oy, image)
      end
    end
  end
end

local function player_draw_rect(layout, game)
  local player_x = game.position.x
  local player_y = game.position.y - game.screen_offset_y
  local map_x = math.floor(player_x * TILE_SRC - TILE_SRC / 2 + 0.5)
  local map_y = math.floor(player_y * TILE_SRC - (TILE_SRC * 10) / 16 + 0.5)
  local x, y = ui_xy(layout, PLAY_X + player_x * TILE_SRC - TILE_SRC / 2,
      PLAY_Y + player_y * TILE_SRC - (TILE_SRC * 10) / 16)
  return {
    x = x,
    y = y,
    map_x = map_x,
    map_y = map_y,
  }
end

local function draw_player(layout, game, rect)
  local direction = game.is_facing_right and "right" or "left"
  local frame = get_player_sprite(game)
  local image = sprites.players[direction][frame]
  rect = rect or player_draw_rect(layout, game)
  draw_sprite(layout, rect.x, rect.y, image)
  return rect
end

local function refresh_buffer_for(game, player_rect)
  local screen_buffer = screen_buffer_for(game.map_index)
  local direction = game.is_facing_right and "right" or "left"
  local frame = get_player_sprite(game)
  local image = sprites.players[direction][frame]
  local x0 = clamp(player_rect.map_x, 0, PLAY_W)
  local y0 = clamp(player_rect.map_y, 0, PLAY_H)
  local x1 = clamp(player_rect.map_x + TILE_SRC, 0, PLAY_W)
  local y1 = clamp(player_rect.map_y + TILE_SRC, 0, PLAY_H)
  if x0 >= x1 or y0 >= y1 then
    return screen_buffer
  end

  local row_bytes = PLAY_W * 2
  local parts = {}
  local top_bytes = y0 * row_bytes
  if top_bytes > 0 then
    parts[#parts + 1] = screen_buffer:sub(1, top_bytes)
  end

  for y = y0, y1 - 1 do
    local row_start = y * row_bytes + 1
    local left_bytes = x0 * 2
    if left_bytes > 0 then
      parts[#parts + 1] = screen_buffer:sub(row_start, row_start + left_bytes - 1)
    end

    for x = x0, x1 - 1 do
      local sprite_x = x - player_rect.map_x
      local sprite_y = y - player_rect.map_y
      local fg = sprite_pixel(image, sprite_y * TILE_SRC + sprite_x)
      local bg_index = row_start + x * 2
      parts[#parts + 1] = fg and pack_rgb565(fg) or
          screen_buffer:sub(bg_index, bg_index + 1)
    end

    local right_start = row_start + x1 * 2
    local row_end = row_start + row_bytes - 1
    if right_start <= row_end then
      parts[#parts + 1] = screen_buffer:sub(right_start, row_end)
    end
  end

  local bottom_start = y1 * row_bytes + 1
  if bottom_start <= #screen_buffer then
    parts[#parts + 1] = screen_buffer:sub(bottom_start)
  end
  return table.concat(parts)
end

local function draw_refresh_buffer(layout, buffer)
  local px, py = ui_xy(layout, PLAY_X, PLAY_Y)
  display.draw_pixels(px, py, buffer, {
    width = PLAY_W,
    height = PLAY_H,
    format = "rgb565",
  })
end

local function draw_scene(layout, game)
  if not display.draw_pixels or math.abs(layout.scale - 1.0) > 0.001 then
    display.begin_frame({ clear = true, color = SCREEN_BG_COLOR, preserve = false })
    draw_static_ui(layout, game)
    draw_map_slow(layout, game)
    draw_player(layout, game)
    display.present()
    display.end_frame()
    return
  end

  local charge_key = charge_ui_key(game)
  local full_redraw = not game.rendered_once or game.rendered_map_index ~= game.map_index
  local current_player_rect = player_draw_rect(layout, game)
  local refresh_buffer = refresh_buffer_for(game, current_player_rect)

  if full_redraw then
    display.begin_frame({ clear = true, color = SCREEN_BG_COLOR, preserve = false })
    draw_static_ui_base(layout, game)
    draw_charge_ui(layout, game)
  else
    display.begin_frame({ clear = false, preserve = false })
    if game.prev_charge_key ~= charge_key then
      draw_charge_ui(layout, game)
    end
  end

  draw_refresh_buffer(layout, refresh_buffer)
  game.rendered_once = true
  game.rendered_map_index = game.map_index
  game.prev_charge_key = charge_key
  display.present()
  display.end_frame()
end

local function timed_out(start_ms)
  if ctx.duration_ms <= 0 then
    return false
  end
  return system.millis() - start_ms >= ctx.duration_ms
end

local function run()
  init_display()
  local seed = ctx.seed
  if seed == 0 then
    seed = math.floor(system.time() + system.millis())
  end
  math.randomseed(seed)

  local game = game_start()
  local layout = choose_layout()
  preload_sprite_data()
  local start_ms = system.millis()
  local last_ms = start_ms

  print(string.format("%s start display=%dx%d ui=%dx%d scale=%.3f",
      TAG, display.width, display.height, UI_W, UI_H, layout.scale))

  while not timed_out(start_ms) do
    local now = system.millis()
    local elapsed = now - last_ms
    if elapsed <= 0 then
      elapsed = ctx.frame_delay_ms
    end
    last_ms = now

    game_update(game, layout, elapsed)
    if game.exit_requested then
      break
    end
    draw_scene(layout, game)
    delay.delay_ms(ctx.frame_delay_ms)
  end
end

local ok, err = xpcall(run, debug.traceback)
cleanup()
if not ok then
  print(TAG .. " ERROR: " .. tostring(err))
  error(err)
end

print(TAG .. " done")
