
VertexDescriptionInputs VGMeshToVertexDescriptionInputs(VertexAnimationData vertexAnimData, VertexAnimationAttributes vertexAttribute)
{
    VertexDescriptionInputs output;
    ZERO_INITIALIZE(VertexDescriptionInputs, output);

    $VertexDescriptionInputs.ObjectSpaceNormal:                         output.ObjectSpaceNormal =                          vertexAttribute.normalOS;
    $VertexDescriptionInputs.WorldSpaceNormal:                          output.WorldSpaceNormal =                           GDRPUtils_TransformObjectToWorldNormal(vertexAttribute.normalOS, vertexAnimData.local2WorldMatrix);
    $VertexDescriptionInputs.ViewSpaceNormal:                           output.ViewSpaceNormal =                            GDRPUtils_TransformWorldToViewDir(output.WorldSpaceNormal, vertexAnimData.viewMatrix);
    $VertexDescriptionInputs.TangentSpaceNormal:                        output.TangentSpaceNormal =                         float3(0.0f, 0.0f, 1.0f);
    $VertexDescriptionInputs.ObjectSpaceTangent:                        output.ObjectSpaceTangent =                         vertexAttribute.tangentOS.xyz;
    $VertexDescriptionInputs.WorldSpaceTangent:                         output.WorldSpaceTangent =                          GDRPUtils_TransformObjectToWorldDir(vertexAttribute.tangentOS.xyz, vertexAnimData.local2WorldMatrix);
    $VertexDescriptionInputs.ViewSpaceTangent:                          output.ViewSpaceTangent =                           GDRPUtils_TransformWorldToViewDir(output.WorldSpaceTangent, vertexAnimData.viewMatrix);
    $VertexDescriptionInputs.TangentSpaceTangent:                       output.TangentSpaceTangent =                        float3(1.0f, 0.0f, 0.0f);
    $VertexDescriptionInputs.ObjectSpaceBiTangent:                      output.ObjectSpaceBiTangent =                       GDRPUtils_CalcObjectSpaceBiTangent(vertexAttribute.normalOS, vertexAttribute.tangentOS, vertexAnimData.local2WorldMatrix);
    $VertexDescriptionInputs.WorldSpaceBiTangent:                       output.WorldSpaceBiTangent =                        GDRPUtils_TransformObjectToWorldDir(output.ObjectSpaceBiTangent, vertexAnimData.local2WorldMatrix);
    $VertexDescriptionInputs.ViewSpaceBiTangent:                        output.ViewSpaceBiTangent =                         GDRPUtils_TransformWorldToViewDir(output.WorldSpaceBiTangent, vertexAnimData.viewMatrix);
    $VertexDescriptionInputs.TangentSpaceBiTangent:                     output.TangentSpaceBiTangent =                      float3(0.0f, 1.0f, 0.0f);
    $VertexDescriptionInputs.ObjectSpacePosition:                       output.ObjectSpacePosition =                        vertexAttribute.positionOS;
    $VertexDescriptionInputs.WorldSpacePosition:                        output.WorldSpacePosition =                         GDRPUtils_TransformObjectToWorld(vertexAttribute.positionOS, vertexAnimData.local2WorldMatrix);
    $VertexDescriptionInputs.ViewSpacePosition:                         output.ViewSpacePosition =                          GDRPUtils_TransformWorldToView(output.WorldSpacePosition, vertexAnimData.viewMatrix);
    $VertexDescriptionInputs.TangentSpacePosition:                      output.TangentSpacePosition =                       float3(0.0f, 0.0f, 0.0f);
    $VertexDescriptionInputs.AbsoluteWorldSpacePosition:                output.AbsoluteWorldSpacePosition =                 GDRPUtils_GetAbsolutePositionWS(vertexAttribute.positionOS, vertexAnimData);
    $VertexDescriptionInputs.ObjectSpacePositionPredisplacement:        output.ObjectSpacePositionPredisplacement =         vertexAttribute.positionOS;
    $VertexDescriptionInputs.WorldSpacePositionPredisplacement:         output.WorldSpacePositionPredisplacement =          GDRPUtils_TransformObjectToWorld(vertexAttribute.positionOS, vertexAnimData.local2WorldMatrix);
    $VertexDescriptionInputs.ViewSpacePositionPredisplacement:          output.ViewSpacePositionPredisplacement =           GDRPUtils_TransformWorldToView(output.WorldSpacePosition, vertexAnimData.viewMatrix);
    $VertexDescriptionInputs.TangentSpacePositionPredisplacement:       output.TangentSpacePositionPredisplacement =        float3(0.0f, 0.0f, 0.0f);
    $VertexDescriptionInputs.AbsoluteWorldSpacePositionPredisplacement: output.AbsoluteWorldSpacePositionPredisplacement =  GDRPUtils_GetAbsolutePositionWS(vertexAttribute.positionOS, vertexAnimData);
    $VertexDescriptionInputs.WorldSpaceViewDirection:                   output.WorldSpaceViewDirection =                    GDRPUtils_GetWorldSpaceNormalizeViewDir(output.WorldSpacePosition, vertexAnimData);
    $VertexDescriptionInputs.ObjectSpaceViewDirection:                  output.ObjectSpaceViewDirection =                   GDRPUtils_TransformWorldToObjectDir(output.WorldSpaceViewDirection, vertexAnimData.local2WorldMatrix);
    $VertexDescriptionInputs.ViewSpaceViewDirection:                    output.ViewSpaceViewDirection =                     GDRPUtils_TransformWorldToViewDir(output.WorldSpaceViewDirection, vertexAnimData.viewMatrix);
    $VertexDescriptionInputs.TangentSpaceViewDirection:                 float3x3 tangentSpaceTransform =                    float3x3(output.WorldSpaceTangent, output.WorldSpaceBiTangent, output.WorldSpaceNormal);
    $VertexDescriptionInputs.TangentSpaceViewDirection:                 output.TangentSpaceViewDirection =                  TransformWorldToTangent(output.WorldSpaceViewDirection, tangentSpaceTransform);
    $VertexDescriptionInputs.ScreenPosition:                            output.ScreenPosition =                             ComputeScreenPos(GDRPUtils_TransformWorldToHClip(output.WorldSpacePosition, vertexAnimData.viewProjectionMatrix), _ProjectionParams.x);
    $VertexDescriptionInputs.NDCPosition:                               output.NDCPosition =                                output.ScreenPosition.xy / output.ScreenPosition.w;
    $VertexDescriptionInputs.PixelPosition:                             output.PixelPosition =                              float2(output.NDCPosition.x, 1.0f - output.NDCPosition.y) * vertexAnimData.viewSize;
    $VertexDescriptionInputs.uv0:                                       output.uv0 =                                        float4(vertexAttribute.uv0, 0.0f, 0.0f);
    $VertexDescriptionInputs.uv1:                                       output.uv1 =                                        float4(vertexAttribute.uv1, 0.0f, 0.0f);
    $VertexDescriptionInputs.uv2:                                       output.uv2 =                                        float4(vertexAttribute.uv2, 0.0f, 0.0f);
    $VertexDescriptionInputs.uv3:                                       output.uv3 =                                        float4(vertexAttribute.uv3, 0.0f, 0.0f);
    $VertexDescriptionInputs.VertexColor:                               output.VertexColor =                                vertexAttribute.color;
    $VertexDescriptionInputs.TimeParameters:                            output.TimeParameters =                             _TimeParameters.xyz; // Note: in case of animation this will be overwrite (allow to handle motion vector)
    //$VertexDescriptionInputs.BoneWeights:                               output.BoneWeights =                                input.weights; // undefined for VG
    //$VertexDescriptionInputs.BoneIndices:                               output.BoneIndices =                                input.indices; // undefined for VG
    $VertexDescriptionInputs.VertexID:                                  output.VertexID =                                   vertexAnimData.vertexId;

    return output;
}

VertexDescription GetVertexDescription(VertexAnimationData vertexAnimData, VertexAnimationAttributes vertexAttribute, float3 timeParameters UNITY_GDRP_INSTANCE_PARAMETER UNITY_GDRP_INSTANCE_ID_PARAMETER, uint materialOffset = 0)
{
    // build graph inputs
    VertexDescriptionInputs vertexDescriptionInputs = VGMeshToVertexDescriptionInputs(vertexAnimData, vertexAttribute);
    // Override time parameters with used one (This is required to correctly handle motion vectors for vertex animation based on time)
    $VertexDescriptionInputs.TimeParameters: vertexDescriptionInputs.TimeParameters = timeParameters;

    // evaluate vertex graph
    VertexDescription vertexDescription = VertexDescriptionFunction(vertexDescriptionInputs UNITY_GDRP_INSTANCE_ARGUMENT UNITY_GDRP_INSTANCE_ID_ARGUMENT, materialOffset);

    return vertexDescription;
}

VertexAnimationAttributes ApplyMeshModification(VertexAnimationData vertexAnimationData, VertexAnimationAttributes vertexAttribute, float3 timeParameters UNITY_GDRP_INSTANCE_PARAMETER UNITY_GDRP_INSTANCE_ID_PARAMETER, uint materialOffset = 0)
{
    VertexDescription vertexDescription = GetVertexDescription(vertexAnimationData, vertexAttribute, timeParameters UNITY_GDRP_INSTANCE_ARGUMENT UNITY_GDRP_INSTANCE_ID_ARGUMENT, materialOffset);

    // copy graph output to the results
    $VertexDescription.Position: vertexAttribute.positionOS = vertexDescription.Position;
    $VertexDescription.Normal:   vertexAttribute.normalOS = vertexDescription.Normal;
    $VertexDescription.Tangent:  vertexAttribute.tangentOS.xyz = vertexDescription.Tangent;
    $VertexDescription.uv0:      vertexAttribute.uv0 = vertexDescription.uv0;
    $VertexDescription.uv1:      vertexAttribute.uv1 = vertexDescription.uv1;
    $VertexDescription.uv2:      vertexAttribute.uv2 = vertexDescription.uv2;
    $VertexDescription.uv3:      vertexAttribute.uv3 = vertexDescription.uv3;

    return vertexAttribute;
}
