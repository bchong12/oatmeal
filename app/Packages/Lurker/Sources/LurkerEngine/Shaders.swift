/// The compositor's Metal source, compiled at startup. One full-screen pass draws, per output pixel:
/// background → screen shadow → screen card (rounded, inset) → click ripple → cursor, then dithers.
/// Everything lives in canvas space and is seen through the virtual camera; motion blur averages the stage over the
/// shutter (the camera's own movement is known exactly, so no optical flow is needed).
/// Colour math is in gamma-encoded sRGB so text keeps its weight when resampled.
enum Shaders {
    static let source = #"""
#include <metal_stdlib>
using namespace metal;

struct Uniforms {
    float4 view0;      // camera view (canvas px) at shutter open
    float4 view1;      // at shutter close
    float4 card;       // screen card rect, canvas px
    float4 crop;       // part of the source shown, source px
    float4 shadow;     // offset x, offset y, sigma, opacity
    float4 inset;      // rgb, width (canvas px)
    float4 cursor;     // sprite width, height, hot x, hot y (canvas px)
    float4 ripple;     // x, y, radius (canvas px), alpha
    float2 outSize;
    float2 canvasSize;
    float2 srcSize;
    float2 pad0;
    float radius;      // card corner radius, canvas px
    float cursorAlpha;
    int blurSamples;
    int cursorSamples;
    int cursorOn;
    int screenOn;
    float dither;
    float frameIndex;
    int maskCount;
    int highlightCount;
    int mpad1;
    int mpad2;
    float4 cam;        // Oatmeal camera bubble: centre x, centre y, radius (output px), mirror
    float2 camSize;    // camera frame size, px
    int camOn;
    int cpad;
};

// A mask over the screen, in source pixels. kind: 0 blur, 1 pixelate, 2 redact, 3 highlight.
struct MaskU { float4 rect; int kind; int p0; int p1; int p2; };

struct VOut { float4 position [[position]]; };

vertex VOut fullscreen(uint vid [[vertex_id]]) {
    float2 p = float2((vid << 1) & 2, vid & 2);
    VOut o; o.position = float4(p * 2.0 - 1.0, 0.0, 1.0);
    return o;
}

float sdRoundRect(float2 p, float4 r, float rad) {
    float2 c = r.xy + r.zw * 0.5;
    float2 h = r.zw * 0.5 - rad;
    float2 q = abs(p - c) - h;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - rad;
}

// erfc for soft shadows (Winitzki's approximation of erf, error < 1e-3)
float erfc_(float x) {
    float x2 = x * x;
    const float a = 0.147;
    float e = sqrt(1.0 - exp(-x2 * (1.27323954 + a * x2) / (1.0 + a * x2)));
    return 1.0 - (x < 0.0 ? -e : e);
}

// Mitchell–Netravali, B = C = 1/3
float mitchell(float x) {
    x = fabs(x);
    const float B = 1.0 / 3.0, C = 1.0 / 3.0;
    if (x < 1.0) return ((12 - 9 * B - 6 * C) * x * x * x + (-18 + 12 * B + 6 * C) * x * x + (6 - 2 * B)) / 6.0;
    if (x < 2.0) return ((-B - 6 * C) * x * x * x + (6 * B + 30 * C) * x * x + (-12 * B - 48 * C) * x + (8 * B + 24 * C)) / 6.0;
    return 0.0;
}

// Interleaved gradient noise: cheap, well spread dither.
float ign(float2 p, float frame) {
    p += frame * 5.588238;
    return fract(52.9829189 * fract(dot(p, float2(0.06711056, 0.00583715))));
}

// The source at a point (source px), filtered for `scale` source px per output px. High quality: a separable
// Mitchell kernel widened by the reduction, read straight from the full-resolution frame (zoomed text stays crisp).
float4 sampleSource(texture2d<float> src, sampler lin, float2 sp, float scale, bool hq, constant Uniforms &u) {
    float2 lo = u.crop.xy, hi = u.crop.xy + u.crop.zw - 1.0;
    if (!hq) return src.sample(lin, clamp(sp, lo + 0.5, hi + 0.5) / u.srcSize);
    float k = max(scale, 1.0);
    float R = 2.0 * k;
    int x0 = int(floor(sp.x - R)), x1 = int(ceil(sp.x + R));
    int y0 = int(floor(sp.y - R)), y1 = int(ceil(sp.y + R));
    // keep the footprint bounded (very large reductions fall back to a coarser kernel)
    int stepX = max(1, (x1 - x0) / 24), stepY = max(1, (y1 - y0) / 24);
    float4 acc = 0.0; float wsum = 0.0;
    for (int y = y0; y <= y1; y += stepY) {
        float wy = mitchell((float(y) + 0.5 - sp.y) / k);
        if (wy == 0.0) continue;
        for (int x = x0; x <= x1; x += stepX) {
            float wx = mitchell((float(x) + 0.5 - sp.x) / k);
            if (wx == 0.0) continue;
            float w = wx * wy;
            uint2 c = uint2(clamp(float2(x, y), lo, hi));
            acc += w * src.read(c);
            wsum += w;
        }
    }
    return wsum != 0.0 ? clamp(acc / wsum, 0.0, 1.0) : src.read(uint2(clamp(sp, lo, hi)));
}

// How far inside a mask a source point is (1 inside, soft 3 px edge).
float maskCover(float2 sp, float4 r, float px) {
    float d = sdRoundRect(sp, r, min(10.0, min(r.z, r.w) * 0.2));
    return clamp(0.5 - d / max(px, 1.0) * 0.33, 0.0, 1.0);
}

float3 masked(float3 s, float2 sp, float scale, texture2d<float> src, sampler lin, constant Uniforms &u, constant MaskU *masks) {
    bool lit = false;
    for (int i = 0; i < u.maskCount; i++) {
        MaskU m = masks[i];
        float c = maskCover(sp, m.rect, scale * 3.0);
        if (m.kind == 3) { if (c > 0.5) lit = true; continue; }
        if (c <= 0.0) continue;
        float3 e;
        if (m.kind == 0) {
            // a smooth Gaussian over a 7×7 grid of bilinear taps (each tap already averages 4 pixels)
            float r = max(14.0, u.srcSize.x * 0.012);
            e = 0.0; float n = 0.0;
            for (int y = -3; y <= 3; y++) {
                for (int x = -3; x <= 3; x++) {
                    float2 o = float2(x, y) * (r / 3.0);
                    float w = exp(-dot(float2(x, y), float2(x, y)) / 8.0);
                    e += w * src.sample(lin, (sp + o) / u.srcSize).rgb; n += w;
                }
            }
            e /= n;
        } else if (m.kind == 1) {
            float b = max(6.0, u.srcSize.x * 0.011);
            e = src.sample(lin, ((floor(sp / b) + 0.5) * b) / u.srcSize).rgb;
        } else {
            e = float3(0.08, 0.08, 0.09);
        }
        s = mix(s, e, c);
    }
    if (u.highlightCount > 0 && !lit) s *= 0.42;
    return s;
}

float3 stage(float2 cp, float pxCanvas, bool hq, texture2d<float> src, texture2d<float> bg, sampler lin, constant Uniforms &u, constant MaskU *masks) {
    float3 col = bg.sample(lin, cp / u.canvasSize).rgb;
    if (u.screenOn == 0) return col;
    if (u.shadow.w > 0.0) {
        float d = sdRoundRect(cp - u.shadow.xy, u.card, u.radius);
        float a = u.shadow.w * 0.5 * erfc_(d / (u.shadow.z * 1.41421356));
        col *= (1.0 - a);
    }
    float d = sdRoundRect(cp, u.card, u.radius);
    float cov = clamp(0.5 - d / pxCanvas, 0.0, 1.0);
    if (cov > 0.0) {
        float2 sp = u.crop.xy + (cp - u.card.xy) / u.card.zw * u.crop.zw;
        float scale = pxCanvas * u.crop.z / u.card.z;
        float3 s = sampleSource(src, lin, sp, scale, hq, u).rgb;
        if (u.maskCount > 0) s = masked(s, sp, scale, src, lin, u, masks);
        if (u.inset.w > 0.0) {
            float b = clamp((d + u.inset.w) / pxCanvas + 0.5, 0.0, 1.0);
            s = mix(s, u.inset.rgb, b);
        }
        col = mix(col, s, cov);
    }
    return col;
}

fragment float4 composite(VOut in [[stage_in]],
                          constant Uniforms &u [[buffer(0)]],
                          constant float2 *cursorPos [[buffer(1)]],
                          constant MaskU *masks [[buffer(2)]],
                          texture2d<float> src [[texture(0)]],
                          texture2d<float> bg [[texture(1)]],
                          texture2d<float> cursorTex [[texture(2)]],
                          texture2d<float> camTex [[texture(3)]]) {
    constexpr sampler lin(filter::linear, address::clamp_to_edge);
    float2 o = in.position.xy;
    int n = max(1, u.blurSamples);
    float jitter = ign(o, u.frameIndex);
    float3 col = 0.0;
    for (int k = 0; k < n; k++) {
        float f = n == 1 ? 0.5 : (float(k) + jitter) / float(n);
        float4 v = mix(u.view0, u.view1, f);
        float2 cp = v.xy + o / u.outSize * v.zw;
        col += stage(cp, v.z / u.outSize.x, n == 1, src, bg, lin, u, masks);
    }
    col /= float(n);

    float4 vmid = mix(u.view0, u.view1, 0.5);
    float2 cpm = vmid.xy + o / u.outSize * vmid.zw;
    float pxm = vmid.z / u.outSize.x;
    if (u.ripple.w > 0.0) {
        float d = length(cpm - u.ripple.xy);
        float w = max(u.ripple.z * 0.14, pxm * 1.5);
        float a = u.ripple.w * (1.0 - smoothstep(0.0, w, fabs(d - u.ripple.z)));
        a += u.ripple.w * 0.35 * (1.0 - smoothstep(u.ripple.z - w, u.ripple.z, d));
        col = mix(col, float3(1.0), clamp(a, 0.0, 1.0));
    }
    if (u.cursorOn != 0 && u.cursorAlpha > 0.0) {
        int m = max(1, u.cursorSamples);
        float4 c = 0.0;
        for (int i = 0; i < m; i++) {
            float f = m == 1 ? 0.5 : (float(i) + 0.5) / float(m);
            float4 v = mix(u.view0, u.view1, f);
            float2 cp = v.xy + o / u.outSize * v.zw;
            float2 local = cp - cursorPos[i] + u.cursor.zw;
            float2 uv = local / u.cursor.xy;
            if (all(uv >= 0.0) && all(uv <= 1.0)) c += cursorTex.sample(lin, uv);
        }
        c *= u.cursorAlpha / float(m);
        col = col * (1.0 - c.a) + c.rgb;
    }
    // Oatmeal: the camera bubble, in output space so zooms never move it. A soft shadow, a white ring, the face
    // (aspect-filled, mirrored like a selfie view).
    if (u.camOn != 0) {
        float k = u.outSize.y / 1080.0;
        float d = length(o - u.cam.xy) - u.cam.z;
        float ring = 4.0 * k;
        col *= 1.0 - 0.22 * (1.0 - smoothstep(0.0, 26.0 * k, d - ring + 6.0 * k));
        float2 local = (o - u.cam.xy) / (2.0 * u.cam.z) + 0.5;
        if (u.cam.w > 0.5) local.x = 1.0 - local.x;
        float aspect = u.camSize.x / max(u.camSize.y, 1.0);
        float2 uv = local;
        if (aspect > 1.0) uv.x = 0.5 + (local.x - 0.5) / aspect; else uv.y = 0.5 + (local.y - 0.5) * aspect;
        col = mix(col, float3(1.0), clamp(0.5 - (d - ring), 0.0, 1.0));
        col = mix(col, camTex.sample(lin, uv).rgb, clamp(0.5 - d, 0.0, 1.0));
    }
    col += (ign(o + 17.0, u.frameIndex) - 0.5) * u.dither / 255.0;
    return float4(saturate(col), 1.0);
}
"""#
}
