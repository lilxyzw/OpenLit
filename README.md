# OpenLit
This library makes it easy to create toon shaders that do the same lighting. This library is licensed under [CC0 1.0 Universal](https://creativecommons.org/publicdomain/zero/1.0/).

## Purpose of this library
- Good behavior in environments where the user has no control over the lighting
- Make the brightness close to Standard Shader
- Get the same brightness as your friends on VRSNS
- Make it easy to use multiple different shaders with one avatar

Lightmaps are not supported. This is because the user has control over the lighting in the world.

## core.hlsl
This file is a library that contains lighting functions.

## OpenToonLit.shader
This file is a shader example using OpenLit Library.