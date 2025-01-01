import {ChartCard} from '@github-ui/chart-card'
import {memo} from 'react'

import type {MemexChartConfiguration} from '../../../api/charts/contracts/api'
import {highChartTypes, isStacked, shouldApplyPointPlacement} from '../../../api/charts/contracts/api'
import {useEnabledFeatures} from '../../../hooks/use-enabled-features'
import type {MemexItemModel} from '../../../models/memex-item-model'
import {useHistoricalChartSeries} from '../../../state-providers/charts/use-historical-chart-series'
import {useLeanHistoricalChartSeriesChartCard} from '../../../state-providers/charts/use-lean-historical-chart-series'
import {getLegendLabel} from '../highcharts-theme'
import {LoadingCard} from './loading-messages/loading-card'
import {NoDataCard} from './loading-messages/no-data-card'

export const LeanHistoricalInsightsChart = memo<{
  configuration: MemexChartConfiguration
  endDate?: string
  filteredItems: Array<MemexItemModel> | null
  filterValue: string
  startDate?: string
}>(function LeanHistoricalInsightsChart({configuration, endDate, filteredItems, startDate}) {
  const {memex_table_without_limits} = useEnabledFeatures()
  const {series, xCoordinates, isLoading} = memex_table_without_limits
    ? // eslint-disable-next-line react-compiler/react-compiler
      // eslint-disable-next-line react-hooks/rules-of-hooks
      useHistoricalChartSeries({configuration, startDate, endDate})
    : // eslint-disable-next-line react-compiler/react-compiler
      // eslint-disable-next-line react-hooks/rules-of-hooks
      useLeanHistoricalChartSeriesChartCard({
        configuration,
        filteredItems,
        startDate,
        endDate,
      })

  if (isLoading) {
    return <LoadingCard />
  }

  if (!xCoordinates.length) {
    return <NoDataCard />
  }

  const chartType = configuration.type
  return (
    // eslint-disable-next-line @github-ui/dotcom-primer/require-children
    <ChartCard padding="spacious" size="xl">
      <ChartCard.Chart
        series={series as Array<Highcharts.SeriesOptionsType>}
        xAxisTitle="Date"
        xAxisOptions={{
          title: {
            text: null,
          },
          categories: xCoordinates,
          tickAmount: 28,
        }}
        yAxisTitle="items"
        yAxisOptions={{
          title: {
            text: null,
          },
          maxPadding: 0,
          allowDecimals: false,
        }}
        plotOptions={{
          series: {
            stacking: isStacked(chartType) ? 'normal' : undefined,
            marker: {
              enabled: false,
            },
            pointPlacement: shouldApplyPointPlacement(configuration.type) ? 'on' : undefined,
          },
        }}
        overrideOptionsNotRecommended={{
          legend: {
            reversed: true,
            align: 'right',
            layout: 'horizontal',
            verticalAlign: 'bottom',
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
        type={highChartTypes[chartType]}
      />
    </ChartCard>
  )
})
