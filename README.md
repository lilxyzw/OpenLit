# OpenLit
This library makes it easy to create toon shaders that do the same lighting. This library is licensed under [CC0 1.0 Universal](https://creativecommons.org/publicdomain/zero/1.0/).

## Purpose of this library
- Good behavior in environments where the user has no control over the lighting
- Make the brightness close to Standard Shader
- Make the brightness the same as your friends in VRSNS
- Make it easy to use multiple different shaders with one avatar

Lightmaps are not supported. This is because the user has control over the lighting in the world.

## core.hlsl
This file is a library that contains lighting functions. When copying and using it, delete `.meta` so that the problem due to duplicate UUID does not occur.

## OpenToonLit.shader
This file is a shader example using OpenLit Library. It may be easier to create a custom shader by copying only what you need from this shader.

## Others
This library isn't perfect and there may be better lighting calculations. So welcome your ideas for improvement.

Special thanks to [poiyomi](https://twitter.com/poiyomi)