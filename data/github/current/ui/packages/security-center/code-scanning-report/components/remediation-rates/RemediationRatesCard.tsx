import type {SeriesOptionsType} from 'highcharts'
import {useMemo} from 'react'

import ChartCard from '../../../common/components/chart-card'
import useRemediationRatesQuery, {type UseRemediationRatesQueryParams} from './use-remediation-rates-query'

interface RemediationRatesCardProps extends UseRemediationRatesQueryParams {}

export default function RemediationRatesCard(props: RemediationRatesCardProps): JSX.Element {
  const dataQuery = useRemediationRatesQuery(props)

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
          data: [dataQuery.data.percentFixedWithAutofixSuggested, null],
          color: 'var(--data-blue-color-emphasis, var(--data-blue-color))',
        } as SeriesOptionsType,
        {
          name: 'Without autofix',
          data: [null, dataQuery.data.percentFixedWithNoAutofixSuggested],
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
      title="Remediation rates"
      type="bar"
      series={chartSeries}
      xAxisTitle="Autofix suggestion status"
      yAxisTitle="Alert remediation rate (%)"
      categories={chartCategories}
      isPercentage
      showDataLabels
      hideLegend
      hideTooltip
    >
      <ChartCard.Description>
        {
          'Percentage of alerts with an available autofix suggestion that were remediated compared to those without an autofix suggestion.'
        }
      </ChartCard.Description>
    </ChartCard>
  )
}
