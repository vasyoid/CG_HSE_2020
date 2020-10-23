Shader "0_Custom/Cubemap"
{
    Properties
    {
        _BaseColor ("Color", Color) = (0, 0, 0, 1)
        _Roughness ("Roughness", Range(0.03, 1)) = 1
        _Samples ("Samples", Int) = 10000
        _Cube ("Cubemap", CUBE) = "" {}
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" }
        LOD 100

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "UnityCG.cginc"
            #include "UnityLightingCommon.cginc"
            
            #define EPS 1e-7

            struct appdata
            {
                float4 vertex : POSITION;
                fixed3 normal : NORMAL;
            };

            struct v2f
            {
                float4 clip : SV_POSITION;
                float4 pos : TEXCOORD1;
                fixed3 normal : NORMAL;
            };

            float4 _BaseColor;
            float _Roughness;
            int _Samples;
            
            samplerCUBE _Cube;
            half4 _Cube_HDR;
            
            v2f vert (appdata v)
            {
                v2f o;
                o.clip = UnityObjectToClipPos(v.vertex);
                o.pos = mul(UNITY_MATRIX_M, v.vertex);
                o.normal = UnityObjectToWorldNormal(v.normal);
                return o;
            }

            uint Hash(uint s)
            {
                s ^= 2747636419u;
                s *= 2654435769u;
                s ^= s >> 16;
                s *= 2654435769u;
                s ^= s >> 16;
                s *= 2654435769u;
                return s;
            }
            
            float Random(uint seed)
            {
                return float(Hash(seed)) / 4294967295.0; // 2^32-1
            }
            
            float3 SampleColor(float3 direction)
            {   
                half4 tex = texCUBElod(_Cube, float4(direction, 0));
                return DecodeHDR(tex, _Cube_HDR).rgb;
            }
            
            float Sqr(float x)
            {
                return x * x;
            }
            
            // Calculated according to NDF of Cook-Torrance
            float GetSpecularBRDF(float3 viewDir, float3 lightDir, float3 normalDir)
            {
                float3 halfwayVector = normalize(viewDir + lightDir);               
                
                float a = Sqr(_Roughness);
                float a2 = Sqr(a);
                float NDotH2 = Sqr(dot(normalDir, halfwayVector));
                
                return a2 / (UNITY_PI * Sqr(NDotH2 * (a2 - 1) + 1));
            }

            // Rotation matrix which maps (0, 1, 0) to v
            // Formula was taken from https://en.wikipedia.org/wiki/Rotation_matrix#Vector_to_vector_formulation
            float3x3 GetRotationMat(float3 v)
            {
                if (v.y == -1)
                {
                    return float3x3
                    (
                        -1, 0, 0,
                        0, -1, 0,
                        0, 0, -1
                    );
                }
                float3x3 m1 = float3x3
                (
                    1, v.x, 0,
                    -v.x, 1, -v.z,
                    0, v.z, 1
                );
                float3x3 m2 = float3x3
                (
                    -v.x * v.x, 0, -v.x * v.z,
                    0, -v.x * v.x - v.z * v.z, 0,
                    -v.x * v.z, 0, -v.z * v.z
                );
                return m1 + 1 / (1 + v.y) * m2;
            }
            
            fixed4 frag (v2f i) : SV_Target
            {
                const float PI = 3.14159265;
                float3 normal = normalize(i.normal);
                
                float3 viewDirection = normalize(_WorldSpaceCameraPos - i.pos.xyz);

                float3 lOut = float3(0, 0, 0);
                float normCft = 0;
                
                float3x3 rotation = GetRotationMat(normal); 
                uint randSeed = 42;
                
                for (int i = 0; i < _Samples; ++i)
                {
                    float cosPhi = Random(randSeed);
                    float sinPhi = sqrt(1 - Sqr(cosPhi));
                    randSeed = Hash(randSeed);
                    float alpha = Random(randSeed) * 2 * PI;
                    randSeed = Hash(randSeed);
                    
                    float3 lightDirection = float3
                    (
                        sinPhi * cos(alpha),
                        cosPhi,
                        sinPhi * sin(alpha)
                    );
                    
                    lightDirection = mul(rotation, lightDirection);
                    
                    float3 lIn = SampleColor(lightDirection);
                    float brdf = GetSpecularBRDF(viewDirection, lightDirection, normal);
                    float cosTheta = dot(normal, lightDirection);
                    
                    lOut += lIn * brdf * cosTheta;
                    normCft += brdf * cosTheta;
                }
                lOut /= normCft;
                return fixed4(lOut, 1);
            }
            ENDCG
        }
    }
}
