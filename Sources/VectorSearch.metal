#include <metal_stdlib>
using namespace metal;

kernel void cosine_similarity_search(
    device const float* queryVector [[buffer(0)]],
    device const float* databaseVectors [[buffer(1)]],
    device float* resultSimilarities [[buffer(2)]],
    device const uint& dimension [[buffer(3)]],
    uint id [[thread_position_in_grid]]
) {
    // Thread index corresponds to database vector index
    uint offset = id * dimension;
    
    float dotProduct = 0.0;
    float magnitudeQ = 0.0;
    float magnitudeD = 0.0;
    
    for (uint i = 0; i < dimension; i++) {
        float q = queryVector[i];
        float d = databaseVectors[offset + i];
        
        dotProduct += q * d;
        magnitudeQ += q * q;
        magnitudeD += d * d;
    }
    
    if (magnitudeQ > 0.0 && magnitudeD > 0.0) {
        resultSimilarities[id] = dotProduct / (sqrt(magnitudeQ) * sqrt(magnitudeD));
    } else {
        resultSimilarities[id] = 0.0;
    }
}
