export function lerp(start: number, target: number, easing: number) {
  return start + (target - start) * easing
}

export function smoothstep(edge0: number, edge1: number, x: number) {
  if (x <= edge0) return 0.0
  if (x >= edge1) return 1.0

  const t = Math.min(1.0, Math.max((x - edge0) / (edge1 - edge0), 0.0))
  return t * t * (3.0 - 2.0 * t)
}

export function getProgress(start: number, end: number, value: number) {
  return Math.max(0.0, Math.min(1.0, (value - start) / (end - start)))
}

export function cubicOut(t: number) {
  const f = t - 1.0
  return f * f * f + 1.0
}

export function cubicIn(t: number) {
  return t * t * t
}

export function expoOut(t: number) {
  return t === 1.0 ? t : 1.0 - Math.pow(2.0, -10.0 * t)
}

export function cubicInOut(t: number) {
  return t < 0.5 ? 4.0 * t * t * t : 0.5 * Math.pow(2.0 * t - 2.0, 3.0) + 1.0
}
