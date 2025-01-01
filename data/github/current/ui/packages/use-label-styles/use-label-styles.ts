import {useTheme} from '@primer/react'
import {parseToHsla, parseToRgba} from 'color2k'
import {useMemo, type CSSProperties} from 'react'

export const useLabelStyles = (borderWidthPx: number = 1, fillColor: string) => {
  const {colorScheme} = useTheme()

  const isHighContrast = useMemo(() => colorScheme?.includes('high_contrast'), [colorScheme])

  const lightModeStyles = useMemo(
    () => ({
      '--lightness-threshold': '0.453',
      '--border-threshold': '0.96',
      '--background-alpha': '0.20',
      '--border-alpha': 'max(0, min(calc((var(--perceived-lightness) - var(--border-threshold)) * 100), 1))',
      background: 'rgb(var(--label-r), var(--label-g), var(--label-b))',
      color: 'hsl(0deg, 0%, calc(var(--lightness-switch) * 100%))',
      borderWidth: borderWidthPx,
      borderStyle: 'solid',
      borderColor:
        'hsla(var(--label-h), calc(var(--label-s) * 1%), calc((var(--label-l) - 25) * 1%), var(--border-alpha))',
    }),
    [borderWidthPx],
  )

  const darkModeStyles = useMemo(
    () => ({
      '--lightness-threshold': '0.6',
      '--background-alpha': '0.18',
      '--border-alpha': isHighContrast ? '0.9' : '0.3',
      '--lighten-by':
        'calc(((var(--lightness-threshold) - var(--perceived-lightness)) * 100) * var(--lightness-switch))',
      borderWidth: borderWidthPx,
      borderStyle: 'solid',
      background: 'rgba(var(--label-r), var(--label-g), var(--label-b), var(--background-alpha))',
      color: 'hsl(var(--label-h), calc(var(--label-s) * 1%), calc((var(--label-l) + var(--lighten-by)) * 1%))',
      borderColor:
        'hsla(var(--label-h), calc(var(--label-s) * 1%), calc((var(--label-l) + var(--lighten-by)) * 1%), var(--border-alpha))',
    }),
    [isHighContrast, borderWidthPx],
  )

  const labelStyles: CSSProperties = useMemo(() => {
    const [r, g, b] = parseToRgba(fillColor)
    const [h, s, l] = parseToHsla(fillColor)

    return {
      '--label-r': String(r),
      '--label-g': String(g),
      '--label-b': String(b),
      '--label-h': String(Math.round(h)),
      '--label-s': String(Math.round(s * 100)),
      '--label-l': String(Math.round(l * 100)),
      '--perceived-lightness':
        'calc(((var(--label-r) * 0.2126) + (var(--label-g) * 0.7152) + (var(--label-b) * 0.0722)) / 255)',
      '--lightness-switch': 'max(0, min(calc((var(--perceived-lightness) - var(--lightness-threshold)) * -1000), 1))',
      '--border-color': 'var(--borderColor-muted, var(--color-border-subtle))',
      ...(colorScheme?.includes('light') ? lightModeStyles : darkModeStyles),
    }
  }, [fillColor, colorScheme, lightModeStyles, darkModeStyles])

  return labelStyles
}
