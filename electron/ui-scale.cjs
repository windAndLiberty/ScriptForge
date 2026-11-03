const MIN_UI_SCALE = 0.85;
const MAX_UI_SCALE = 1.3;
const UI_SCALE_STEPS = [0.85, 0.9, 1, 1.1, 1.2, 1.3];

function normalizeUiScale(value) {
  const numeric = Number(value);
  if (!Number.isFinite(numeric)) return 1;
  const clamped = Math.max(MIN_UI_SCALE, Math.min(MAX_UI_SCALE, numeric));
  return UI_SCALE_STEPS.reduce(
    (nearest, candidate) =>
      Math.abs(candidate - clamped) < Math.abs(nearest - clamped)
        ? candidate
        : nearest,
    1,
  );
}

function applyUiScale(webContents, value) {
  const scale = normalizeUiScale(value);
  if (!webContents || webContents.isDestroyed()) {
    throw new Error("The application window is no longer available.");
  }
  webContents.setZoomFactor(scale);
  return scale;
}

module.exports = {
  MAX_UI_SCALE,
  MIN_UI_SCALE,
  UI_SCALE_STEPS,
  applyUiScale,
  normalizeUiScale,
};
