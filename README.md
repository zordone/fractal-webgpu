# Fractal WebGPU

This is just a little test project to try out WebGPU.

## Features

- Rendering the MandelBulb fractal by ray marching its SDF.
- Diffuse shading with specular highlights and ambient occlusion.
- Animated power parameter.
- Rotating light source.
- The scene can be rotated by dragging.
- Additional parameters can be changed by range inputs.

The only library used is gl-matrix to ease the vector math for the scene rotation on the CPU side, everything else is done with pure WGSL.

## Demo

Open it in a browser with WebGPU support. [Which are those?](https://caniuse.com/webgpu)

[Live Demo.](https://zordone.github.io/fractal-webgpu/)

## Screenshot

![Screenshot](screenshot.png)
