const PI = 3.14159265359;
const RADIAN = PI / 180.0;
const BAILOUT = 2.0;

// enum for sdf mix mode
const MIX_UNION = 1;
const MIX_INTERSECT = 2;
const MIX_A_MINUS_B = 3;
const MIX_B_MINUS_A = 4;
const MIX_SMOOTH_UNION = 5;

// incoming parameters, aligned to 16 bytes
struct Uniforms {
  // ---
  sceneViewMatrix: mat4x4<f32>,
  // ---
  imageWidth: f32,
  imageHeight: f32,
  fov: f32,
  frame: f32,
};
@group(0) @binding(0)
var<uniform> uniforms: Uniforms;

// struct for one object in the scene
struct Object {
  sdf: f32,
  color: vec3<f32>,
  mix: u32
}

// create an object struct
fn object(sdf: f32, color: vec3<f32>, mix: u32) -> Object {
  var obj: Object;
  obj.sdf = sdf;
  obj.color = color;
  obj.mix = mix;
  return obj;
}

// shortcut for defining a position
fn pos(x: f32, y: f32, z: f32) -> vec3<f32> {
  return vec3<f32>(x, y, z);
}

// shortcut for defining a color
fn color(r: f32, g: f32, b: f32) -> vec3<f32> {
  return vec3<f32>(r, g, b);
}

// cubic smooth minimum
// returns: x = smooth min, y = blending factor
fn smoothMin(a: f32, b: f32, smoothness: f32) -> vec2<f32> {
  let diff = max(smoothness - abs(a - b), 0.0) / smoothness;
  let factor = diff * diff * 0.5;
  let sub = factor * smoothness * 0.5;
  if (a < b) {
    return vec2(a - sub, factor);
  } else {
    return vec2(b - sub, 1.0 - factor);
  }
}

// SDF of a sphere
fn sdfSphere(point: vec3<f32>, center: vec3<f32>, radius: f32) -> f32 {
  return length(point - center) - radius;
}

// SDF of the whole scene
// returns: x = distance, yzw = color
fn sdfScene(point: vec3<f32>) -> vec4<f32> {
  // animated positions
  let x2 = -0.3 + sin(uniforms.frame / 200) * 1.6;
  let y3 =        sin(uniforms.frame / 370) * 1.5;
  let y4 =        cos(uniforms.frame / 513) * 1.4;
  let z5 = -4.0 + sin(uniforms.frame / 597) * 2.5;
  // define the objects in our scene
  const numObjects = 5;
  let objects = array<Object,numObjects>(
    object( // 1
      sdfSphere(point, pos(-0.3, 0, -3.5), 0.6), 
      color(1, 0, 0.5), 
      MIX_SMOOTH_UNION
    ),    
    object( // 2
      sdfSphere(point, pos(x2, 0, -3.1), 0.3),
      color(1, 0.5, 0), 
      MIX_SMOOTH_UNION
    ),
    object( // 3
      sdfSphere(point, pos(0.0, y3, -3), 0.4),
      color(0.5, 0, 1), 
      MIX_SMOOTH_UNION
    ),
    object( // 4
      sdfSphere(point, pos(y4 * 0.1, -y4, -2.8), 0.3),
      color(1, 0.8, 0), 
      MIX_SMOOTH_UNION
    ),
    object( // 5
      sdfSphere(point, pos(0.2, 0.5, z5), 0.9),
      color(0, 0, 1), 
      MIX_A_MINUS_B
    ),
  );
  // go over the objects and mix them
  var distance: f32;
  var color: vec3<f32>;
  for (var index = 0; index < numObjects; index += 1) {
    let obj = objects[index];
    if (index == 0) {
      // no mixing needed for the first object, just set the values
      distance = obj.sdf;
      color = obj.color;
    } else {
      // combine previous results with the current object, depending on the mix mode
      if (obj.mix == MIX_UNION) {
        if (obj.sdf < distance) { color = obj.color; }        
        distance = min(distance, obj.sdf);
      } else if (obj.mix == MIX_INTERSECT) {
        distance = max(distance, obj.sdf); 
      } else if (obj.mix == MIX_A_MINUS_B) {
        distance = max(distance, -obj.sdf); 
      } else if (obj.mix == MIX_B_MINUS_A) {
        distance = max(-distance, obj.sdf); 
        color = obj.color;
      } else if (obj.mix == MIX_SMOOTH_UNION) {
        let sm = smoothMin(distance, obj.sdf, 1.5);
        distance = sm.x;
        color = mix(color, obj.color, sm.y);
      } 
    }
  }
  // final results
  return vec4<f32>(distance, color);
}

// estimate the surface normal at a point by taking the gradient of the SDF
fn estimateSceneNormal(point: vec3<f32>) -> vec3<f32> {
  let distance = vec3<f32>(0.001, 0, 0);
  return normalize(vec3<f32>(
    sdfScene(point + distance.xyy).x - sdfScene(point - distance.xyy).x,
    sdfScene(point + distance.yxy).x - sdfScene(point - distance.yxy).x,
    sdfScene(point + distance.yyx).x - sdfScene(point - distance.yyx).x
  ));
}

// perform ray marching to find intersection
fn rayMarching(rayOrigin: vec3<f32>, rayDirection: vec3<f32>) -> vec4<f32> {
  let maxSteps = 128; // max iterations
  let bailoutDistance = 100.0;
  let epsilon = 0.001; // distance smaller than this is considered a hit
  let lightDirection = normalize(vec3<f32>(3,1,3));
  // march!
  var length = 0.0;
  var step = 0;
  for (step = 0; step < maxSteps; step++) {
    let point = rayOrigin + rayDirection * length;
    // get surface distance and color
    let res = sdfScene(point); 
    let distance = res.x;
    let color = res.yzw;
    if (distance < epsilon) { 
      // calculate color based on the estimated normal of the intersection point
      let normal = estimateSceneNormal(point);
      // compute components
      let lightDot = dot(normal, lightDirection);
      let globalColor = 0.2 * color;
      let diffuseColor = 0.8 * max(lightDot, 0) * color;
      // blinn phong specular
      let toLight = -lightDirection - point;
      let toCamera = -point;
      let blinnPhong = dot(normalize(toLight + toCamera), normal);
      let glossiness = 170.0;
      let specularMix = 0.6;
      let specular = pow(clamp(blinnPhong, 0, 1), glossiness) * specularMix;
      return vec4<f32>(globalColor + diffuseColor + specular, 1);
    }
    length += distance;
    // bailout 
    if (length > bailoutDistance) {
      break;
    }
  }
  // backround with glow
  let glow = f32(step) / f32(maxSteps);
  let glowColor = vec3<f32>(0.9, 0.5, 0.9);
  return vec4<f32>(glowColor * glow, 1);
}

struct Interpolators {
  @builtin(position) pRaster: vec4<f32>,
  @location(0) pCamera: vec4<f32>,
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
  // output
  var output: Interpolators;
  output.pRaster = pClip; // will be converted to raster space automatically
  output.pCamera = pCamera;
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
  );
}