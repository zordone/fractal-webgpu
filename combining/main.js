const { mat4 } = glMatrix;

// canvas setup
const canvas = document.querySelector("#canvas");
window.onresize = () => {
  canvas.width = window.innerWidth;
  canvas.height = window.innerHeight;
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
    const fov = 80;
    const cameraPosition = [0, 0, 0];
    const sceneCenter = [0.0, 0.5, -3.0]; // XY is rotation, Z is zoom
    const sceneCenterInverse = sceneCenter.map((x) => -x);
    // camera position/rotation
    const sceneViewMatrix = mat4.create();
    mat4.lookAt(sceneViewMatrix, cameraPosition, sceneCenter, [0, 1, 0]);
    mat4.translate(sceneViewMatrix, sceneViewMatrix, sceneCenter);
    mat4.rotateX(
      sceneViewMatrix,
      sceneViewMatrix,
      ((Math.PI / 180) * frame) / 13
    );
    mat4.rotateY(
      sceneViewMatrix,
      sceneViewMatrix,
      -((Math.PI / 180) * frame) / 7
    );
    mat4.translate(sceneViewMatrix, sceneViewMatrix, sceneCenterInverse);
    mat4.invert(sceneViewMatrix, sceneViewMatrix);
    // put custom params into uniform buffer, aligned to 16 bytes
    const params = new Float32Array([
      ...sceneViewMatrix,
      // ---
      imageWidth,
      imageHeight,
      fov,
      frame,
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

  // first frame
  render();
}

main().catch(console.error);
