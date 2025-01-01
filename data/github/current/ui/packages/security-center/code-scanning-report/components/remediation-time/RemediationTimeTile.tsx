import type {SeriesOptionsType} from 'highcharts'
import {useMemo} from 'react'

import ChartCard from '../../../common/components/chart-card'
import useRemediationTimeQuery, {type UseRemediationTimeQueryParams} from './use-remediation-time-query'

interface RemediationTimeTileProps extends UseRemediationTimeQueryParams {}

export default function RemediationTimeTile(props: RemediationTimeTileProps): JSX.Element {
  const dataQuery = useRemediationTimeQuery(props)

  const chartBlankslate = useMemo(() => {
    if (dataQuery.isPending) {
      return {
        isLoading: true,
      }
    }

    if (dataQuery.isError) {
      return {
        isLoading: false,
        message: 'Data could not be loaded right now.',
        isError: true,
      }
    }

    return undefined
  }, [dataQuery])

  const [chartCategories, chartSeries] = useMemo(() => {
    const categories = ['With autofix', 'Without autofix']
    if (!dataQuery.isSuccess) return [categories, [] as SeriesOptionsType[]]

    return [
      categories,
      [
        {
          name: 'With autofix',
          data: [dataQuery.data.remediationTimeInHoursWithAutofixSuggested, null],
          color: 'var(--data-blue-color-emphasis, var(--data-blue-color))',
        } as SeriesOptionsType,
        {
          name: 'Without autofix',
          data: [null, dataQuery.data.remediationTimeInHoursWithNoAutofixSuggested],
          color: 'var(--data-purple-color-emphasis, var(--data-purple-color))',
        } as SeriesOptionsType,
      ],
    ]
  }, [dataQuery])

  return (
    <ChartCard
      blankslate={chartBlankslate}
      height={244}
      width={270}
      size="small"
      title="Mean time to remediate"
      type="bar"
      series={chartSeries}
      xAxisTitle="Autofix suggestion status"
      yAxisTitle="Alert remediation time (hours)"
      displayYAxisTitle
      categories={chartCategories}
      showDataLabels
      hideLegend
      hideTooltip
    >
      <ChartCard.Description>
        Average age of closed alerts (excludes alerts closed as false positives)
      </ChartCard.Description>
    </ChartCard>
  )
}
