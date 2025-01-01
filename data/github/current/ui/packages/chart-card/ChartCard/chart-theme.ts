import type Highcharts from 'highcharts'
import styles from '../ChartCard.module.css'

type SymbolClass =
  | 'ChartCardSymbol-square'
  | 'ChartCardSymbol-circle'
  | 'ChartCardSymbol-diamond'
  | 'ChartCardSymbol-triangle'
  | 'ChartCardSymbol-triangle-down'

// This is HTML that gets injected into the tooltip for each series.
// Highcharts expects this to be a string and parses out the vars.
const tooltipHeaderFormat =
  // eslint-disable-next-line github/unescaped-html-literal
  '<table style="min-width: 120px;"><tr><th colspan="3" style="color:var(--fgColor-muted, var(--color-fg-muted)); font-weight:var(--base-text-weight-semibold); padding-bottom:2px;">{point.key}</th></tr>'
function tooltipPointFormatter(this: Highcharts.Point) {
  const chartType = this.series?.chart?.options?.chart?.type
  let symbolStyle: string
  const symbol =
    this.series?.options?.marker?.symbol ?? (chartType === 'column' || chartType === 'bar' ? 'square' : 'circle')

  // Determine border color for symbol
  const borderColor = this.options?.borderColor ?? this.series?.options?.borderColor
  // Do not add border for triangle symbols
  const border = borderColor && !symbol.startsWith('triangle') ? `border: 1px solid ${borderColor};` : undefined

  // Check for gradient
  if (this.color && typeof this.color === 'object' && 'stops' in this.color) {
    // Build a CSS linear-gradient from the stops
    const stops = this.color.stops
      .map((stop: Highcharts.GradientColorStopObject) => {
        const pos = stop[0]
        const color = stop[1]
        return `${color} ${pos * 100}%`
      })
      .join(', ')
    // Default to left-right horizontal gradient
    symbolStyle = `background: linear-gradient(0deg, ${stops});
      ${border ?? ''}`
  } else {
    symbolStyle = `background-color: ${typeof this.color === 'string' ? this.color : '#000'};
    ${border ?? ''}`
  }

  const symbolClass = `ChartCardSymbol-${symbol}` as SymbolClass

  // eslint-disable-next-line github/unescaped-html-literal
  return `<tr><td style="padding-top:var(--base-size-4)"><span class="${styles.ChartCardSymbol} ${
    styles[symbolClass as keyof typeof styles]
  }" style="${symbolStyle}"></span> ${
    this.series.name
  }</td><td style="text-align: right; padding-top:var(--base-size-4);"><strong>${this.y}</strong></td></tr>`
}

const tooltipFooterFormat = '</table>'

export const yAxisConfig: Highcharts.YAxisOptions = {
  tickWidth: 0,
  lineWidth: 0,
  gridLineColor: 'var(--borderColor-muted)',
  gridLineDashStyle: 'Dash',
  lineColor: 'var(--borderColor-default)',
  stackLabels: {
    style: {
      color: 'var(--fgColor-default)',
      fontSize: 'var(--text-body-size-small)',
      textOutline: '1px var(--bgColor-default)',
    },
  },
  labels: {
    style: {
      color: 'var(--fgColor-muted)',
      fontSize: 'var(--text-body-size-small)',
    },
  },
  title: {
    style: {
      color: 'var(--fgColor-muted)',
      fontSize: 'var(--text-body-size-small)',
    },
  },
}

declare module 'highcharts' {
  interface ChartEventsOptions {
    afterA11yUpdate?: () => void
  }
}

const ChartTheme: Highcharts.Options = {
  accessibility: {
    keyboardNavigation: {
      order: ['legend', 'series'],
    },
  },
  colors: [
    'var(--data-blue-color-emphasis, var(--data-blue-color))',
    'var(--data-green-color-emphasis, var(--data-green-color))',
    'var(--data-orange-color-emphasis, var(--data-orange-color))',
    'var(--data-pink-color-emphasis, var(--data-pink-color))',
    'var(--data-yellow-color-emphasis, var(--data-yellow-color))',
    'var(--data-red-color-emphasis, var(--data-red-color))',
    'var(--data-purple-color-emphasis, var(--data-purple-color))',
    'var(--data-auburn-color-emphasis, var(--data-auburn-color))',
    'var(--data-teal-color-emphasis, var(--data-teal-color))',
    'var(--data-gray-color-emphasis, var(--data-gray-color))',
  ],
  caption: {
    align: 'left',
    style: {
      color: 'var(--fgColor-muted)',
    },
    verticalAlign: 'top',
  },
  title: {
    align: 'left',
    style: {
      color: 'var(--fgColor-default)',
    },
    text: undefined,
  },
  tooltip: {
    backgroundColor: 'var(--bgColor-default)',
    borderRadius: 6,
    borderColor: 'var(--borderColor-muted)',
    borderWidth: 1,
    shape: 'rect',
    padding: 10,
    shadow: {
      offsetX: 2,
      offsetY: 2,
      opacity: 0.02,
      width: 4,
      color: 'var(--shadowColor-default)',
    },
    style: {
      color: 'var(--fgColor-default)',
      fontFamily: 'var(--fontStack-sansSerif)',
      fontSize: 'var(--text-body-size-small)',
    },
    useHTML: true,
    headerFormat: tooltipHeaderFormat,
    pointFormatter: tooltipPointFormatter,
    footerFormat: tooltipFooterFormat,
  },
  credits: {
    enabled: false,
  },
  chart: {
    animation: false,
    events: {
      afterA11yUpdate() {
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        const container = (this as any).container
        container?.setAttribute('role', 'application')
      },
    },
    spacing: [4, 0, 4, 0],
    backgroundColor: 'var(--bgColor-default, var(--color-canvas-default))',
    style: {
      fontFamily: 'var(--fontStack-sansSerif)',
      fontSize: 'var(--text-body-size-small)',
      color: 'var(--fgColor-default)',
    },
  },
  legend: {
    itemStyle: {
      fontSize: 'var(--text-body-size-small)',
      font: 'var(--fontStack-sansSerif)',
      color: 'var(--fgColor-default)',
    },
    align: 'left',
    verticalAlign: 'top',
    x: -8,
    y: -12,
    itemHoverStyle: {
      color: 'var(--fgColor-default)',
    },
    title: {
      style: {
        color: 'var(--fgColor-default)',
      },
    },
  },
  navigation: {
    buttonOptions: {
      enabled: false,
    },
  },
  exporting: {
    fallbackToExportServer: false,
  },
  plotOptions: {
    series: {
      animation: false,
    },
    spline: {
      animation: false,
    },
    bar: {
      borderColor: 'var(--bgColor-default)',
    },
    column: {
      borderColor: 'var(--bgColor-default)',
    },
  },
  xAxis: {
    tickWidth: 0,
    lineWidth: 1,
    gridLineColor: 'var(--borderColor-muted)',
    gridLineDashStyle: 'Dash',
    lineColor: 'var(--borderColor-default)',
    labels: {
      style: {
        color: 'var(--fgColor-muted)',
        fontSize: 'var(--text-body-size-small)',
      },
    },
    title: {
      style: {
        color: 'var(--fgColor-muted)',
        fontSize: 'var(--text-body-size-small)',
      },
    },
  },
  yAxis: [yAxisConfig],
}

export default ChartTheme
