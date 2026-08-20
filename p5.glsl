// ======================================================================
// p5.glsl — a tiny p5.js emulator that runs entirely inside a Shadertoy
// fragment shader.
//
// Paste this whole file into a Shadertoy "Image" tab and edit draw()
// at the bottom. Every pixel evaluates your sketch as signed distance
// fields, so all linework is analytically anti-aliased.
//
// Supported subset:
//   background(g | r,g,b)                    colors are 0..255, p5-style
//   stroke(g | r,g,b | r,g,b,a)  noStroke()
//   fill(g | r,g,b | r,g,b,a)    noFill()
//   strokeWeight(w)
//   line(x1,y1,x2,y2)  point(x,y)
//   circle(x,y,d)  ellipse(x,y,w,h)
//   rect(x,y,w,h[,r])  square(x,y,s)
//   triangle(...)  quad(...)
//   arc(x,y,w,h,start,stop)                  stroke only (OPEN mode)
//   bezier(x1,y1, cx1,cy1, cx2,cy2, x2,y2)   stroke only
//   beginShape() vertex(x,y) endShape([CLOSE])   up to 128 vertices
//   push() pop() translate(x,y) rotate(a) scale(s)   uniform scale only
//   width height mouseX mouseY mouseIsPressed frameCount millis() map()
//   PI TWO_PI HALF_PI
//
// Coordinate system matches p5: origin top-left, y down, angles in
// radians, positive rotation is clockwise.
// ======================================================================

const float PI      = 3.14159265358979;
const float TWO_PI  = 6.28318530717959;
const float HALF_PI = 1.57079632679490;
const int   CLOSE   = 1;

// ---------------------------- state -----------------------------------
vec2  _P;                 // this pixel, in p5 coords (y down)
vec3  _canvas;            // accumulated color
vec4  _strokeCol, _fillCol;
float _sw;
bool  _doStroke, _doFill;
mat3  _inv;               // inverse of the current transform
float _k;                 // current uniform scale factor

const int _STACK = 10;
mat3  _sInv[_STACK]; float _sK[_STACK];
vec4  _sSC[_STACK], _sFC[_STACK]; float _sSW[_STACK];
bool  _sDS[_STACK], _sDF[_STACK];
int   _sp = 0;

const int _MAXV = 128;
vec2 _verts[_MAXV]; int _vn = 0;

float width, height, mouseX, mouseY, frameCount;
bool  mouseIsPressed;
float _t;

// --------------------------- internals --------------------------------
vec2 _q() { return (_inv * vec3(_P, 1.0)).xy; }

// alpha-composite a primitive; d is signed distance in screen pixels
void _blend(vec4 c, float d) {
    float a = c.a * smoothstep(0.5, -0.5, d);
    _canvas = mix(_canvas, c.rgb, a);
}

void _shape(float d) {                     // fill first, stroke on top
    if (_doFill)   _blend(_fillCol, d);
    if (_doStroke) _blend(_strokeCol, abs(d) - 0.5 * _sw * _k);
}

void _strokeD(float d) {                   // unsigned distance -> stroke
    if (_doStroke) _blend(_strokeCol, d - 0.5 * _sw * _k);
}

float _sdSeg(vec2 p, vec2 a, vec2 b) {
    vec2 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-8), 0.0, 1.0);
    return length(pa - ba * h);
}

float _sdTri(vec2 p, vec2 p0, vec2 p1, vec2 p2) {
    vec2 e0 = p1 - p0, e1 = p2 - p1, e2 = p0 - p2;
    vec2 v0 = p - p0,  v1 = p - p1,  v2 = p - p2;
    vec2 pq0 = v0 - e0 * clamp(dot(v0, e0) / dot(e0, e0), 0.0, 1.0);
    vec2 pq1 = v1 - e1 * clamp(dot(v1, e1) / dot(e1, e1), 0.0, 1.0);
    vec2 pq2 = v2 - e2 * clamp(dot(v2, e2) / dot(e2, e2), 0.0, 1.0);
    float s = sign(e0.x * e2.y - e0.y * e2.x);
    vec2 d = min(min(vec2(dot(pq0, pq0), s * (v0.x * e0.y - v0.y * e0.x)),
                     vec2(dot(pq1, pq1), s * (v1.x * e1.y - v1.y * e1.x))),
                     vec2(dot(pq2, pq2), s * (v2.x * e2.y - v2.y * e2.x)));
    return -sqrt(d.x) * sign(d.y);
}

// signed distance to the closed polygon in _verts[0.._vn)
float _sdPoly(vec2 p) {
    float d = dot(p - _verts[0], p - _verts[0]);
    float s = 1.0;
    for (int i = 0; i < _vn; i++) {
        int j = (i == 0) ? _vn - 1 : i - 1;
        vec2 e = _verts[j] - _verts[i];
        vec2 w = p - _verts[i];
        vec2 b = w - e * clamp(dot(w, e) / dot(e, e), 0.0, 1.0);
        d = min(d, dot(b, b));
        bvec3 c = bvec3(p.y >= _verts[i].y, p.y < _verts[j].y,
                        e.x * w.y > e.y * w.x);
        if (all(c) || all(not(c))) s *= -1.0;
    }
    return s * sqrt(d);
}

vec2 _bezPt(vec2 a, vec2 b, vec2 c, vec2 d, float t) {
    float u = 1.0 - t;
    return u*u*u*a + 3.0*u*u*t*b + 3.0*u*t*t*c + t*t*t*d;
}

// ------------------------- color & style ------------------------------
void background(float r, float g, float b) { _canvas = vec3(r, g, b) / 255.0; }
void background(float g)                   { background(g, g, g); }

void stroke(float r, float g, float b, float a) {
    _strokeCol = vec4(vec3(r, g, b) / 255.0, a / 255.0); _doStroke = true;
}
void stroke(float r, float g, float b) { stroke(r, g, b, 255.0); }
void stroke(float g)                   { stroke(g, g, g, 255.0); }
void noStroke()                        { _doStroke = false; }

void fill(float r, float g, float b, float a) {
    _fillCol = vec4(vec3(r, g, b) / 255.0, a / 255.0); _doFill = true;
}
void fill(float r, float g, float b) { fill(r, g, b, 255.0); }
void fill(float g)                   { fill(g, g, g, 255.0); }
void noFill()                        { _doFill = false; }

void strokeWeight(float w) { _sw = w; }

// -------------------------- transforms --------------------------------
void translate(float x, float y) {
    _inv = mat3(1, 0, 0,  0, 1, 0,  -x, -y, 1) * _inv;
}
void rotate(float a) {
    float c = cos(a), s = sin(a);
    _inv = mat3(c, -s, 0,  s, c, 0,  0, 0, 1) * _inv;
}
void scale(float s) {
    _inv = mat3(1.0/s, 0, 0,  0, 1.0/s, 0,  0, 0, 1) * _inv;
    _k *= s;
}
void push() {
    if (_sp < _STACK) {
        _sInv[_sp] = _inv; _sK[_sp] = _k;
        _sSC[_sp] = _strokeCol; _sFC[_sp] = _fillCol; _sSW[_sp] = _sw;
        _sDS[_sp] = _doStroke;  _sDF[_sp] = _doFill;
        _sp++;
    }
}
void pop() {
    if (_sp > 0) {
        _sp--;
        _inv = _sInv[_sp]; _k = _sK[_sp];
        _strokeCol = _sSC[_sp]; _fillCol = _sFC[_sp]; _sw = _sSW[_sp];
        _doStroke = _sDS[_sp];  _doFill = _sDF[_sp];
    }
}

// -------------------------- primitives --------------------------------
void line(float x1, float y1, float x2, float y2) {
    if (!_doStroke) return;
    _strokeD(_sdSeg(_q(), vec2(x1, y1), vec2(x2, y2)) * _k);
}

void point(float x, float y) {
    if (!_doStroke) return;
    _blend(_strokeCol, (length(_q() - vec2(x, y))) * _k - 0.5 * _sw * _k);
}

void circle(float x, float y, float d) {
    _shape((length(_q() - vec2(x, y)) - 0.5 * d) * _k);
}

void ellipse(float x, float y, float w, float h) {
    vec2 p = _q() - vec2(x, y);
    vec2 r = vec2(w, h) * 0.5;
    _shape((length(p / r) - 1.0) * min(r.x, r.y) * _k);
}

void rect(float x, float y, float w, float h, float r) {
    vec2 p = _q() - (vec2(x, y) + 0.5 * vec2(w, h));
    vec2 b = 0.5 * vec2(w, h) - r;
    vec2 dv = abs(p) - b;
    _shape((length(max(dv, 0.0)) + min(max(dv.x, dv.y), 0.0) - r) * _k);
}
void rect(float x, float y, float w, float h) { rect(x, y, w, h, 0.0); }
void square(float x, float y, float s)        { rect(x, y, s, s, 0.0); }

void triangle(float x1, float y1, float x2, float y2, float x3, float y3) {
    _shape(_sdTri(_q(), vec2(x1, y1), vec2(x2, y2), vec2(x3, y3)) * _k);
}

void quad(float x1, float y1, float x2, float y2,
          float x3, float y3, float x4, float y4) {
    _verts[0] = vec2(x1, y1); _verts[1] = vec2(x2, y2);
    _verts[2] = vec2(x3, y3); _verts[3] = vec2(x4, y4);
    _vn = 4;
    _shape(_sdPoly(_q()) * _k);
    _vn = 0;
}

void arc(float x, float y, float w, float h, float a0, float a1) {
    if (!_doStroke) return;
    vec2 q = _q(), c = vec2(x, y), r = vec2(w, h) * 0.5;
    vec2 prev = c + r * vec2(cos(a0), sin(a0));
    float dmin = 1e6;
    for (int i = 1; i <= 32; i++) {
        float a = mix(a0, a1, float(i) / 32.0);
        vec2 pt = c + r * vec2(cos(a), sin(a));
        dmin = min(dmin, _sdSeg(q, prev, pt));
        prev = pt;
    }
    _strokeD(dmin * _k);
}

void bezier(float x1, float y1, float cx1, float cy1,
            float cx2, float cy2, float x2, float y2) {
    if (!_doStroke) return;
    vec2 q = _q();
    vec2 a = vec2(x1, y1), b = vec2(cx1, cy1);
    vec2 c = vec2(cx2, cy2), d = vec2(x2, y2);
    vec2 prev = a;
    float dmin = 1e6;
    for (int i = 1; i <= 24; i++) {
        vec2 pt = _bezPt(a, b, c, d, float(i) / 24.0);
        dmin = min(dmin, _sdSeg(q, prev, pt));
        prev = pt;
    }
    _strokeD(dmin * _k);
}

void beginShape() { _vn = 0; }
void vertex(float x, float y) { if (_vn < _MAXV) _verts[_vn++] = vec2(x, y); }
void endShape(int mode) {
    if (_vn < 2) return;
    vec2 q = _q();
    if (mode == CLOSE) {
        _shape(_sdPoly(q) * _k);
    } else {
        float d = 1e6;
        for (int i = 0; i < _vn - 1; i++)
            d = min(d, _sdSeg(q, _verts[i], _verts[i + 1]));
        _strokeD(d * _k);
    }
    _vn = 0;
}
void endShape() { endShape(0); }

// ---------------------------- utils -----------------------------------
float millis() { return _t * 1000.0; }
float map(float v, float a, float b, float c, float d) {
    return c + (d - c) * (v - a) / (b - a);
}

// --------------------------- runtime ----------------------------------
void draw();

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    width  = iResolution.x;
    height = iResolution.y;
    _P = vec2(fragCoord.x, iResolution.y - fragCoord.y);   // y-down, p5-style
    _t = iTime;
    frameCount = float(iFrame);
    mouseIsPressed = iMouse.z > 0.0;
    if (iMouse.x <= 0.0 && iMouse.y <= 0.0) {              // never clicked yet
        mouseX = width * 0.5; mouseY = height * 0.5;
    } else {
        mouseX = iMouse.x; mouseY = height - iMouse.y;
    }

    _canvas    = vec3(200.0 / 255.0);
    _strokeCol = vec4(0, 0, 0, 1);
    _fillCol   = vec4(1);
    _sw = 1.0; _doStroke = true; _doFill = true;
    _inv = mat3(1.0); _k = 1.0; _sp = 0; _vn = 0;

    draw();

    fragColor = vec4(_canvas, 1.0);
}

// ======================================================================
// YOUR SKETCH — plain p5, but every pixel runs it on the GPU
// ======================================================================
void draw() {
    background(14.0, 15.0, 20.0);
    float t = millis() / 1000.0;
    float cx = width * 0.5, cy = height * 0.5;
    float R = min(width, height) * 0.40;

    // clock-face ticks: push/translate/rotate state machine
    push();
    translate(cx, cy);
    rotate(t * 0.08);
    stroke(255.0, 255.0, 255.0, 70.0);
    strokeWeight(1.5);
    for (int i = 0; i < 60; i++) {
        rotate(TWO_PI / 60.0);
        line(R * 0.94, 0.0, R * 1.02, 0.0);
    }
    pop();

    // bezier fan, breathing
    stroke(255.0, 130.0, 100.0, 160.0);
    strokeWeight(1.5);
    for (int i = 0; i < 9; i++) {
        float f = float(i) / 8.0;
        float w = sin(t * 0.9 + f * 4.0) * R * 0.8;
        bezier(cx - R, cy + R * 0.55,
               cx - R * 0.35, cy - w,
               cx + R * 0.35, cy + w,
               cx + R, cy - R * 0.55);
    }

    // Lissajous ribbon: closed 64-gon through beginShape/vertex
    stroke(110.0, 210.0, 255.0);
    strokeWeight(2.5);
    noFill();
    beginShape();
    for (int i = 0; i < 128; i++) {
        float u = float(i) / 128.0 * TWO_PI;
        vertex(cx + R * 0.82 * sin(2.0 * u + t * 0.6),
               cy + R * 0.82 * sin(3.0 * u));
    }
    endShape(CLOSE);

    // orbiting filled shapes: fill + stroke compositing
    push();
    translate(cx, cy);
    rotate(-t * 0.3);
    fill(255.0, 205.0, 90.0);
    stroke(14.0, 15.0, 20.0);
    strokeWeight(3.0);
    circle(R * 0.94, 0.0, 26.0);
    rotate(PI);
    push();
    translate(R * 0.94, 0.0);
    rotate(t * 1.7);
    fill(170.0, 140.0, 255.0);
    square(-11.0, -11.0, 22.0);
    pop();
    pop();

    // crosshair follows the mouse (click-drag on the canvas)
    stroke(255.0, 255.0, 255.0, 200.0);
    strokeWeight(1.0);
    line(mouseX - 14.0, mouseY, mouseX + 14.0, mouseY);
    line(mouseX, mouseY - 14.0, mouseX, mouseY + 14.0);
    noFill();
    strokeWeight(1.5);
    circle(mouseX, mouseY, 18.0);
}
