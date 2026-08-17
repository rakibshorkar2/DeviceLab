import Foundation
import Metal

/// GPU benchmark using Metal (public API).
/// Measures DeviceLab's own GPU workload: compute throughput and
/// triangle-rendering throughput. Not equivalent to Apple's internal
/// GPU benchmark and never claimed to be.
struct GPUBenchmark: Benchmark {
    let category = "GPU"
    let name = "GPU Benchmark"
    let detailName = "Metal compute + rendering"

    func run(progress: @escaping @Sendable (Double) async -> Void, cancelled: @escaping @Sendable () async -> Bool) async throws -> BenchmarkOutcome {
        guard let engine = try? MetalGPUBenchmarkEngine() else {
            throw BenchmarkError.metalUnavailable
        }

        await progress(0.05)
        let compute = try engine.runCompute(iterations: 120)
        if await cancelled() { throw BenchmarkError.cancelled }
        await progress(0.55)

        let render = try engine.runRender(seconds: 3.0)
        if await cancelled() { throw BenchmarkError.cancelled }
        await progress(0.95)

        let computeScore = BenchmarkMeasurement.normalizedScore(workPerSecond: compute.flopsPerSecond, reference: 1.5e12)
        let renderScore = BenchmarkMeasurement.normalizedScore(workPerSecond: render.trianglesPerSecond, reference: 1.0e10)
        let score = computeScore * 0.6 + renderScore * 0.4

        let detail = """
        Compute (float4 add): \(String(format: "%.2f TFLOP/s", compute.flopsPerSecond / 1e12))
        Compute score: \(Int(computeScore))
        Rendering: \(Int(render.fps)) FPS · \(String(format: "%.2f ms", render.frameTimeMs)) frame time
        Triangles/s: \(String(format: "%.2f M", render.trianglesPerSecond / 1e6))
        Render score: \(Int(renderScore))
        Thermal state during run: \(ThermalMonitor.name(for: ProcessInfo.processInfo.thermalState))

        DeviceLab score (0–10,000), normalized against internal calibration
        constants. Measured on this device with Metal.
        """

        return BenchmarkOutcome(
            score: score,
            metrics: [
                "computeScore": computeScore,
                "renderScore": renderScore,
                "fps": render.fps,
                "frameTimeMs": render.frameTimeMs,
                "flopsPerSecond": compute.flopsPerSecond,
            ],
            detail: detail
        )
    }
}

final class MetalGPUBenchmarkEngine: @unchecked Sendable {
    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let library: MTLLibrary

    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    kernel void add4(const device float4* a [[buffer(0)]],
                     const device float4* b [[buffer(1)]],
                     device float4* out [[buffer(2)]],
                     uint id [[thread_position_in_grid]]) {
        out[id] = a[id] + b[id];
    }

    struct VertexOut {
        float4 position [[position]];
        float4 color;
    };

    vertex VertexOut triangle_vertex(uint vid [[vertex_id]],
                                     uint iid [[instance_id]],
                                     const device float2* positions [[buffer(0)]]) {
        float2 pos = positions[vid % 3];
        float angle = float(iid % 360) * 3.14159265 / 180.0;
        float2x2 rot = float2x2(cos(angle), -sin(angle), sin(angle), cos(angle));
        VertexOut out;
        out.position = float4(rot * pos, 0.0, 1.0);
        out.color = float4(0.3 + 0.7 * pos.x, 0.3 - 0.5 * pos.y, 0.8, 1.0);
        return out;
    }

    fragment float4 triangle_fragment(VertexOut in [[stage_in]]) {
        return in.color;
    }
    """

    init() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw BenchmarkError.metalUnavailable
        }
        self.device = device
        guard let queue = device.makeCommandQueue() else {
            throw BenchmarkError.metalUnavailable
        }
        self.queue = queue
        guard let library = try? device.makeLibrary(source: Self.shaderSource, options: nil) else {
            throw BenchmarkError.metalUnavailable
        }
        self.library = library
    }

    func runCompute(iterations: Int) throws -> (flopsPerSecond: Double, iterations: Int) {
        let count = 2_000_000
        let byteSize = count * MemoryLayout<SIMD4<Float>>.stride

        guard let a = device.makeBuffer(length: byteSize, options: .storageModeShared),
              let b = device.makeBuffer(length: byteSize, options: .storageModeShared),
              let out = device.makeBuffer(length: byteSize, options: .storageModeShared),
              let function = library.makeFunction(name: "add4"),
              let pipeline = try? device.makeComputePipelineState(function: function) else {
            throw BenchmarkError.metalUnavailable
        }

        let ptr = a.contents().assumingMemoryBound(to: Float.self)
        for i in 0..<(byteSize / MemoryLayout<Float>.stride) {
            ptr[i] = Float(i % 97) * 0.01
        }
        let ptrB = b.contents().assumingMemoryBound(to: Float.self)
        for i in 0..<(byteSize / MemoryLayout<Float>.stride) {
            ptrB[i] = Float(i % 53) * 0.01
        }

        let start = Date()
        guard let commandBuffer = queue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw BenchmarkError.metalUnavailable
        }
        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(a, offset: 0, index: 0)
        encoder.setBuffer(b, offset: 0, index: 1)
        encoder.setBuffer(out, offset: 0, index: 2)
        let threads = MTLSize(width: count, height: 1, depth: 1)
        let threadsPerGroup = MTLSize(width: 256, height: 1, depth: 1)
        for _ in 0..<iterations {
            encoder.dispatchThreads(threads, threadsPerThreadgroup: threadsPerGroup)
        }
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        let elapsed = Date().timeIntervalSince(start)

        let ops = Double(iterations) * Double(count) * 4.0 * 2.0
        return (ops / elapsed, iterations)
    }

    func runRender(seconds: Double) throws -> (fps: Double, frameTimeMs: Double, trianglesPerSecond: Double) {
        guard let vertexFunction = library.makeFunction(name: "triangle_vertex"),
              let fragmentFunction = library.makeFunction(name: "triangle_fragment") else {
            throw BenchmarkError.metalUnavailable
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        guard let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor) else {
            throw BenchmarkError.metalUnavailable
        }

        let width = 1170
        let height = 2532
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        textureDescriptor.usage = [.renderTarget]
        guard let texture = device.makeTexture(descriptor: textureDescriptor) else {
            throw BenchmarkError.metalUnavailable
        }

        let triangle: [SIMD2<Float>] = [
            SIMD2<Float>(0.0, 0.9),
            SIMD2<Float>(-0.8, -0.6),
            SIMD2<Float>(0.8, -0.6),
        ]
        let vertexBuffer = device.makeBuffer(
            bytes: triangle,
            length: triangle.count * MemoryLayout<SIMD2<Float>>.stride,
            options: []
        )

        let instances = 300_000
        var frameCount = 0
        let deadline = Date().addingTimeInterval(seconds)
        let start = Date()

        repeat {
            guard let renderPass = MTLRenderPassDescriptor() as MTLRenderPassDescriptor? else { break }
            renderPass.colorAttachments[0].texture = texture
            renderPass.colorAttachments[0].loadAction = .clear
            renderPass.colorAttachments[0].storeAction = .store
            renderPass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)

            guard let commandBuffer = queue.makeCommandBuffer(),
                  let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass) else {
                throw BenchmarkError.metalUnavailable
            }
            encoder.setRenderPipelineState(pipeline)
            encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3, instanceCount: instances)
            encoder.endEncoding()
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
            frameCount += 1
        } while Date() < deadline

        let elapsed = Date().timeIntervalSince(start)
        let fps = Double(frameCount) / elapsed
        let frameTimeMs = elapsed / Double(frameCount) * 1000
        let trianglesPerSecond = Double(frameCount * instances) / elapsed
        return (fps, frameTimeMs, trianglesPerSecond)
    }
}