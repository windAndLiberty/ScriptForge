export const UI_SCALE_STEPS = [0.85, 0.9, 1, 1.1, 1.2, 1.3] as const;

export function normalizeUiScale(value: unknown) {
  const numeric = Number(value);
  if (!Number.isFinite(numeric)) return 1;
  return UI_SCALE_STEPS.reduce(
    (nearest, candidate) =>
      Math.abs(candidate - numeric) < Math.abs(nearest - numeric)
        ? candidate
        : nearest,
    1,
  );
}

export function stepUiScale(current: number, direction: -1 | 1) {
  const normalized = normalizeUiScale(current);
  const index = UI_SCALE_STEPS.indexOf(
    normalized as (typeof UI_SCALE_STEPS)[number],
  );
  const nextIndex = Math.max(
    0,
    Math.min(UI_SCALE_STEPS.length - 1, index + direction),
  );
  return UI_SCALE_STEPS[nextIndex];
}
