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

  const [yAxisTitleTxt, chartCategories, chartSeries] = useMemo(() => {
    let innerYAxisTitleTxt = 'Alert remediation time (hours)'
    const categories = ['With autofix', 'Without autofix']
    let dataAutofix = 0.0
    let dataNoAutofix = 0.0

    if (dataQuery.isSuccess) {
      if (
        dataQuery.data.remediationTimeInHoursWithAutofixSuggested < 24 ||
        dataQuery.data.remediationTimeInHoursWithNoAutofixSuggested < 24
      ) {
        innerYAxisTitleTxt = 'Alert remediation time (hours)'
        dataAutofix = dataQuery.data.remediationTimeInHoursWithAutofixSuggested
        dataNoAutofix = dataQuery.data.remediationTimeInHoursWithNoAutofixSuggested
      } else {
        innerYAxisTitleTxt = 'Alert remediation time (days)'
        dataAutofix = dataQuery.data.remediationTimeInHoursWithAutofixSuggested / 24
        dataNoAutofix = dataQuery.data.remediationTimeInHoursWithNoAutofixSuggested / 24
      }
    }

    if (!dataQuery.isSuccess) return [innerYAxisTitleTxt, categories, [] as SeriesOptionsType[]]

    return [
      innerYAxisTitleTxt,
      categories,
      [
        {
          name: 'With autofix',
          data: [Number(dataAutofix.toFixed(2)), null],
          color: 'var(--data-blue-color-emphasis, var(--data-blue-color))',
        } as SeriesOptionsType,
        {
          name: 'Without autofix',
          data: [null, Number(dataNoAutofix.toFixed(2))],
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
      yAxisTitle={yAxisTitleTxt}
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
