import type {SeriesOptionsType} from 'highcharts'
import {useMemo} from 'react'

import ChartCard from '../../../common/components/chart-card'
import {humanReadableDate} from '../../../common/utils/date-formatter'
import type CardProps from '../../types/card-props'
import {generateAriaLabelForAlertActivity} from './aria'
import {getAlertActivityData, useAlertActivityQuery} from './use-alert-activity-query'

export function AlertActivityChart({startDate, endDate, query = ''}: CardProps): JSX.Element {
  const alertActivityState = useAlertActivityQuery({query, startDate, endDate})
  const {data: alertActivityData, sum: alertActivitySum} = getAlertActivityData(alertActivityState)
  const isSuccess = alertActivityState.every(result => result.isSuccess)
  const isLoading = alertActivityState.some(result => result.isPending)
  const isError = alertActivityState.some(result => result.isError)
  const isNoData = isSuccess && alertActivitySum === 0

  const dateRanges = useMemo(() => {
    return alertActivityData.map(d => {
      return {
        startDate: d.date,
        endDate: d.endDate,
      }
    })
  }, [alertActivityData])

  const chartBlankslate = useMemo(() => {
    if (isLoading) {
      return {
        isLoading: true,
      }
    }

    if (isError) {
      return {
        isLoading: false,
        message: 'Alert activity could not be loaded right now.',
        isError,
        ariaLabel: generateAriaLabelForAlertActivity(alertActivityData, true),
      }
    }

    if (isNoData) {
      return {
        isLoading: false,
        message: 'Try modifying your filters to see the security impact on your organization.',
        isError: false,
        ariaLabel: generateAriaLabelForAlertActivity(alertActivityData),
      }
    }

    return undefined
  }, [isLoading, isError, isNoData, alertActivityData])

  const [chartCategories, chartSeries] = useMemo(() => {
    const categories = dateRanges.map(range => {
      const dateOptions = {includeYear: false}

      const formattedDate = humanReadableDate(new Date(range.startDate), dateOptions)
      if (range.startDate === range.endDate) {
        return formattedDate
      }

      const formattedEndDate = humanReadableDate(new Date(range.endDate), dateOptions)
      return `${formattedDate} - ${formattedEndDate}`
    })

    const series = [
      {
        name: 'New',
        data: alertActivityData.map(d => d.opened),
        type: 'column',
        color: 'var(--bgColor-success-muted)',
        borderColor: 'var(--bgColor-success-emphasis)',
        borderWidth: 2,
        borderRadius: 0,
      } as SeriesOptionsType,
      {
        name: 'Closed',
        data: alertActivityData.map(d => -1 * d.closed),
        type: 'column',
        color: 'var(--bgColor-done-muted)',
        borderColor: 'var(--bgColor-done-emphasis)',
        borderWidth: 2,
        borderRadius: 0,
      } as SeriesOptionsType,
      {
        name: 'Net alert activity',
        data: alertActivityData.map(d => d.opened - d.closed),
        type: 'line',
        color: 'var(--bgColor-accent-emphasis)',
        dashStyle: 'Dash',
      } as SeriesOptionsType,
    ]

    return [categories, series]
  }, [alertActivityData, dateRanges])

  return (
    <ChartCard
      blankslate={chartBlankslate}
      height={330}
      size="medium"
      title="Alert activity"
      type="column"
      series={chartSeries}
      xAxisTitle="Date period"
      yAxisTitle="Number of alerts"
      categories={chartCategories}
    />
  )
}
