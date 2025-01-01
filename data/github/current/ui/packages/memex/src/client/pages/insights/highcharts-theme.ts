import type {ColorCodingConfig} from '@github-ui/insights-charts'

import {highChartTypes, type MemexChartType} from '../../api/charts/contracts/api'
import {sanitizeTextInputHtmlString} from '../../helpers/sanitize'

// These colors are taken from the ChartTheme in @github-ui/chart-card.
export const colors = (style: string = 'emphasis') => [
  `var(--data-blue-color-${style}, var(--data-blue-color))`,
  `var(--data-green-color-${style}, var(--data-green-color))`,
  `var(--data-orange-color-${style}, var(--data-orange-color))`,
  `var(--data-pink-color-${style}, var(--data-pink-color))`,
  `var(--data-yellow-color-${style}, var(--data-yellow-color))`,
  `var(--data-red-color-${style}, var(--data-red-color))`,
  `var(--data-purple-color-${style}, var(--data-purple-color))`,
  `var(--data-auburn-color-${style}, var(--data-auburn-color))`,
  `var(--data-teal-color-${style}, var(--data-teal-color))`,
  `var(--data-gray-color-${style}, var(--data-gray-color))`,
]

// The DataSetConfig type is from @github-ui/insights-charts.
type DataSetConfig = ColorCodingConfig[keyof ColorCodingConfig]

export const styleForChartType = (memexChartType: MemexChartType, indexOrColorSet: number | DataSetConfig) => {
  const type = highChartTypes[memexChartType]

  // Setting a default to appease the type checker.
  // If a colorSet is passed, we'll use that instead. If an index is passed, we'll reassign this value.
  let index = 0
  let colorSet
  if (typeof indexOrColorSet === 'number') {
    // Cycle through the colors if the index is greater than the number of colors.
    index = indexOrColorSet % colors().length
  } else {
    colorSet = indexOrColorSet
  }

  // Setting fallback values to appease the type checker.
  const muted = colorSet?.backgroundColor ?? colors('muted')[index] ?? 'var(--data-blue-color)'
  const emphasis = colorSet?.borderColor ?? colors('emphasis')[index] ?? 'var(--data-blue-color)'

  // Highcharts ignores the opacity attribute if color is explicitly set, so we need to use rgb(a) to set opacity.
  // To handle var colors, we use the relative color (`rgb(from color...)`) syntax.
  // This is not supported in all browser versions, so check for support and default to full opacity if needed.
  let fillColor = muted
  if (window.CSS?.supports('color', `rgb(from ${muted} r g b / 0.5)`)) {
    fillColor = `rgb(from ${muted} r g b / 0.5)`
  }

  switch (type) {
    case 'bar':
    case 'column': {
      return {
        color: fillColor,
        borderColor: emphasis,
        borderWidth: 2,
      }
    }
    case 'area':
    case 'areaspline':
      return {
        fillColor,
        color: emphasis,
      }
    case 'line':
    default:
      return {
        color: emphasis,
      }
  }
}

export function getLegendLabel(options: Highcharts.PointOptionsObject, name: string): string {
  // matching the colors for the chart type like in styleForChartType above
  const backgroundColor = options.fillColor ?? options.color
  const borderColor = options.borderColor ?? options.color
  // eslint-disable-next-line github/unescaped-html-literal, @typescript-eslint/no-base-to-string
  const symbol = `<span style="width: 14px; height: 14px; border-radius: 50%; position: absolute; background-color: ${backgroundColor}; border: 1px solid ${borderColor};"></span>`
  // eslint-disable-next-line github/unescaped-html-literal
  const label = `<span style="padding-left: 20px">${sanitizeTextInputHtmlString(name)}</span>`
  return `${symbol} ${label}`
}
