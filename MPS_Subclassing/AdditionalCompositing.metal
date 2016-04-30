//
//  AdditionalCompositing.metal
//  MPS_Subclassing
//
//  Created by Simon Gladman on 29/04/2016.
//  Copyright © 2016 Simon Gladman. All rights reserved.
//

#include <metal_stdlib>
using namespace metal;

kernel void additionalCompositing(texture2d<float, access::read> primaryTexture [[texture(0)]],
                                  texture2d<float, access::read> secondaryTexture [[texture(1)]],
                                  texture2d<float, access::write> destinationTexture [[texture(2)]],
                                  constant float &secondryTextureBrightness [[ buffer(0) ]],
                                  uint2 id [[thread_position_in_grid]])
{
    float4 primaryPixel = primaryTexture.read(id);
    float4 secondaryPixel = secondaryTexture.read(id);
    
    destinationTexture.write(saturate(primaryPixel + (secondaryPixel * secondryTextureBrightness)), id);
}
