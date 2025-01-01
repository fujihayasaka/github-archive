export function randomLabelWidth(): string {
  const min = 40
  const max = 60
  const width = Math.floor(Math.random() * (max - min + 1) + min)
  return `${width}%`
}
