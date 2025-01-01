import {ChartCard} from '@github-ui/chart-card'
import {memo} from 'react'

import type {MemexChartConfiguration} from '../../../api/charts/contracts/api'
import {highChartTypes, isStacked, shouldApplyPointPlacement} from '../../../api/charts/contracts/api'
import {useEnabledFeatures} from '../../../hooks/use-enabled-features'
import type {MemexItemModel} from '../../../models/memex-item-model'
import {useChartSeries} from '../../../state-providers/charts/use-chart-series'
import {useChartSeriesCardCharts} from '../../../state-providers/charts/use-chart-series-card-charts'
import {colors, getLegendLabel, styleForChartType} from '../highcharts-theme'
import {LoadingCard} from './loading-messages/loading-card'
import {NoDataCard} from './loading-messages/no-data-card'

export const CurrentInsightsChart = memo<{
  configuration: MemexChartConfiguration
  filteredItems: Array<MemexItemModel> | null
  filterValue: string
}>(function CurrentInsightsChart({configuration, filteredItems}) {
  const {memex_table_without_limits} = useEnabledFeatures()

  const {series, axis, xCoordinates, isLoading} = memex_table_without_limits
    ? // eslint-disable-next-line react-hooks/react-compiler
      // eslint-disable-next-line react-hooks/rules-of-hooks
      useChartSeries(configuration)
    : // eslint-disable-next-line react-hooks/react-compiler
      // eslint-disable-next-line react-hooks/rules-of-hooks
      useChartSeriesCardCharts(configuration, filteredItems)

  const {xAxis, yAxis} = axis

  const styledSeries = series.map((s, index) => {
    const style = styleForChartType(configuration.type, index)
    return {
      ...s,
      ...style,
    }
  })

  if (isLoading) {
    return <LoadingCard />
  }

  if (!xCoordinates.length) {
    return <NoDataCard />
  }

  return (
    // eslint-disable-next-line @github-ui/dotcom-primer/require-children
    <ChartCard padding="spacious" size="xl">
      <ChartCard.Chart
        // Pass colors explicitly to stay in sync with our custom series styles.
        colors={colors('emphasis')}
        series={styledSeries as Array<Highcharts.SeriesOptionsType>}
        xAxisTitle={xAxis.name}
        xAxisOptions={{
          title: {
            text: null,
          },
          categories: xCoordinates,
        }}
        yAxisTitle={yAxis.name}
        yAxisOptions={{
          title: {
            text: null,
          },
          maxPadding: 0,
          allowDecimals: false,
        }}
        plotOptions={{
          series: {
            stacking: isStacked(configuration.type) ? 'normal' : undefined,
            marker: {
              enabled: false,
            },
            pointPlacement: shouldApplyPointPlacement(configuration.type) ? 'on' : undefined,
          },
        }}
        overrideOptionsNotRecommended={{
          legend: {
            reversed: false,
            verticalAlign: 'bottom',
            align: 'right',
            layout: 'horizontal',
            enabled: true,
            useHTML: true,
            symbolHeight: 0,
            symbolWidth: 0,
            labelFormatter() {
              return getLegendLabel(this.options as Highcharts.PointOptionsObject, this.name)
            },
          },
          tooltip: {
            valuePrefix: '&nbsp;',
          },
        }}
        type={highChartTypes[configuration.type]}
      />
    </ChartCard>
  )
})
