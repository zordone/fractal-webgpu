# Fractal WebGPU

This is just a little test project to try out WebGPU.

- Rendering the MandelBulb fractal by ray marching its SDF.
- Diffuse shading with specular highlights and ambient occlusion.
- Animated power parameter.
- Rotating light source.
- The scene can be rotated by dragging.
- Additional parameters can be changed by range inputs.

The only library used is gl-matrix to ease the vector math for the scene rotation on the CPU side, everything else is done with pure WGSL.

![Screenshot](screenshot.png)
