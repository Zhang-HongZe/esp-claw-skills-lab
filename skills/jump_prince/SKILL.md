---
{
  "name": "jump_prince",
  "description": "Show the Jump Prince platform game on the board display with the original factory_demo maps, physics, and sprites. Use when the user asks to play, show, draw, or demo Jump Prince.",
  "metadata": {
    "cap_groups": [
      "cap_lua"
    ],
    "manage_mode": "readonly",
    "category": ["game", "ui"]
  },
  "simulator": {
    "entry": "scripts/draw_jump_prince.lua",
    "files": [
      "scripts/draw_jump_prince.lua",
      "scripts/jump_prince_png.lua",
      "scripts/jump_prince_assets.lua",
      "scripts/tilemap.png",
      "scripts/player.png"
    ]
  }
}
---

# Jump Prince

Use this skill when the user asks to play, show, draw, or demo Jump Prince on the screen.

Run the bundled Lua script with `lua_run_script_async` for normal display use:

```json
{"path":"{CUR_SKILL_DIR}/scripts/draw_jump_prince.lua","args":{},"name":"jump_prince","exclusive":"display","replace":true,"log_bytes":2048}
```

The script ports the factory_demo Jump Prince game into a self-contained Lua display skill. It keeps the original 480 x 480 Jump Prince screen layout, 16 x 12 tile maps, jump/gravity/collision behavior, player animation selection, and tile sprite selection. The sprite assets are converted directly from the factory_demo `ui_img_jump_prince_*_data` C arrays into Lua arrays and decoded at draw time. It uses `display.poll_touch()` from the existing display module for touch controls and does not modify any shared Lua module code.

Touch follows the original factory_demo control pad: `x < 160` is left, `x > 320` is right, and the middle zone is a vertical jump. Hold a zone to charge the jump, then release to jump. The script also draws the original title, Exit/Restart buttons, Stage label, play area, charge bars, and Left/Jump/Right buttons at their factory_demo coordinates.

If script execution returns an error, report that error directly to the user.

## Script Args Schema

```json
{
  "type": "object",
  "properties": {
    "frame_delay_ms": {
      "type": "integer",
      "default": 33,
      "minimum": 16,
      "maximum": 250,
      "description": "Delay between game frames."
    },
    "duration_ms": {
      "type": "integer",
      "default": 0,
      "minimum": 0,
      "description": "How long to run. Use 0 to continue until stopped or replaced."
    },
    "seed": {
      "type": "integer",
      "default": 0,
      "minimum": 0,
      "description": "Use 0 to seed from local time."
    }
  }
}
```

## Tool Call Inputs

Start Jump Prince with defaults:

```json
{"path":"{CUR_SKILL_DIR}/scripts/draw_jump_prince.lua","args":{},"name":"jump_prince","exclusive":"display","replace":true,"log_bytes":2048}
```

Run Jump Prince for one minute:

```json
{"path":"{CUR_SKILL_DIR}/scripts/draw_jump_prince.lua","args":{"duration_ms":60000},"name":"jump_prince","exclusive":"display","replace":true,"log_bytes":2048}
```

## Recommended Flow

1. Use `lua_run_script_async` with `name: "jump_prince"`, `exclusive: "display"`, and `replace: true`.
2. Use default args unless the user asks for a duration.
3. Leave `duration_ms` as `0` for a Jump Prince demo that keeps running until stopped or replaced.
4. Report the async job start result or script error directly to the user.
