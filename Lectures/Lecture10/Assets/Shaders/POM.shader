// Upgrade NOTE: replaced 'mul(UNITY_MATRIX_MVP,*)' with 'UnityObjectToClipPos(*)'

// Upgrade NOTE: replaced 'mul(UNITY_MATRIX_MVP,*)' with 'UnityObjectToClipPos(*)'

Shader "Custom/POM"
{
    Properties {
        // normal map texture on the material,
        // default to dummy "flat surface" normalmap
        [KeywordEnum(PLAIN, NORMAL, BUMP, POM, POM_SHADOWS)] MODE("Overlay mode", Float) = 0
        
        _NormalMap("Normal Map", 2D) = "bump" {}
        _MainTex("Texture", 2D) = "grey" {}
        _HeightMap("Height Map", 2D) = "white" {}
        _MaxHeight("Max Height", Range(0.0001, 0.02)) = 0.01
        _StepLength("Step Length", Float) = 0.000001
        _MaxStepCount("Max Step Count", Int) = 64
        _TexToWorldLen("Texture To World  Length", Float) = 1
        
        _Reflectivity("Reflectivity", Range(1, 100)) = 0.5
    }
    
    CGINCLUDE
    #include "UnityCG.cginc"
    #include "UnityLightingCommon.cginc"
    
    inline float LinearEyeDepthToOutDepth(float z)
    {
        return (1 - _ZBufferParams.w * z) / (_ZBufferParams.z * z);
    }

    struct v2f {
        float3 worldPos : TEXCOORD0;
        half3 worldTangent : TEXCOORD1;
        half3 worldBitangent : TEXCOORD2;
        half3 worldSurfaceNormal : TEXCOORD3;
        // texture coordinate for the normal map
        float2 uv : TEXCOORD4;
        float4 clip : SV_POSITION;
    };

    // Vertex shader now also gets a per-vertex tangent vector.
    // In Unity tangents are 4D vectors, with the .w component used to indicate direction of the bitangent vector.
    v2f vert (float4 vertex : POSITION, float3 normal : NORMAL, float4 tangent : TANGENT, float2 uv : TEXCOORD0)
    {
        v2f o;
        o.clip = UnityObjectToClipPos(vertex);
        o.worldPos = mul(unity_ObjectToWorld, vertex).xyz;
        half3 wNormal = UnityObjectToWorldNormal(normal);
        half3 wTangent = UnityObjectToWorldDir(tangent.xyz);
        
        o.uv = uv;
        o.worldSurfaceNormal = normal;

        half3 wBitangent = cross(wNormal, wTangent) * -tangent.w;
        o.worldTangent = wTangent;
        o.worldBitangent = wBitangent;

        return o;
    }

    // normal map texture from shader properties
    sampler2D _NormalMap;
    sampler2D _MainTex;
    sampler2D _HeightMap;
    
    // The maximum depth in which the ray can go.
    uniform float _MaxHeight;
    // Step size
    uniform float _StepLength;
    // Count of steps
    uniform int _MaxStepCount;

    uniform float _TexToWorldLen;
    
    float _Reflectivity;

    float2 BumpMapping(float2 uv, half3 viewDir)
    { 
        float height = 1 - tex2D(_HeightMap, uv).r * _MaxHeight;
        float2 offset = viewDir.xy / viewDir.z * height;
        return uv - offset;
    }

    float sampleHeight(float2 uv)
    {
        return (1 - tex2Dlod(_HeightMap, float4(uv, 0, 0)).r) * _MaxHeight;
    }

    float2 ParallaxOcclusionMapping(float2 uv, half3 viewDir)
    { 
        float viewHeight = 0;

        float2 deltaUV = viewDir.xy * _StepLength * _MaxHeight / viewDir.z;
        float deltaHeight = _MaxHeight * _StepLength;
//        float2 deltaUV = normalize(viewDir.xy) * _StepLength;
//        float deltaHeight = _StepLength * viewDir.z / length(viewDir.xy);
        float height = sampleHeight(uv);
        
        for (int step = 0; step < _MaxStepCount && viewHeight < height; ++step)
        {
            uv -= deltaUV;
            height = sampleHeight(uv);
            viewHeight += deltaHeight;  
        }

        float2 prevUV = uv + deltaUV;

        float afterDepth = height - viewHeight;
        float beforeDepth = sampleHeight(prevUV) - viewHeight + deltaHeight;
        
        float t = afterDepth / (afterDepth - beforeDepth);
        return lerp(prevUV, uv, t);
    }

    void frag (in v2f i, out half4 outColor : COLOR, out float outDepth : DEPTH)
    {
        float2 uv = i.uv;
        
        float3 worldViewDir = normalize(i.worldPos.xyz - _WorldSpaceCameraPos.xyz);

        half3x3 tbnInv = half3x3(i.worldTangent, i.worldBitangent, i.worldSurfaceNormal);
        half3x3 tbn = transpose(tbnInv);
#if MODE_BUMP
        float3 bumpResult = BumpMapping(uv, mul(tbnInv, worldViewDir));
        uv = bumpResult.xy;
#endif   
    
        float depthDif = 0;
#if MODE_POM | MODE_POM_SHADOWS    
        float2 oldUV = uv;
        uv = ParallaxOcclusionMapping(oldUV, mul(tbnInv, worldViewDir));
        depthDif = length(uv - oldUV) * _TexToWorldLen;
#endif

        float3 worldLightDir = normalize(_WorldSpaceLightPos0.xyz);
        float shadow = 0;
#if MODE_POM_SHADOWS
    
#endif
        
        half3 normal = i.worldSurfaceNormal;
#if !MODE_PLAIN
        half3 surfNormal = UnpackNormal(tex2D(_NormalMap, uv));
        normal = normalize(mul(tbn, surfNormal.xyz));
#endif

        // Diffuse lightning
        half cosTheta = max(0, dot(normal, worldLightDir));
        half3 diffuseLight = max(0, cosTheta) * _LightColor0 * max(0, 1 - shadow);
        
        // Specular lighting (ad-hoc)
        half specularLight = pow(max(0, dot(worldViewDir, reflect(worldLightDir, normal))), _Reflectivity) * _LightColor0 * max(0, 1 - shadow); 

        // Ambient lighting
        half3 ambient = ShadeSH9(half4(UnityObjectToWorldNormal(normal), 1));

        // Return resulting color
        float3 texColor = tex2D(_MainTex, uv);
        outColor = half4((diffuseLight + specularLight + ambient) * texColor, 0);
        outDepth = LinearEyeDepthToOutDepth(LinearEyeDepth(i.clip.z) + depthDif);
    }
    ENDCG
    
    SubShader
    {    
        Pass
        {
            Name "MAIN"
            Tags { "LightMode" = "ForwardBase" }
        
            ZTest Less
            ZWrite On
            Cull Back
            
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            
            #pragma multi_compile_local MODE_PLAIN MODE_NORMAL MODE_BUMP MODE_POM MODE_POM_SHADOWS
            ENDCG
            
        }
    }
}