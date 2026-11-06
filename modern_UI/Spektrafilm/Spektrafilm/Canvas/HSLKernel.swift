// HSLKernel.swift — 景到 HSL, compiled at run time.
//
// The personal build reuses the official 1.3.5 `default.metallib` unchanged
// (Tools/build-personal.sh guards Shaders.metal), so this one small kernel is
// kept here as source and compiled once with safe, precise float math.
import Metal

enum HSLKernel {
    static func makePipeline(device: MTLDevice) -> MTLComputePipelineState? {
        let options = MTLCompileOptions()
        options.mathMode = .safe
        options.mathFloatingPointFunctions = .precise
        guard let library = try? device.makeLibrary(source: source, options: options),
              let function = library.makeFunction(name: "hslAdjust") else { return nil }
        return try? device.makeComputePipelineState(function: function)
    }

    // Same arithmetic as the iOS `mobileHSL` kernel: hue measured in linear
    // sRGB, rotation/scale about the grey axis, exact inverse back to ProPhoto.
    static let source = """
#include <metal_stdlib>
using namespace metal;
struct HSLUniforms {
    float4 hue[2];        // degrees per band
    float4 saturation[2]; // −1…1, relative chroma change
    float4 luminance[2];  // −1…1, stops of brightness on that colour
};

constant float3x3 proPhotoToSRGB = float3x3(
    float3(2.0340757, -0.2288132, -0.0085698),
    float3(-0.7273342, 1.2317301, -0.1532866),
    float3(-0.3067416, -0.0029169, 1.1618564));
constant float3x3 sRGBToProPhoto = float3x3(
    float3(0.5293460, 0.0983743, 0.0168832),
    float3(0.3300728, 0.8734610, 0.1176725),
    float3(0.1405812, 0.0281647, 0.8654443));
constant float bandCentre[9] = {0.0, 30.0, 60.0, 120.0, 180.0, 240.0, 270.0, 300.0, 360.0};

static inline float hslBand(constant float4 *v, int i) { return v[i >> 2][i & 3]; }

kernel void hslAdjust(texture2d<float, access::read> src [[texture(0)]],
                      texture2d<float, access::write> dst [[texture(1)]],
                      constant HSLUniforms &u [[buffer(0)]],
                      uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= dst.get_width() || gid.y >= dst.get_height()) return;
    float3 encoded = src.read(gid).rgb;
    float3 c = proPhotoToSRGB * pow(max(encoded, 0.0f), 1.8f);
    float hi = max(c.r, max(c.g, c.b)), lo = min(c.r, min(c.g, c.b));
    // Neutrals and near-neutrals are left alone.
    float chroma = (hi - lo) / max(hi, 1e-5f);
    float gate = smoothstep(0.02f, 0.20f, chroma) * step(1e-5f, hi);
    if (gate <= 0.0f) { dst.write(float4(encoded, 1), gid); return; }
    float h = atan2(0.8660254f * (c.g - c.b), c.r - 0.5f * (c.g + c.b)) * 57.29578f;
    if (h < 0.0f) h += 360.0f;
    // Piecewise-linear interpolation between neighbouring band centres.
    int i = 0;
    for (int k = 0; k < 8; ++k) { if (h >= bandCentre[k]) i = k; }
    float t = (h - bandCentre[i]) / (bandCentre[i + 1] - bandCentre[i]);
    int j = (i + 1) & 7;
    float dh = mix(hslBand(u.hue, i), hslBand(u.hue, j), t) * gate;
    float ds = mix(hslBand(u.saturation, i), hslBand(u.saturation, j), t) * gate;
    float dl = mix(hslBand(u.luminance, i), hslBand(u.luminance, j), t) * gate;
    // Rotate the chroma vector about the grey axis (Rodrigues, axis 1,1,1).
    float grey = (c.r + c.g + c.b) / 3.0f;
    float3 d = c - grey;
    float a = dh * 0.01745329f, ca = cos(a), sa = sin(a);
    float3 k = float3(0.5773503f);
    d = d * ca + cross(k, d) * sa + k * dot(k, d) * (1.0f - ca);
    d *= max(0.0f, 1.0f + ds);
    c = (grey + d) * exp2(dl);
    float3 back = sRGBToProPhoto * c;
    dst.write(float4(pow(max(back, 0.0f), 1.0f / 1.8f), 1), gid);
}
"""
}
