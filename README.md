# p5.glsl — a p5.js emulator inside Shadertoy

A single-file GLSL "library" that lets you write p5.js-style sketches that run
entirely in a Shadertoy fragment shader. Every pixel evaluates your `draw()`
call list as signed distance fields, which makes it especially good at the
thing raw GLSL is worst at: **linework**. Strokes are analytically
anti-aliased at any resolution and any stroke weight.

## Use it on Shadertoy

Paste all of [p5.glsl](p5.glsl) into a Shadertoy **Image** tab and edit the
`draw()` function at the bottom. That's it — no buffers, no textures.

## Run it locally

```bash
python3 -m http.server 8123
```

Then open <http://localhost:8123>. `index.html` is a minimal harness that
provides Shadertoy's uniforms (`iResolution`, `iTime`, `iFrame`, `iMouse`)
around the unmodified `p5.glsl`, so the file stays copy-paste compatible.
Shader compile errors show up as an overlay with numbered source.

## How it works

p5's immediate-mode API is a state machine, and that translates surprisingly
directly to GLSL:

- `stroke()`, `fill()`, `strokeWeight()`, `translate()`, `rotate()`,
  `scale()`, `push()`, `pop()` mutate global shader state (colors, weight, an
  inverse transform matrix, and a small state stack).
- Each primitive (`line()`, `circle()`, `bezier()`, …) computes the signed
  distance from the current pixel to the shape, converts it to coverage with a
  1-pixel smoothstep, and alpha-composites it into a canvas accumulator — so
  painter's ordering works exactly like p5.
- Curves (`bezier()`, `arc()`) are flattened to short polylines and rendered
  as distance-to-polyline. `beginShape()`/`vertex()`/`endShape(CLOSE)` uses an
  exact signed polygon distance, so closed shapes can be filled and stroked.

## Supported subset

`background` · `stroke`/`noStroke` · `fill`/`noFill` · `strokeWeight` ·
`line` · `point` · `circle` · `ellipse` · `rect` (with corner radius) ·
`square` · `triangle` · `quad` · `arc` (stroke only) · `bezier` (stroke only) ·
`beginShape`/`vertex`/`endShape([CLOSE])` (≤128 vertices) ·
`push`/`pop`/`translate`/`rotate`/`scale` (uniform scale only) ·
`width` `height` `mouseX` `mouseY` `mouseIsPressed` `frameCount` `millis()`
`map()` `PI` `TWO_PI` `HALF_PI`

Colors are 0–255 like p5. Coordinates are p5's: origin top-left, y down,
positive rotation clockwise.

## Limitations / ideas for later

- Cost is per-pixel: every pixel pays for every primitive drawn, so a sketch
  with thousands of calls will get heavy. Fine for hundreds of segments.
- Non-uniform `scale(x, y)` isn't supported (the SDF math assumes uniform
  scale). `strokeWeight` scales with `scale()`, like p5.
- No `text()`, no images, no blend modes, no `random()`/`noise()` yet — a
  hash-based `random(seed)` and value `noise()` would be easy additions.
- `arc()` and `bezier()` are stroke-only; filled arcs (pie mode) and filled
  bezier shapes would need more SDF work.
- Persistent canvas (p5's no-`background()` trails) could be done with a
  Shadertoy Buffer A that reads its own previous frame.
