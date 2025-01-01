import type {SeriesOptionsType} from 'highcharts'
import {useMemo} from 'react'

import ChartCard from '../../../common/components/chart-card'
import {HpcTag} from '../../../common/components/HpcTag'
import type CardProps from '../../types/card-props'
import {getTotalAlertCountData, usePreventedAndIntroducedChartData} from './use-prevented-and-introduced-chart-data'

export function PreventedAndIntroducedChart({startDate, endDate, query = ''}: CardProps): JSX.Element {
  const dataQuery = usePreventedAndIntroducedChartData({query, startDate, endDate})
  const totalAlertCount = getTotalAlertCountData(dataQuery)
  const isNoData = dataQuery.isSuccess && totalAlertCount === 0

  const chartBlankslate = useMemo(() => {
    if (dataQuery.isPending) {
      return {
        isLoading: true,
      }
    }

    if (dataQuery.isError) {
      return {
        isLoading: false,
        message: 'Alert trends could not be loaded right now.',
        isError: true,
        ariaLabel: 'Empty chart. Prevented and introduced trends could not be loaded right now.',
      }
    }

    if (isNoData) {
      return {
        isLoading: false,
        message: 'Try modifying your filters to see the security impact on your organization.',
        isError: false,
        ariaLabel: 'Empty chart. There are no prevented or introduced alerts in this period.',
      }
    }

    return undefined
  }, [dataQuery, isNoData])

  const chartSeries = useMemo(() => {
    const series = [] as SeriesOptionsType[]
    if (!dataQuery.isSuccess) return series

    const trends = new Map<string, Array<{x: string; y: number}>>()
    for (const seriesData of dataQuery.data) {
      trends.set(seriesData.label, seriesData.data)
    }

    series.push({
      name: 'Prevented',
      data: trends.get('Prevented')?.map(i => [Date.parse(i.x), i.y]) || [],
      type: 'area',
      color: 'var(--data-blue-color-emphasis, var(--data-blue-color))',
      dashStyle: 'ShortDot',
    })

    series.push({
      name: 'Introduced',
      data: trends.get('Introduced')?.map(i => [Date.parse(i.x), i.y]) || [],
      type: 'area',
      color: 'var(--data-pink-color-emphasis, var(--data-pink-color))',
      dashStyle: 'Solid',
    })

    return series
  }, [dataQuery])

  return (
    <>
      <ChartCard
        blankslate={chartBlankslate}
        height={415}
        size="large"
        title="Prevented vs. Introduced"
        type="area"
        series={chartSeries}
        xAxisTitle="Date"
        yAxisTitle="Number of closed alerts"
        yAxisMin={0}
      >
        <ChartCard.Description>
          {'CodeQL vulnerabilities caught in the developer workflow before being introduced to the default branch'}
        </ChartCard.Description>
      </ChartCard>
      <HpcTag loading={dataQuery.isPending} />
    </>
  )
}
