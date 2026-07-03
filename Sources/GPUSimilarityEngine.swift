import Metal
import Foundation

class GPUSimilarityEngine {
    static let shared = GPUSimilarityEngine()
    
    private var device: MTLDevice?
    private var commandQueue: MTLCommandQueue?
    private var computePipelineState: MTLComputePipelineState?
    
    private init() {
        setupMetal()
    }
    
    private func setupMetal() {
        self.device = MTLCreateSystemDefaultDevice()
        guard let device = device else {
            print("Metal is not supported on this device.")
            return
        }
        
        self.commandQueue = device.makeCommandQueue()
        
        // Load default library
        guard let library = device.makeDefaultLibrary() else {
            print("Failed to load default Metal library.")
            return
        }
        
        guard let kernelFunction = library.makeFunction(name: "cosine_similarity_search") else {
            print("Failed to find kernel function 'cosine_similarity_search'.")
            return
        }
        
        do {
            self.computePipelineState = try device.makeComputePipelineState(function: kernelFunction)
        } catch {
            print("Failed to create compute pipeline state: \(error)")
        }
    }
    
    func performParallelSearch(
        query: [Float],
        database: [Float],
        vectorCount: Int,
        dimension: Int
    ) -> [Float]? {
        guard let device = device,
              let commandQueue = commandQueue,
              let pipelineState = computePipelineState else {
            return nil
        }
        
        // 1. Create Buffers
        let queryByteLength = query.count * MemoryLayout<Float>.size
        let databaseByteLength = database.count * MemoryLayout<Float>.size
        let resultsByteLength = vectorCount * MemoryLayout<Float>.size
        
        guard let queryBuffer = device.makeBuffer(bytes: query, length: queryByteLength, options: .storageModeShared),
              let databaseBuffer = device.makeBuffer(bytes: database, length: databaseByteLength, options: .storageModeShared),
              let resultsBuffer = device.makeBuffer(length: resultsByteLength, options: .storageModeShared) else {
            return nil
        }
        
        // 2. Create command buffer and compute encoder
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
            return nil
        }
        
        computeEncoder.setComputePipelineState(pipelineState)
        computeEncoder.setBuffer(queryBuffer, offset: 0, index: 0)
        computeEncoder.setBuffer(databaseBuffer, offset: 0, index: 1)
        computeEncoder.setBuffer(resultsBuffer, offset: 0, index: 2)
        
        var dim = UInt32(dimension)
        computeEncoder.setBytes(&dim, length: MemoryLayout<UInt32>.size, index: 3)
        
        // 3. Threads configuration
        let threadExecutionWidth = pipelineState.threadExecutionWidth
        let threadsPerThreadgroup = MTLSize(width: threadExecutionWidth, height: 1, depth: 1)
        let threadsPerGrid = MTLSize(width: vectorCount, height: 1, depth: 1)
        
        computeEncoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
        computeEncoder.endEncoding()
        
        // 4. Commit and wait
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        // 5. Retrieve results
        let resultsPointer = resultsBuffer.contents().assumingMemoryBound(to: Float.self)
        var results = [Float](repeating: 0.0, count: vectorCount)
        for i in 0..<vectorCount {
            results[i] = resultsPointer[i]
        }
        
        return results
    }
}
