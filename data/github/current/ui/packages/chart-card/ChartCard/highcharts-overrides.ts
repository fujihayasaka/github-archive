import {announce} from '@github-ui/aria-live'
import Highcharts, {type WrapProceedFunction} from 'highcharts'
import Highstock from 'highcharts/highstock'

/**
 * Monkey patches Highcharts methods for enhanced accessibility experience.
 */
export const applyHighchartsOverrides = () => {
  overrideHighlightBehavior()
  overrideGetDataRows()
}

declare module 'highcharts' {
  export const SeriesAccessibilityDescriber: {
    defaultPointDescriptionFormatter: (point: Highcharts.Point) => string
  }
}

/**
 * Overrides the point-highlight behavior with the addition of a live region announcement, enabling
 * point-by-point navigation for screen reader users.
 * See: https://github.com/highcharts/highcharts/issues/22149#issuecomment-2478399887.
 */
function overrideHighlightBehavior() {
  const defaultPointDescriptionEnabledThreshold =
    Highcharts.getOptions().accessibility?.series?.pointDescriptionEnabledThreshold

  for (const chartsModule of [Highstock, Highcharts]) {
    chartsModule.wrap(
      chartsModule.Point.prototype,
      'highlight',
      function (this: Highcharts.Point | Highstock.Point, proceed: WrapProceedFunction, ...rest) {
        // Run the original function and store the return value
        const originalReturnValue = proceed.apply(this, rest)

        // https://api.highcharts.com/highcharts/accessibility.series.pointDescriptionEnabledThreshold
        const pointDescriptionEnabledThreshold =
          this.series.chart.userOptions.accessibility?.series?.pointDescriptionEnabledThreshold ||
          defaultPointDescriptionEnabledThreshold
        if (
          pointDescriptionEnabledThreshold &&
          typeof pointDescriptionEnabledThreshold == 'number' &&
          this.series.data.length > pointDescriptionEnabledThreshold
        ) {
          const announcement = chartsModule.SeriesAccessibilityDescriber.defaultPointDescriptionFormatter(this)
          announce(announcement, {assertive: true})
        }

        return originalReturnValue
      },
    )
  }
}

/**
 * Ensures that the data shown in the table and CSV reflect the selected range in the Chart.
 * See: https://github.com/github/accessibility/issues/7760#issuecomment-2551561294.
 */
function overrideGetDataRows() {
  for (const chartsModule of [Highstock, Highcharts]) {
    chartsModule.wrap(
      chartsModule.Chart.prototype,
      'getDataRows',
      function (this: Highstock.Chart | Highcharts.Chart, proceed: WrapProceedFunction, multiLevelHeaders) {
        let rows = proceed.call(this, multiLevelHeaders)
        const xMin = this.xAxis[0]?.min
        const xMax = this.xAxis[0]?.max

        if (xMin && xMax) {
          // eslint-disable-next-line @typescript-eslint/no-explicit-any
          rows = rows.filter(function (row: Record<string, any>) {
            return typeof row.x !== 'number' || (row.x >= xMin && row.x <= xMax)
          })
        }
        return rows
      },
    )
  }
}
