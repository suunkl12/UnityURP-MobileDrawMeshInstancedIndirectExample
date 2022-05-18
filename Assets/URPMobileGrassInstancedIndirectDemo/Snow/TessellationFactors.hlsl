// MIT License

// Copyright (c) 2021 NedMakesGames

// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files(the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and / or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions :

// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.

// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

#ifndef TESSELLATION_FACTORS_INCLUDED
    #define TESSELLATION_FACTORS_INCLUDED

    #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

    struct Attributes {
        float3 positionOS : POSITION;
        float3 normalOS : NORMAL;
        UNITY_VERTEX_INPUT_INSTANCE_ID
    };

    struct TessellationFactors {
        float edge[3] : SV_TessFactor;
        float inside : SV_InsideTessFactor;
    };

    struct TessellationControlPoint {
        float3 positionWS : INTERNALTESSPOS;
        float3 normalWS : NORMAL;
        UNITY_VERTEX_INPUT_INSTANCE_ID
    };

    struct Interpolators {
        float3 normalWS                 : TEXCOORD0;
        float3 positionWS               : TEXCOORD1;
        float4 positionCS               : SV_POSITION;
        UNITY_VERTEX_INPUT_INSTANCE_ID
        UNITY_VERTEX_OUTPUT_STEREO
    };

    CBUFFER_START(UnityPerMaterial)
        float3 _FactorEdge1;
        float _FactorEdge2;
        float _FactorEdge3;
        float _FactorInside;
    CBUFFER_END

    float3 GetViewDirectionFromPosition(float3 positionWS) {
        return normalize(GetCameraPositionWS() - positionWS);
    }

    float4 GetShadowCoord(float3 positionWS, float4 positionCS) {
        // Calculate the shadow coordinate depending on the type of shadows currently in use
        #if SHADOWS_SCREEN
            return ComputeScreenPos(positionCS);
        #else
            return TransformWorldToShadowCoord(positionWS);
        #endif
    }

    TessellationControlPoint Vertex(Attributes input) {
        TessellationControlPoint output;

        UNITY_SETUP_INSTANCE_ID(input);
        UNITY_TRANSFER_INSTANCE_ID(input, output);

        VertexPositionInputs posnInputs = GetVertexPositionInputs(input.positionOS);
        VertexNormalInputs normalInputs = GetVertexNormalInputs(input.normalOS);

        output.positionWS = posnInputs.positionWS;
        output.normalWS = normalInputs.normalWS;
        return output;
    }

    // The patch constant function runs once per triangle, or "patch"
    // It runs in parallel to the hull function
    TessellationFactors PatchConstantFunction(
    InputPatch<TessellationControlPoint, 3> patch) {
        UNITY_SETUP_INSTANCE_ID(patch[0]); // Set up instancing
        // Calculate tessellation factors
        TessellationFactors f;
        f.edge[0] = _FactorEdge1.x;
        f.edge[1] = _FactorEdge1.y;
        f.edge[2] = _FactorEdge1.z;
        f.inside = _FactorInside;
        return f;
    }

    // The hull function runs once per vertex. You can use it to modify vertex
    // data based on values in the entire triangle
    [domain("tri")] // Signal we're inputting triangles
    [outputcontrolpoints(3)] // Triangles have three points
    [outputtopology("triangle_cw")] // Signal we're outputting triangles
    [patchconstantfunc("PatchConstantFunction")] // Register the patch constant function
    // Select a partitioning mode based on keywords
    #if defined(_PARTITIONING_INTEGER)
        [partitioning("integer")]
    #elif defined(_PARTITIONING_FRAC_EVEN)
        [partitioning("fractional_even")]
    #elif defined(_PARTITIONING_FRAC_ODD)
        [partitioning("fractional_odd")]
    #elif defined(_PARTITIONING_POW2)
        [partitioning("pow2")]
    #else 
        [partitioning("fractional_odd")]
    #endif
    TessellationControlPoint Hull(
    InputPatch<TessellationControlPoint, 3> patch, // Input triangle
    uint id : SV_OutputControlPointID) { // Vertex index on the triangle

        return patch[id];
    }

    // Call this macro to interpolate between a triangle patch, passing the field name
    #define BARYCENTRIC_INTERPOLATE(fieldName) \
    patch[0].fieldName * barycentricCoordinates.x + \
    patch[1].fieldName * barycentricCoordinates.y + \
    patch[2].fieldName * barycentricCoordinates.z

    // The domain function runs once per vertex in the final, tessellated mesh
    // Use it to reposition vertices and prepare for the fragment stage
    [domain("tri")] // Signal we're inputting triangles
    Interpolators Domain(
    TessellationFactors factors, // The output of the patch constant function
    OutputPatch<TessellationControlPoint, 3> patch, // The Input triangle
    float3 barycentricCoordinates : SV_DomainLocation) { // The barycentric coordinates of the vertex on the triangle

        Interpolators output;

        // Setup instancing and stereo support (for VR)
        UNITY_SETUP_INSTANCE_ID(patch[0]);
        UNITY_TRANSFER_INSTANCE_ID(patch[0], output);
        UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);

        float3 positionWS = BARYCENTRIC_INTERPOLATE(positionWS);
        float3 normalWS = BARYCENTRIC_INTERPOLATE(normalWS);

        output.positionCS = TransformWorldToHClip(positionWS);
        output.normalWS = normalWS;
        output.positionWS = positionWS;

        return output;
    }

    float4 Fragment(Interpolators input) : SV_Target{
        UNITY_SETUP_INSTANCE_ID(input);
        UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);

        // Fill the various lighting and surface data structures for the PBR algorithm
        InputData lightingInput = (InputData)0; // Found in URP/Input.hlsl
        lightingInput.positionWS = input.positionWS;
        lightingInput.normalWS = normalize(input.normalWS);
        lightingInput.viewDirectionWS = GetViewDirectionFromPosition(lightingInput.positionWS);
        lightingInput.shadowCoord = GetShadowCoord(lightingInput.positionWS, input.positionCS);
        lightingInput.normalizedScreenSpaceUV = GetNormalizedScreenSpaceUV(input.positionCS);

        SurfaceData surface = (SurfaceData)0; // Found in URP/SurfaceData.hlsl
        surface.albedo = 0.5;
        surface.alpha = 1;
        surface.metallic = 0;
        surface.smoothness = 0.5;
        surface.normalTS = float3(0, 0, 1);
        surface.occlusion = 1;

        return UniversalFragmentPBR(lightingInput, surface);
    }

#endif
