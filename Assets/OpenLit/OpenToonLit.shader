// Shader example using OpenLit Library
// This code is licensed under CC0 1.0 Universal.
// https://creativecommons.org/publicdomain/zero/1.0/
Shader "OpenToonLit"
{
    Properties
    {
        //------------------------------------------------------------------------------------------------------------------------------
        // Properties for material
        _MainTex ("Texture", 2D) = "white" {}
        _ShadowThreshold ("Shadow Threshold", Range(-1,1)) = 0
        [Toggle(_)] _ReceiveShadow ("Receive Shadow", Int) = 0
        [Toggle(_PACK_LIGHTDATAS)] _PackLightDatas ("[Debug] Pack Light Datas", Int) = 0

        //------------------------------------------------------------------------------------------------------------------------------
        // [OpenLit] Properties for lighting

        // It is more accurate to set _LightMinLimit to 0, but the avatar will be black.
        // In many cases, setting a small value will give better results.

        // _VertexLightStrength should be set to 1, but vertex lights will not work properly if there are multiple SkinnedMeshRenderers.
        // And many users seem to prefer to use multiple SkinnedMeshRenderers.
        [Space]
        _AsUnlit                ("As Unlit", Range(0,1)) = 0
        _VertexLightStrength    ("Vertex Light Strength", Range(0,1)) = 0
        _LightMinLimit          ("Light Min Limit", Range(0,1)) = 0.05
        _LightMaxLimit          ("Light Max Limit", Range(0,10)) = 1
        _BeforeExposureLimit    ("Before Exposure Limit", Float) = 10000
        _MonochromeLighting     ("Monochrome lighting", Range(0,1)) = 0
        _AlphaBoostFA           ("Boost Transparency in ForwardAdd", Range(1,100)) = 10
        _LightDirectionOverride ("Light Direction Override", Vector) = (0.001,0.002,0.001,0)

        // Based on Semantic Versioning 2.0.0
        // https://semver.org/spec/v2.0.0.html
        [HideInInspector] _OpenLitVersionMAJOR ("MAJOR", Int) = 1
        [HideInInspector] _OpenLitVersionMINOR ("MINOR", Int) = 0
        [HideInInspector] _OpenLitVersionPATCH ("PATCH", Int) = 0

        //------------------------------------------------------------------------------------------------------------------------------
        // [OpenLit] ForwardBase
        [Enum(UnityEngine.Rendering.BlendMode)] _SrcBlend   ("SrcBlend", Int) = 1
        [Enum(UnityEngine.Rendering.BlendMode)] _DstBlend   ("DstBlend", Int) = 0
        [Enum(UnityEngine.Rendering.BlendOp)]   _BlendOp    ("BlendOp", Int) = 0

        //------------------------------------------------------------------------------------------------------------------------------
        // [OpenLit] ForwardAdd uses "BlendOp Max" to avoid overexposure
        // This blending causes problems with transparent materials, so use the _AlphaBoostFA property to boost transparency.
        [Enum(UnityEngine.Rendering.BlendMode)] _SrcBlendFA ("ForwardAdd SrcBlend", Int) = 1
        [Enum(UnityEngine.Rendering.BlendMode)] _DstBlendFA ("ForwardAdd DstBlend", Int) = 1
        [Enum(UnityEngine.Rendering.BlendOp)]   _BlendOpFA  ("ForwardAdd BlendOp", Int) = 4
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" }

        HLSLINCLUDE
            #pragma skip_variants LIGHTMAP_ON DYNAMICLIGHTMAP_ON LIGHTMAP_SHADOW_MIXING SHADOWS_SHADOWMASK DIRLIGHTMAP_COMBINED

            sampler2D _MainTex;
            float4  _MainTex_ST;
            float   _ShadowThreshold;
            uint    _ReceiveShadow;

            // [OpenLit] Properties for lighting
            float   _AsUnlit;
            float   _VertexLightStrength;
            float   _LightMinLimit;
            float   _LightMaxLimit;
            float   _BeforeExposureLimit;
            float   _MonochromeLighting;
            float   _AlphaBoostFA;
            float4  _LightDirectionOverride;
        ENDHLSL

        Pass
        {
            Tags {"LightMode" = "ForwardBase"}

            BlendOp [_BlendOp], Add
            Blend [_SrcBlend] [_DstBlend], One OneMinusSrcAlpha

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_fwdbase
            #pragma multi_compile_fog
            #pragma shader_feature_local _ _PACK_LIGHTDATAS
            #if defined(SHADER_API_GLES)
                #undef _PACK_LIGHTDATAS
            #endif

            #include "UnityCG.cginc"
            #include "Lighting.cginc"
            #include "AutoLight.cginc"

            // [OpenLit] Include this
            #include "core.hlsl"

            struct appdata
            {
                float4 vertex   : POSITION;
                float2 uv       : TEXCOORD0;
                float2 uv1      : TEXCOORD1;
                float3 normalOS : NORMAL;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct v2f
            {
                float4 pos          : SV_POSITION;
                float3 positionWS   : TEXCOORD0;
                float2 uv           : TEXCOORD1;
                float3 normalWS     : TEXCOORD2;
                // [OpenLit] Add light datas
                #if defined(_PACK_LIGHTDATAS)
                    nointerpolation uint3 lightDatas : TEXCOORD3;
                    UNITY_FOG_COORDS(4)
                    UNITY_LIGHTING_COORDS(5, 6)
                    #if !defined(LIGHTMAP_ON) && UNITY_SHOULD_SAMPLE_SH
                        float3 vertexLight  : TEXCOORD7;
                    #endif
                #else
                    nointerpolation float3 lightDirection : TEXCOORD3;
                    nointerpolation float3 directLight : TEXCOORD4;
                    nointerpolation float3 indirectLight : TEXCOORD5;
                    UNITY_FOG_COORDS(6)
                    UNITY_LIGHTING_COORDS(7, 8)
                    #if !defined(LIGHTMAP_ON) && UNITY_SHOULD_SAMPLE_SH
                        float3 vertexLight  : TEXCOORD9;
                    #endif
                #endif
                UNITY_VERTEX_OUTPUT_STEREO
            };

            v2f vert(appdata v)
            {
                v2f o;
                UNITY_INITIALIZE_OUTPUT(v2f,o);
                UNITY_SETUP_INSTANCE_ID(v);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);

                o.positionWS    = mul(unity_ObjectToWorld, float4(v.vertex.xyz, 1.0));
                o.pos           = UnityWorldToClipPos(o.positionWS);
                o.uv            = TRANSFORM_TEX(v.uv, _MainTex);
                o.normalWS      = UnityObjectToWorldNormal(v.normalOS);
                UNITY_TRANSFER_FOG(o,o.pos);
                UNITY_TRANSFER_LIGHTING(o,v.uv1);

                // [OpenLit] Calculate and copy vertex lighting
                #if !defined(LIGHTMAP_ON) && UNITY_SHOULD_SAMPLE_SH && defined(VERTEXLIGHT_ON)
                    o.vertexLight = ComputeAdditionalLights(o.positionWS, o.pos) * _VertexLightStrength;
                    o.vertexLight = min(o.vertexLight, _LightMaxLimit);
                #endif

                // [OpenLit] Calculate and copy light datas
                OpenLitLightDatas lightDatas;
                ComputeLights(lightDatas, _LightDirectionOverride);
                CorrectLights(lightDatas, _LightMinLimit, _LightMaxLimit, _MonochromeLighting, _AsUnlit);
                #if defined(_PACK_LIGHTDATAS)
                    PackLightDatas(o.lightDatas, lightDatas);
                #else
                    o.lightDirection    = lightDatas.lightDirection;
                    o.directLight       = lightDatas.directLight;
                    o.indirectLight     = lightDatas.indirectLight;
                #endif

                return o;
            }

            half4 frag(v2f i) : SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(i);
                UNITY_LIGHT_ATTENUATION(attenuation, i, i.positionWS);

                // [OpenLit] Copy light datas from the input
                OpenLitLightDatas lightDatas;
                #if defined(_PACK_LIGHTDATAS)
                    UnpackLightDatas(lightDatas, i.lightDatas);
                #else
                    lightDatas.lightDirection   = i.lightDirection;
                    lightDatas.directLight      = i.directLight;
                    lightDatas.indirectLight    = i.indirectLight;
                #endif

                float3 N = normalize(i.normalWS);
                float3 L = lightDatas.lightDirection;
                float NdotL = dot(N,L);
                float factor = NdotL > _ShadowThreshold ? 1 : 0;
                if(_ReceiveShadow) factor *= attenuation;

                half4 col = tex2D(_MainTex, i.uv);
                half3 albedo = col.rgb;
                col.rgb *= lerp(lightDatas.indirectLight, lightDatas.directLight, factor);
                #if !defined(LIGHTMAP_ON) && UNITY_SHOULD_SAMPLE_SH
                    col.rgb += albedo.rgb * i.vertexLight;
                    col.rgb = min(col.rgb, albedo.rgb * _LightMaxLimit);
                #endif
                UNITY_APPLY_FOG(i.fogCoord, col);
                return col;
            }
            ENDHLSL
        }

        Pass
        {
            Tags {"LightMode" = "ForwardAdd"}

            // [OpenLit] ForwardAdd uses "BlendOp Max" to avoid overexposure
            BlendOp [_BlendOpFA], Add
            Blend [_SrcBlendFA] [_DstBlendFA], Zero One

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_fwdadd
            #pragma multi_compile_fog

            #include "UnityCG.cginc"
            #include "Lighting.cginc"
            #include "AutoLight.cginc"

            #include "core.hlsl"

            struct appdata
            {
                float4 vertex   : POSITION;
                float2 uv       : TEXCOORD0;
                float2 uv1      : TEXCOORD1;
                float3 normalOS : NORMAL;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct v2f
            {
                float4 pos          : SV_POSITION;
                float3 positionWS   : TEXCOORD0;
                float2 uv           : TEXCOORD1;
                float3 normalWS     : TEXCOORD2;
                UNITY_FOG_COORDS(3)
                UNITY_LIGHTING_COORDS(4, 5)
                UNITY_VERTEX_OUTPUT_STEREO
            };

            v2f vert(appdata v)
            {
                v2f o;
                UNITY_INITIALIZE_OUTPUT(v2f,o);
                UNITY_SETUP_INSTANCE_ID(v);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);

                o.positionWS    = mul(unity_ObjectToWorld, float4(v.vertex.xyz, 1.0));
                o.pos           = UnityWorldToClipPos(o.positionWS);
                o.uv            = TRANSFORM_TEX(v.uv, _MainTex);
                o.normalWS      = UnityObjectToWorldNormal(v.normalOS);
                UNITY_TRANSFER_FOG(o,o.pos);
                UNITY_TRANSFER_LIGHTING(o,v.uv1);
                return o;
            }

            half4 frag(v2f i) : SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(i);
                UNITY_LIGHT_ATTENUATION(attenuation, i, i.positionWS);
                float3 N = normalize(i.normalWS);
                float3 L = UnityWorldSpaceLightDir(i.positionWS);
                float NdotL = dot(N,L);
                float factor = NdotL > _ShadowThreshold ? 1 : 0;

                half4 col = tex2D(_MainTex, i.uv);
                col.rgb *= lerp(0.0, OPENLIT_LIGHT_COLOR, factor * attenuation);
                UNITY_APPLY_FOG(i.fogCoord, col);

                // [OpenLit] Premultiply (only for transparent materials)
                col.rgb *= saturate(col.a * _AlphaBoostFA);

                return col;
            }
            ENDHLSL
        }
    }

    // Enable ShadowCaster by fallback to Standard
    Fallback "Standard"
}
