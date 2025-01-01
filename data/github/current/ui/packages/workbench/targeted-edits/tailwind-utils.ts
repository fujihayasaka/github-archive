export const tailwindTshirtSizes = [
  'xs',
  'sm',
  'md',
  'lg',
  'xl',
  '2xl',
  '3xl',
  '4xl',
  '5xl',
  '6xl',
  '7xl',
  '8xl',
  '9xl',
]
export const tailwindColors = [
  'red',
  'orange',
  'amber',
  'yellow',
  'lime',
  'green',
  'emerald',
  'teal',
  'cyan',
  'sky',
  'blue',
  'indigo',
  'violet',
  'purple',
  'fuchsia',
  'pink',
  'rose',
  'slate',
  'gray',
  'zinc',
  'neutral',
  'stone',
]

export const tailwindColorShades = ['50', '100', '200', '300', '400', '500', '600', '700', '800', '900', '950']

export const supportedStyles = [
  {tw: 'p', attribute: 'padding'},
  {tw: 'm', attribute: 'margin'},
  {tw: 'text', attribute: 'color'},
  {tw: 'bg', attribute: 'backgroundColor'},
  {tw: 'text', attribute: 'fontSize'},
  {tw: 'rounded', attribute: 'borderRadius'},
  {tw: 'font', attribute: 'fontWeight'},
]

export function parseStyles(className: string = ''): Record<string, {value: string; unit: string}> {
  return className.split(' ').reduce(
    (acc, style) => {
      const [key, value] = style.split('-[')
      if (key && value) {
        const unit = value.endsWith(']') ? value.slice(0, -1) : value
        acc[key] = {value: unit, unit: 'px'}
      }
      return acc
    },
    {} as Record<string, {value: string; unit: string}>,
  )
}

export type TailwindStyle =
  | {
      attribute: string
      value: string
      type: 'absolute-value'
      originalString: string
    }
  | {
      attribute: string
      value: string
      type: 'utility-class'
      originalString: string
    }
  | {
      type: 'unknown'
      originalString: string
    }

function parseTailwindClass(className: string): TailwindStyle {
  const [prefix, value] = className.split('-', 2)

  // Values like p-[10px] or p-[10%], etc.
  if (value && value.startsWith('[') && value.endsWith(']')) {
    return {
      attribute: supportedStyles.find(style => style.tw === prefix)?.attribute || '',
      value: value.slice(1, -1),
      type: 'absolute-value',
      originalString: className,
    }
  }

  return {
    type: 'unknown',
    originalString: className,
  }
}

export function parseTailWindClassName(className: string): TailwindStyle[] {
  return className.split(' ').map(parseTailwindClass)
}
