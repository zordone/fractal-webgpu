const PI = 3.14159265359;
const RADIAN = PI / 180.0;
const BAILOUT = 2.0;

// incoming parameters, aligned to 16 bytes
struct Uniforms {
    // ---
    sceneViewMatrix: mat4x4<f32>,
    // ---
    imageWidth: f32,
    imageHeight: f32,
    fov: f32,
    frame: f32,
    // ---
    sceneCenter: vec3<f32>,
    blob: f32,
    // ---
    spike: f32,
    detail: f32,
    temp1: f32,
    temp2: f32,
    // ---
    color: vec3<f32>,
};
@group(0) @binding(0)
var<uniform> uniforms: Uniforms;

// signed distance function for a mandelbulb fractal
fn sdfMandel(point0: vec3<f32>, power: f32) -> f32 {
  // the mandelbulb is at scene scene center. translate to origin.
  let point = point0 - uniforms.sceneCenter;
  // params
  let blob = 1 - uniforms.blob;
  let spike = uniforms.spike * PI / 2;
  // iterate to find distance
  var z = point;
  var dr = 1.0;
  var dist: f32;    
  for (var step = 0; step < 16; step++) {
    dist = length(z);        
    if (dist > BAILOUT) { break; }
    // to polar coordinates
    let theta = acos(z.z / dist) * power * blob;
    let phi = atan2(z.y, z.x) * power;
    // scale and rotate
    let distPowMinusOne = pow(dist, power - 1.0);
    let zr = distPowMinusOne * dist;
    dr = distPowMinusOne * power * dr + 1.0;
    // back to cartesian coordinates
    let sinTheta = sin(theta);
    z = zr * vec3<f32>(sinTheta * cos(phi), sin(phi + spike) * sinTheta, cos(theta));
    z += point;
  }
  return 0.5 * log(dist) * dist / dr;
}

// estimate the surface normal at p by taking the gradient of the SDF
fn estimateNormal(point: vec3<f32>, power: f32) -> vec3<f32> {
  let distance = vec3<f32>(0.001, 0, 0);
  return normalize(vec3<f32>(
    sdfMandel(point + distance.xyy, power) - sdfMandel(point - distance.xyy, power),
    sdfMandel(point + distance.yxy, power) - sdfMandel(point - distance.yxy, power),
    sdfMandel(point + distance.yyx, power) - sdfMandel(point - distance.yyx, power)
  ));
}

// ambient occlusion from a hit point along the normal
fn ambientOcclusion(point: vec3<f32>, normal: vec3<f32>, power: f32) -> f32 {
  let steps = 5;
  let start = 0.02;
  let end = 0.1;
  var total = 0.0;
  for (var i = 0; i < steps; i++) {
    let t = mix(start, end, f32(i) / f32(steps - 1));
    total += t * sdfMandel(point + t * normal, power);
  }
  return clamp(1.0 - 50.0 * total, 0.0, 1.0);
}

// perform ray marching to find intersection
fn rayMarching(rayOrigin: vec3<f32>, rayDirection: vec3<f32>, lightPosition: vec3<f32>, power: f32) -> vec4<f32> {
  let maxSteps = 65; // max iterations
  let epsilon = uniforms.detail; // distance smaller than this is considered a hit
  let baseColor = uniforms.color;
  // march!
  var length = 0.0;
  for (var step = 0; step < maxSteps; step++) {
    let point = rayOrigin + rayDirection * length;
    let distance = sdfMandel(point, power); 
    if (distance < epsilon) { 
      // calculate color based on the estimated normal of the intersection point
      let normal = estimateNormal(point, power);
      // normalize light direction
      let lightDir: vec3<f32> = normalize(lightPosition - point);        
      // compute components
      let lightDot = dot(normal, lightDir);
      let globalColor = 0.80 * baseColor;
      let aoColor = 0.85 * ambientOcclusion(point, normal, power) * baseColor;
      let diffuseColor = max(lightDot, 0) * baseColor;
      let specularSmooth = 0.93;
      let specularAmount = 0.9;
      let specularColor = vec3<f32>(1, 1, 1);
      let specularMix = max(lightDot - specularSmooth, 0) / (1.0 - specularSmooth) * specularAmount;
      let sumColor = vec3<f32>(globalColor + diffuseColor - aoColor);
      return vec4<f32>(mix(sumColor, specularColor, specularMix), 1);
    }
    length += distance;
  }
  // max steps reached, return transparent
  return vec4<f32>(0, 0, 0, 0);
}

struct Interpolators {
  @builtin(position) pRaster: vec4<f32>,
  @location(0) pCamera: vec4<f32>,
  @location(1) @interpolate(flat) lightPosition: vec3<f32>,
  @location(2) @interpolate(flat) power: f32,  
};

@vertex
fn vs_main(@builtin(vertex_index) vertexIndex : u32) -> Interpolators {
  // params
  let aspectRatio = uniforms.imageWidth / uniforms.imageHeight;
  let tanFov = tan(uniforms.fov * RADIAN / 2);
  let pixelCenterOffset = 0.5;
  let imagePlaneZ = -1.0;
  // triangle strip, forming a quad, covering the whole view
  let vertices = array<vec2<f32>,4>(
    vec2<f32>(-1, -1),
    vec2<f32>(-1,  1),
    vec2<f32>( 1, -1),
    vec2<f32>( 1,  1)
  );
  let vertex = vertices[vertexIndex];
  // current vertex in clip space
  let pClip = vec4<f32>(vertex, 0, 1);
  // current vertex in camera space
  let pCamera = vec4<f32>(
    (pixelCenterOffset / uniforms.imageWidth ) + vertex.x * tanFov * aspectRatio,
    (pixelCenterOffset / uniforms.imageHeight) + vertex.y * tanFov,
    imagePlaneZ, 
    1.0
  );
  // light position for the current frame - rotate around the scene center
  let lightDistance = 20.0;
  let lightAngle = PI / 400 * uniforms.frame;
  let lightPosition = vec3<f32>(
    uniforms.sceneCenter.x + lightDistance * sin(lightAngle),
    uniforms.sceneCenter.y - lightDistance * cos(lightAngle),
    uniforms.sceneCenter.z 
  );
  // power for the current frame
  let powerLoopMin = 5.0;
  let powerLoopMax = 18.0;
  let powerLoopFrames = 120.0 * 90;
  let powerLoopAngle = PI * 2.0 / powerLoopFrames * uniforms.frame;
  let power = powerLoopMin + (cos(PI + powerLoopAngle) + 1) / 2 * (powerLoopMax - powerLoopMin);  
  // output
  var output: Interpolators;
  output.pRaster = pClip; // will be converted to raster space automatically
  output.pCamera = pCamera;
  output.lightPosition = lightPosition;
  output.power = power;
  return output;
}

@fragment
fn fs_main(input: Interpolators) -> @location(0) vec4<f32> {
  // current fragment in camera space
  let pCamera = input.pCamera;
  // ray for the current fragment, with scene rotation
  // has to be here. interpolated vertex shader values are not precise enough.
  let cameraOrigin = vec4<f32>(0.0, 0.0, 0.0, 1.0);
  let rayOrigin = uniforms.sceneViewMatrix * cameraOrigin;
  let rayDirection = normalize(uniforms.sceneViewMatrix * (pCamera - cameraOrigin));
  // ray marching
  return rayMarching(
    rayOrigin.xyz, 
    rayDirection.xyz, 
    input.lightPosition,
    input.power
  );
}