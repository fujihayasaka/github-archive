import {useMemo} from 'react'
import {ChartCard} from '@github-ui/chart-card'
import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'
import {type MetricDataPoint, METRIC_KEY} from '../types'

export type CodeFrequencyChartProps = {
  additions: MetricDataPoint[]
  deletions: MetricDataPoint[]
}

export default function CodeFrequencyChart({additions, deletions}: CodeFrequencyChartProps) {
  const columnCharts = useFeatureFlag('repos_column_charts')
  const isAcrossMultipleYears = useMemo(() => {
    const first = additions[0]
    const last = additions.at(-1)
    if (!first || !last) {
      return false
    }
    const firstDate = new Date(first[METRIC_KEY.TIMESTAMP])
    const lastDate = new Date(last[METRIC_KEY.TIMESTAMP])

    return firstDate?.getFullYear() !== lastDate?.getFullYear()
  }, [additions])

  const type = columnCharts ? 'column' : 'areaspline'

  return (
    <ChartCard size="xl">
      <ChartCard.Title>Code frequency</ChartCard.Title>
      <ChartCard.Description>Additions and deletions per week</ChartCard.Description>
      <ChartCard.Chart
        type={type}
        dataGrouping={columnCharts}
        series={[
          {
            type,
            name: 'Additions',
            data: additions,
          },
          {
            type,
            name: 'Deletions',
            data: deletions,
            dashStyle: type === 'areaspline' ? 'Dash' : undefined,
          },
        ]}
        xAxisTitle=""
        yAxisTitle="Frequency"
        colors={[
          'var(--data-green-color-emphasis, var(--data-green-color))',
          'var(--data-red-color-emphasis, var(--data-red-color))',
        ]}
        xAxisOptions={{
          type: 'datetime',
          labels: {
            format: columnCharts ? undefined : `{value:%b %e${isAcrossMultipleYears ? ', %Y' : ''}}`,
          },
        }}
        yAxisOptions={{
          labels: {
            align: 'left',
            x: 5,
          },
        }}
        plotOptions={{
          series: {
            marker: {
              enabled: false,
            },
          },
          column: columnCharts
            ? {
                pointPadding: 0,
                borderWidth: 1,
                borderColor: 'var(--bgColor-default)',
                groupPadding: 0,
                borderRadius: 2,
                stacking: 'overlap',
              }
            : undefined,
        }}
        tooltipOptions={{
          ...(columnCharts
            ? {
                xDateFormat: 'Week of %e %b, %Y',
              }
            : {}),
          split: false,
        }}
        overrideOptionsNotRecommended={{
          ...(columnCharts
            ? {
                legend: {
                  enabled: true,
                  align: 'right',
                  layout: 'vertical',
                  verticalAlign: 'middle',
                },
              }
            : {}),
          rangeSelector: {
            enabled: false,
          },
          scrollbar: {
            enabled: false,
          },
          navigator: {
            enabled: false,
          },
        }}
      />
    </ChartCard>
  )
}
