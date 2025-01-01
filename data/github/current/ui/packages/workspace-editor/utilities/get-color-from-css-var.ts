// Utility function to convert hex color to RGBA
const hexToRgba = (hex: string, alpha: number) => {
  const match = hex.match(/\w\w/g)
  if (!match) {
    throw new Error('Invalid hex color')
  }
  const [r, g, b] = match.map(c => parseInt(c, 16))
  return `rgba(${r}, ${g}, ${b}, ${alpha})`
}

export const getColorFromCSSVar = (colorVar: string, alpha?: number) => {
  /**
   *  Typical colorVar is of type var(--fgColor-accent, var(--color-accent-fg, #0969da))
   * extract the fallback color which we assume is provided as the last argument in the nest var
   * use regex to get the color
   */
  const color = colorVar.match(/#[0-9a-f]{3,6}/i)?.[0]
  if (!color) {
    return ''
  }
  return color && alpha ? hexToRgba(color, alpha) : color
}
