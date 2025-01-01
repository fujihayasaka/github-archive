import type {IconColor} from '@github-ui/pacer/Icon'

/**
 * Picks a color based on a string input using a hash function
 * @param str The input string
 * @param colors Array of available colors to choose from
 * @returns A color from the provided array
 */
export function pickColorBasedOnString(str: string, colors: IconColor[]): IconColor {
  function hashString(s: string): number {
    let hash = 0
    for (let i = 0; i < s.length; i++) {
      hash = (hash * 31 + s.charCodeAt(i)) % 1000000007
    }
    return hash
  }

  const hash = hashString(str)
  const index = hash % colors.length

  return colors[index] as IconColor
}

/**
 * Available colors for use with icons
 */
export const availableColors: IconColor[] = [
  'auburn',
  'blue',
  'brown',
  'coral',
  'cyan',
  'gray',
  'green',
  'indigo',
  'lemon',
  'lime',
  'olive',
  'orange',
  'pine',
  'pink',
  'plum',
  'purple',
  'red',
  'teal',
  'yellow',
]
