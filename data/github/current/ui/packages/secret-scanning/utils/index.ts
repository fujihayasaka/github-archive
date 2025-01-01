export function toPercentString(value: number, total: number, opts: Parameters<typeof toPercentInt>[2] = {}): string {
  return `${toPercentInt(value, total, opts)}%`
}

/**
 * Return a percentage (value/total) as an integer (so 1/2 becomes 50).
 */
export function toPercentInt(value: number, total: number, {floor = false} = {}): number {
  // Resolve total to 1 to prevent divide by 0
  const val = (value / (total || 1)) * 100

  if (floor) return Math.floor(val)
  return Math.round(val)
}
