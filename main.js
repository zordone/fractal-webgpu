import { getSceneViewMatrix } from "./camera.js";

const fps = document.querySelector("#fps");

// canvas setup
const canvas = document.querySelector("#canvas");
window.onresize = () => {
  canvas.width = window.innerWidth;
  canvas.height = window.innerHeight;
};

// params from the ui
const uiParams = {
  zoom: document.querySelector("#paramZoom"),
  blob: document.querySelector("#paramBlob"),
  spike: document.querySelector("#paramSpike"),
  color: document.querySelector("#paramColor"),
};

// convert 0..1 hue to rgb with fixed saturation and lightness
const hueToColor = (hue) => {
  hue *= 360;
  const sat = 0.6;
  const lig = 0.55;
  const k = (n) => (n + hue / 30) % 12;
  const a = sat * Math.min(lig, 1 - lig);
  const f = (n) =>
    lig - a * Math.max(-1, Math.min(k(n) - 3, Math.min(9 - k(n), 1)));
  return [0, 8, 4].map(f);
};

async function main() {
  window.onresize();
  const code = await fetch("./shaders.wgsl").then((res) => res.text());

  // get a GPU device and a context for the canvas
  const adapter = await navigator.gpu.requestAdapter();
  const device = await adapter.requestDevice();
  const context = canvas.getContext("webgpu");
  context.configure({
    device: device,
    format: navigator.gpu.getPreferredCanvasFormat(),
    alphaMode: "premultiplied",
  });

  // compile shaders
  const shaderModule = device.createShaderModule({ code });

  // create pipeline
  const pipeline = device.createRenderPipeline({
    vertex: {
      module: shaderModule,
      entryPoint: "vs_main",
    },
    fragment: {
      module: shaderModule,
      entryPoint: "fs_main",
      targets: [{ format: navigator.gpu.getPreferredCanvasFormat() }],
    },
    primitive: {
      topology: "triangle-strip",
    },
    layout: "auto",
  });

  // create uniform buffer
  const uniformBuffer = device.createBuffer({
    size: 128,
    usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST,
  });

  // bind the uniform buffer to the render pipeline
  pipeline.bindGroupLayouts = [
    device.createBindGroupLayout({
      entries: [
        {
          binding: 0,
          visibility: GPUShaderStage.VERTEX,
          buffer: { type: "uniform" },
        },
      ],
    }),
  ];

  pipeline.bindGroup = [
    device.createBindGroup({
      layout: pipeline.getBindGroupLayout(0),
      entries: [
        {
          binding: 0,
          resource: { buffer: uniformBuffer },
        },
      ],
    }),
  ];

  // render loop
  let frame = 0;
  function render() {
    // params
    const imageWidth = canvas.width;
    const imageHeight = canvas.height;
    const fov = 62 - uiParams.zoom.value * 50;
    const sceneCenter = [-1.5, 0.4, 2.0]; // XY is rotation, Z is zoom
    // camera position/rotation
    const sceneViewMatrix = getSceneViewMatrix(sceneCenter);
    // put custom params into uniform buffer, aligned to 16 bytes
    const params = new Float32Array([
      ...sceneViewMatrix,
      // ---
      imageWidth,
      imageHeight,
      fov,
      frame,
      // ---
      ...sceneCenter,
      uiParams.blob.value,
      // ---
      uiParams.spike.value,
      0, // temp1,
      0, // temp2,
      0, // temp3,
      // ---
      ...hueToColor(uiParams.color.value),
    ]);
    device.queue.writeBuffer(
      uniformBuffer,
      0,
      params.buffer,
      params.byteOffset,
      params.byteLength
    );
    // render pass
    const commandEncoder = device.createCommandEncoder();
    const renderPassDescriptor = {
      colorAttachments: [
        {
          clearValue: { r: 0.0, g: 0.0, b: 0.0, a: 0.0 }, // transparent bg
          loadOp: "clear",
          storeOp: "store",
          view: context.getCurrentTexture().createView(),
        },
      ],
    };
    const passEncoder = commandEncoder.beginRenderPass(renderPassDescriptor);
    passEncoder.setPipeline(pipeline);
    passEncoder.setBindGroup(0, pipeline.bindGroup[0]);
    passEncoder.draw(4, 1, 0, 0);
    passEncoder.end();
    device.queue.submit([commandEncoder.finish()]);
    // next frame
    frame += 1;
    requestAnimationFrame(render);
  }

  // FPS meter
  let previousFpsFrame = 0;
  setInterval(() => {
    fps.textContent = frame - previousFpsFrame + " FPS.";
    previousFpsFrame = frame;
  }, 1000);

  // first frame
  render();
}

main().catch(console.error);
