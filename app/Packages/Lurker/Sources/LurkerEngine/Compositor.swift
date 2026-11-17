import CoreVideo
import Foundation
import Metal
import MetalKit
import simd

/// Uniforms for one output frame. Field order and types mirror `Uniforms` in Shaders.swift exactly.
struct FrameUniforms {
    var view0 = SIMD4<Float>.zero
    var view1 = SIMD4<Float>.zero
    var card = SIMD4<Float>.zero
    var crop = SIMD4<Float>.zero
    var shadow = SIMD4<Float>.zero
    var inset = SIMD4<Float>.zero
    var cursor = SIMD4<Float>.zero
    var ripple = SIMD4<Float>.zero
    var outSize = SIMD2<Float>.zero
    var canvasSize = SIMD2<Float>.zero
    var srcSize = SIMD2<Float>.zero
    var pad0 = SIMD2<Float>.zero
    var radius: Float = 0
    var cursorAlpha: Float = 0
    var blurSamples: Int32 = 1
    var cursorSamples: Int32 = 1
    var cursorOn: Int32 = 0
    var screenOn: Int32 = 1
    var dither: Float = 1
    var frameIndex: Float = 0
    var maskCount: Int32 = 0
    var highlightCount: Int32 = 0
    var mpad1: Int32 = 0
    var mpad2: Int32 = 0
    /// Oatmeal's camera (a rounded square): centre x, centre y, half its side (output px), mirror (1 = flip).
    var cam = SIMD4<Float>.zero
    var camSize = SIMD2<Float>.zero
    var camOn: Int32 = 0
    var cpad: Int32 = 0
}

/// One mask for the shader (mirrors MaskU).
struct MaskUniform {
    var rect: SIMD4<Float>
    var kind: Int32
    var p0: Int32 = 0, p1: Int32 = 0, p2: Int32 = 0
}

/// Runs the composite pass on the GPU, reading decoded frames and writing the encoder's pixel buffers without copies.
final class Compositor: @unchecked Sendable {
    let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private var cache: CVMetalTextureCache?
    private let loader: MTKTextureLoader
    /// 1×1 stand-ins for unused texture slots.
    private let blank: MTLTexture

    init() throws {
        guard let d = MTLCreateSystemDefaultDevice(), let q = d.makeCommandQueue() else { throw EngineError("no Metal device") }
        device = d; queue = q
        let lib = try d.makeLibrary(source: Shaders.source, options: nil)
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = lib.makeFunction(name: "fullscreen")
        desc.fragmentFunction = lib.makeFunction(name: "composite")
        desc.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipeline = try d.makeRenderPipelineState(descriptor: desc)
        CVMetalTextureCacheCreate(nil, nil, d, nil, &cache)
        loader = MTKTextureLoader(device: d)
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 1, height: 1, mipmapped: false)
        guard let b = d.makeTexture(descriptor: td) else { throw EngineError("no Metal texture") }
        var px: UInt32 = 0xFF00_0000
        b.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: &px, bytesPerRow: 4)
        blank = b
    }

    /// A BGRA pixel buffer as a texture. The returned CVMetalTexture must stay alive until the GPU is done.
    func texture(_ pb: CVPixelBuffer) -> (MTLTexture, CVMetalTexture)? {
        guard let cache else { return nil }
        var cvt: CVMetalTexture?
        CVMetalTextureCacheCreateTextureFromImage(nil, cache, pb, nil, .bgra8Unorm, CVPixelBufferGetWidth(pb), CVPixelBufferGetHeight(pb), 0, &cvt)
        guard let cvt, let t = CVMetalTextureGetTexture(cvt) else { return nil }
        return (t, cvt)
    }

    /// An image as a texture, values kept as encoded (no sRGB decode), top row first.
    func texture(_ image: CGImage) throws -> MTLTexture {
        try loader.newTexture(cgImage: image, options: [.SRGB: false, .origin: MTKTextureLoader.Origin.topLeft, .textureUsage: MTLTextureUsage.shaderRead.rawValue])
    }

    func render(into out: CVPixelBuffer, uniforms: FrameUniforms, cursorPositions: [SIMD2<Float>], source: CVPixelBuffer?, background: MTLTexture,
                cursor: MTLTexture?, masks: [MaskUniform] = [], camera: CVPixelBuffer? = nil) throws {
        guard let (target, keepTarget) = texture(out) else { throw EngineError("output buffer isn't Metal compatible") }
        let src = source.flatMap(texture)
        let cam = camera.flatMap(texture)
        let rp = MTLRenderPassDescriptor()
        rp.colorAttachments[0].texture = target
        rp.colorAttachments[0].loadAction = .dontCare
        rp.colorAttachments[0].storeAction = .store
        guard let cb = queue.makeCommandBuffer(), let enc = cb.makeRenderCommandEncoder(descriptor: rp) else { throw EngineError("Metal command failed") }
        enc.setRenderPipelineState(pipeline)
        var u = uniforms
        enc.setFragmentBytes(&u, length: MemoryLayout<FrameUniforms>.stride, index: 0)
        var pos = cursorPositions.isEmpty ? [SIMD2<Float>.zero] : cursorPositions
        enc.setFragmentBytes(&pos, length: MemoryLayout<SIMD2<Float>>.stride * pos.count, index: 1)
        var ms = masks.isEmpty ? [MaskUniform(rect: .zero, kind: 0)] : masks
        enc.setFragmentBytes(&ms, length: MemoryLayout<MaskUniform>.stride * ms.count, index: 2)
        enc.setFragmentTexture(src?.0 ?? blank, index: 0)
        enc.setFragmentTexture(background, index: 1)
        enc.setFragmentTexture(cursor ?? blank, index: 2)
        enc.setFragmentTexture(cam?.0 ?? blank, index: 3)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
        cb.commit()
        cb.waitUntilCompleted()
        if let e = cb.error { throw EngineError("GPU: \(e.localizedDescription)") }
        withExtendedLifetime((keepTarget, src?.1, cam?.1)) {}
    }
}
