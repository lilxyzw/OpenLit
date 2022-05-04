# OpenLit
このライブラリを使用すると、同様のライティングを行うトゥーンシェーダーを簡単に作成できます。このライブラリは[CC0 1.0 Universal](https://creativecommons.org/publicdomain/zero/1.0/)で公開されています。

## ライブラリの目的
- ユーザーが照明を制御できない環境での良好な動作
- Standard Shaderに近い明るさにする
- VRSNSでフレンドと同じ明るさにする
- 1つのアバターで複数の異なるシェーダーを手軽に利用できるようにする

ワールド制作ではユーザーがライティングを制御できるため、ライトマップはサポートしていません。

## core.hlsl
ライティングの関数をまとめたものです。コピーして使用する場合は`.meta`ファイルを削除してUUIDの重複による問題が発生しないようにしてください。

## OpenToonLit.shader
OpenLitライブラリを使用したシェーダーの例です。このシェーダーから必要な部分だけをコピーしてカスタムシェーダーを作成する方法が手軽かもしれません。

## Details
このライブラリは、これらのライティング環境をサポートしています。

- Directional Light
- Point Light
- Spot Light
- Environment Light
- Light Probe

"Environment Light"と"Light Probe"は`ShadeSH9()`を使用して実装されます。ただし、トゥーンシェーダーとしては見栄えが悪くなるため、いくつか変更が加えられています。

### ライト方向

まず、ライト方向は次のように実装されています。`unity_SHAr.xyz`は[球面調和](https://docs.unity3d.com/Manual/LightProbes-TechnicalInformation.html)の偏りを表すため、`ShadeSH9()`の方向はここから擬似的に計算できます。最後に、これとDirectional Lightを合成して最も明るいポイントを計算します。ただし、球面調和でライト方向を制御するケースはめったにないため、ライト方向を上に向けたものをシェーディングに使用します。ライトが全くない場合はマテリアルに設定された`Light Direction Override`にフォールバックします。

https://github.com/lilxyzw/OpenLit/blob/main/Assets/OpenLit/core.hlsl#L65-L86
```HLSL
float3 ComputeCustomLightDirection(float4 lightDirectionOverride)
{
    float3 customDir = length(lightDirectionOverride.xyz) * normalize(mul((float3x3)OPENLIT_MATRIX_M, lightDirectionOverride.xyz));
    return lightDirectionOverride.w ? customDir : lightDirectionOverride.xyz;
}

void ComputeLightDirection(out float3 lightDirection, out float3 lightDirectionForSH9, float4 lightDirectionOverride)
{
    float3 mainDir = OPENLIT_LIGHT_DIRECTION * OpenLitLuminance(OPENLIT_LIGHT_COLOR);
    #if !defined(LIGHTMAP_ON) && UNITY_SHOULD_SAMPLE_SH
        float3 sh9Dir = unity_SHAr.xyz * 0.333333 + unity_SHAg.xyz * 0.333333 + unity_SHAb.xyz * 0.333333;
        float3 sh9DirAbs = float3(sh9Dir.x, abs(sh9Dir.y), sh9Dir.z);
    #else
        float3 sh9Dir = 0;
        float3 sh9DirAbs = 0;
    #endif
    float3 customDir = ComputeCustomLightDirection(lightDirectionOverride);

    lightDirection = normalize(sh9DirAbs + mainDir + customDir);
    lightDirectionForSH9 = sh9Dir + mainDir;
    lightDirectionForSH9 = dot(lightDirectionForSH9,lightDirectionForSH9) < 0.000001 ? 0 : normalize(lightDirectionForSH9);
}
```

### Environment Light / Light Probe
次に、`ShadeSH9()`を計算します。先程計算したライトベクトルを使用して、最も明るいポイントの色を求めます。また、ベクトルを反転して影の色を求めます。ただし、ベクトルをそのまま使用すると非常に明るくなるため、ベクトルを少し小さくします。

https://github.com/lilxyzw/OpenLit/blob/main/Assets/OpenLit/core.hlsl#L95-L121
```HLSL
void ShadeSH9ToonDouble(float3 lightDirection, out float3 shMax, out float3 shMin)
{
    #if !defined(LIGHTMAP_ON) && UNITY_SHOULD_SAMPLE_SH
        float3 N = lightDirection * 0.666666;
        float4 vB = N.xyzz * N.yzzx;
        // L0 L2
        float3 res = float3(unity_SHAr.w,unity_SHAg.w,unity_SHAb.w);
        res.r += dot(unity_SHBr, vB);
        res.g += dot(unity_SHBg, vB);
        res.b += dot(unity_SHBb, vB);
        res += unity_SHC.rgb * (N.x * N.x - N.y * N.y);
        // L1
        float3 l1;
        l1.r = dot(unity_SHAr.rgb, N);
        l1.g = dot(unity_SHAg.rgb, N);
        l1.b = dot(unity_SHAb.rgb, N);
        shMax = res + l1;
        shMin = res - l1;
        #if defined(UNITY_COLORSPACE_GAMMA)
            shMax = OpenLitLinearToSRGB(shMax);
            shMin = OpenLitLinearToSRGB(shMin);
        #endif
    #else
        shMax = 0.0;
        shMin = 0.0;
    #endif
}
```

そして、Directional Lightの色を加算します。

https://github.com/lilxyzw/OpenLit/blob/main/Assets/OpenLit/core.hlsl#L146-L178
```HLSL
void ComputeSHLightsAndDirection(out float3 lightDirection, out float3 directLight, out float3 indirectLight, float4 lightDirectionOverride)
{
    float3 lightDirectionForSH9;
    ComputeLightDirection(lightDirection, lightDirectionForSH9, lightDirectionOverride);
    ShadeSH9ToonDouble(lightDirectionForSH9, directLight, indirectLight);
}

void ComputeLights(out float3 lightDirection, out float3 directLight, out float3 indirectLight, float4 lightDirectionOverride)
{
    ComputeSHLightsAndDirection(lightDirection, directLight, indirectLight, lightDirectionOverride);
    directLight += OPENLIT_LIGHT_COLOR;
}
```

### 頂点ライト
頂点ライトの減衰はForwardAddのものとは異なります。これは、メッシュがライトに範囲外になると突然暗くなるという問題を引き起こします。そこで、ForwardAddで使用される`_LightTexture0`を再現する関数を作成しました。

https://github.com/lilxyzw/OpenLit/blob/main/Assets/OpenLit/core.hlsl#L242-L262
```HLSL
float3 ComputeAdditionalLights(float3 positionWS, float3 positionCS)
{
    float4 toLightX = unity_4LightPosX0 - positionWS.x;
    float4 toLightY = unity_4LightPosY0 - positionWS.y;
    float4 toLightZ = unity_4LightPosZ0 - positionWS.z;

    float4 lengthSq = toLightX * toLightX + 0.000001;
    lengthSq += toLightY * toLightY;
    lengthSq += toLightZ * toLightZ;

    //float4 atten = 1.0 / (1.0 + lengthSq * unity_4LightAtten0);
    float4 atten = saturate(saturate((25.0 - lengthSq * unity_4LightAtten0) * 0.111375) / (0.987725 + lengthSq * unity_4LightAtten0));

    float3 additionalLightColor;
    additionalLightColor =                        unity_LightColor[0].rgb * atten.x;
    additionalLightColor = additionalLightColor + unity_LightColor[1].rgb * atten.y;
    additionalLightColor = additionalLightColor + unity_LightColor[2].rgb * atten.z;
    additionalLightColor = additionalLightColor + unity_LightColor[3].rgb * atten.w;

    return additionalLightColor;
}
```

通常は頂点ライトを加算するべきですが、`Not Important`に設定されたスポットライトで問題が発生します。これは`Spot Angle`が無視され、ポイントライトとして計算されるためです。したがって、複数のSkinned Mesh Rendererを持つアバターでメッシュごとに明るさが異なることになります。本来であればメッシュを1つにまとめる必要がありますが、利便性の問題で多くのユーザーは複数のSkinned Mesh Rendererを使用しています。そのため、頂点ライトの強度はデフォルトで0に設定されています。

### ForwardAdd
ForwardAddの減衰はStandard Shaderと同様に計算されます。ただし、そのまま加算すると激しい白飛びを引き起こします。したがって、この問題を回避するために`BlendOp Max`を使用しています。これにより、Fragment Shaderの出力がクランプされていれば白飛びを防ぐことができます。ただし、このブレンド方法では透過マテリアルで問題が発生するため透明度のブーストを行っています。

https://github.com/lilxyzw/OpenLit/blob/main/Assets/OpenLit/OpenToonLit.shader#L273-L274
```HLSL
// [OpenLit] Premultiply (only for transparent materials)
col.rgb *= saturate(col.a * _AlphaBoostFA);
```

## その他
このライブラリは完璧ではなく、より良い手法があると思います。もし改善のためのアイデアがあれば是非投稿してください。

Special thanks to [poiyomi](https://twitter.com/poiyomi)