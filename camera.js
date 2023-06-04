const { mat4 } = glMatrix;

const cameraRotation = { x: 0, y: 0 };
const cameraPosition = [0, 0, 0];

const canvas = document.querySelector("#canvas");

// mouse drag state
let isDragging = false;
let prevMousePosition = { x: 0, y: 0 };

// drag logic
canvas.addEventListener("mousedown", (e) => {
  isDragging = true;
  prevMousePosition = { x: e.clientX, y: e.clientY };
});

canvas.addEventListener("mousemove", (e) => {
  if (!isDragging) return;

  const dx = e.clientX - prevMousePosition.x;
  const dy = e.clientY - prevMousePosition.y;

  cameraRotation.y += dx * 0.003;
  cameraRotation.x -= dy * 0.003;

  prevMousePosition = { x: e.clientX, y: e.clientY };
});

canvas.addEventListener("mouseup", (e) => {
  isDragging = false;
});

// create model-view matrix
const sceneViewMatrix = mat4.create();

// get the scene view matrix for the current camera position/rotation
export const getSceneViewMatrix = (sceneCenter) => {
  const sceneCenterInverse = sceneCenter.map((x) => -x);
  mat4.lookAt(sceneViewMatrix, cameraPosition, sceneCenter, [0, 1, 0]);
  mat4.translate(sceneViewMatrix, sceneViewMatrix, sceneCenter);
  mat4.rotateX(sceneViewMatrix, sceneViewMatrix, cameraRotation.x);
  mat4.rotateY(sceneViewMatrix, sceneViewMatrix, cameraRotation.y);
  mat4.translate(sceneViewMatrix, sceneViewMatrix, sceneCenterInverse);
  mat4.invert(sceneViewMatrix, sceneViewMatrix);
  return sceneViewMatrix;
};
