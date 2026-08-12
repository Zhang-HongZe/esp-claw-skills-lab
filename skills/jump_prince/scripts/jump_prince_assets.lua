local BASE = "/fatfs/skills/jump_prince/scripts"

local M = {
  width = 25,
  height = 25,
}

M.sheets = {
  tiles = { path = BASE .. "/tilemap.png", width = 112, height = 96 },
  player = { path = BASE .. "/player.png", width = 112, height = 16 },
}

M.players = {
  right = {},
  left = {},
}

for i = 0, 6 do
  M.players.right[i + 1] = {
    sheet = M.sheets.player,
    x = i * 16,
    y = 0,
    src_width = 16,
    src_height = 16,
    width = M.width,
    height = M.height,
  }
  M.players.left[i + 1] = {
    sheet = M.sheets.player,
    x = i * 16,
    y = 0,
    src_width = 16,
    src_height = 16,
    width = M.width,
    height = M.height,
    flip_x = true,
  }
end

M.tiles = {}
for tx = 0, 6 do
  local col = {}
  for ty = 0, 5 do
    col[ty + 1] = {
      sheet = M.sheets.tiles,
      x = tx * 16,
      y = ty * 16,
      src_width = 16,
      src_height = 16,
      width = M.width,
      height = M.height,
      opaque = true,
    }
  end
  M.tiles[tx + 1] = col
end

return M
