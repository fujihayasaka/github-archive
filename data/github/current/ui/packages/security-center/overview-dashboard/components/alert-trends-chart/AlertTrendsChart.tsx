import DataCard from '@github-ui/data-card'
import {ActionList, ActionMenu, Box, Text} from '@primer/react'
import type {SeriesOptionsType} from 'highcharts'
import {useEffect, useMemo, useState} from 'react'

import ChartCard from '../../../common/components/chart-card'
import {HpcTag} from '../../../common/components/HpcTag'
import {TrendIndicator} from '../../../common/components/trend-indicator'
import {useClickLogging} from '../../../common/hooks/use-click-logging'
import {humanReadableDate} from '../../../common/utils/date-formatter'
import {calculateTrend} from '../../../common/utils/trend-data'
import type CardProps from '../../types/card-props'
import {generateAriaLabelForAlertTrends} from './aria'
import {calculatePreviousTwoDays} from './calculate-previous-two-days'
import type {GroupingType} from './grouping-type'
import {groupingValues} from './grouping-type'
import {getAlertTrendsData, getTotalAlertCountData, useAlertTrendsQuery} from './use-alert-trends-query'

const defaultGrouping = 'severity'

type AlertTrendsChartProps = {
  grouping?: GroupingType
  isOpenSelected: boolean
} & CardProps

export function AlertTrendsChart({
  startDate,
  endDate,
  grouping: initialGrouping,
  isOpenSelected,
  query = '',
}: AlertTrendsChartProps): JSX.Element {
  const [trend, setTrend] = useState(0)
  const [grouping, setSelectedGrouping] = useState<GroupingType>(initialGrouping ?? defaultGrouping)

  const {logClick} = useClickLogging({category: 'AlertTrendsChart'})

  const alertState = isOpenSelected ? 'open' : 'closed'
  const previousDateRange = calculatePreviousTwoDays(startDate)
  const currentPeriodState = useAlertTrendsQuery({query, startDate, endDate, grouping, alertState})
  const previousPeriodState = useAlertTrendsQuery({
    query,
    startDate: previousDateRange.startDate,
    endDate: previousDateRange.endDate,
    grouping,
    alertState,
  })

  const alertTrends = getAlertTrendsData(currentPeriodState)
  const totalAlertCount = getTotalAlertCountData(currentPeriodState)
  const totalPreviousAlertCount = getTotalAlertCountData(previousPeriodState)
  // current data states
  const isCurrentStateSuccess = currentPeriodState.every(result => result.isSuccess)
  const isCurrentStatePending = currentPeriodState.some(result => result.isPending)
  const isCurrentStateError = currentPeriodState.some(result => result.isError)
  const isNoData = isCurrentStateSuccess && totalAlertCount === 0
  // previous data states
  const isPreviousStatePending = previousPeriodState.some(result => result.isPending)
  const isPreviousStateError = previousPeriodState.some(result => result.isError)

  useEffect(() => {
    if (totalAlertCount != null && totalPreviousAlertCount != null) {
      setTrend(calculateTrend(totalAlertCount, totalPreviousAlertCount))
    }
  }, [totalAlertCount, totalPreviousAlertCount])

  // Change the URL.
  useEffect(() => {
    const url = new URL(window.location.href, window.location.origin)
    const nextParams = url.searchParams

    if (grouping === defaultGrouping) {
      nextParams.delete('alertTrendsChart[grouping]')
    } else {
      nextParams.set('alertTrendsChart[grouping]', grouping)
    }

    history.pushState(null, '', `${url.pathname}${url.search}`)
  }, [grouping])

  const chartBlankslate = useMemo(() => {
    if (isCurrentStatePending) {
      return {
        isLoading: true,
      }
    }

    if (!groupingValues.includes(grouping)) {
      return {
        isLoading: false,
        message: 'Invalid grouping. Please select a valid grouping from the dropdown.',
        isError: true,
        ariaLabel: generateAriaLabelForAlertTrends(null, grouping, startDate, endDate, isOpenSelected, true),
      }
    }

    if (isCurrentStateError) {
      return {
        isLoading: false,
        message: 'Alert trends could not be loaded right now.',
        isError: true,
        ariaLabel: generateAriaLabelForAlertTrends(null, grouping, startDate, endDate, isOpenSelected, true),
      }
    }

    if (isNoData) {
      return {
        isLoading: false,
        message: 'Try modifying your filters to see the security impact on your organization.',
        isError: false,
        ariaLabel: generateAriaLabelForAlertTrends(null, grouping, startDate, endDate, isOpenSelected),
      }
    }

    return undefined
  }, [isCurrentStatePending, grouping, isCurrentStateError, isNoData, startDate, endDate, isOpenSelected])

  const chartSeries = useMemo(() => {
    const series = [] as SeriesOptionsType[]
    if (!isCurrentStateSuccess) return series
    if (alertTrends.size <= 0) return series

    if (grouping === 'severity') {
      series.push({
        name: 'Critical',
        data: alertTrends.get('Critical')?.map(i => [Date.parse(i.x), i.y]) || [],
        type: 'area',
        color: 'var(--data-pink-color-emphasis, var(--data-pink-color))',
        dashStyle: 'ShortDot',
      })

      series.push({
        name: 'High',
        data: alertTrends.get('High')?.map(i => [Date.parse(i.x), i.y]) || [],
        type: 'area',
        color: 'var(--data-orange-color-emphasis, var(--data-orange-color))',
        dashStyle: 'Dash',
      })

      series.push({
        name: 'Medium',
        data: alertTrends.get('Medium')?.map(i => [Date.parse(i.x), i.y]) || [],
        type: 'area',
        color: 'var(--data-yellow-color-emphasis, var(--data-yellow-color))',
        dashStyle: 'Solid',
      })

      series.push({
        name: 'Low',
        data: alertTrends.get('Low')?.map(i => [Date.parse(i.x), i.y]) || [],
        type: 'area',
        color: 'var(--data-gray-color-emphasis, var(--data-gray-color))',
        dashStyle: 'ShortDashDot',
      })
    }

    if (grouping === 'age') {
      series.push({
        name: '< 30 days',
        data: alertTrends.get('< 30 days')?.map(i => [Date.parse(i.x), i.y]) || [],
        type: 'area',
        color: 'var(--data-blue-color-emphasis, var(--data-blue-color))',
        dashStyle: 'ShortDot',
      })

      series.push({
        name: '31 - 59 days',
        data: alertTrends.get('31 - 59 days')?.map(i => [Date.parse(i.x), i.y]) || [],
        type: 'area',
        color: 'var(--data-green-color-emphasis, var(--data-green-color))',
        dashStyle: 'Dash',
      })

      series.push({
        name: '60 - 89 days',
        data: alertTrends.get('60 - 89 days')?.map(i => [Date.parse(i.x), i.y]) || [],
        type: 'area',
        color: 'var(--data-orange-color-emphasis, var(--data-orange-color))',
        dashStyle: 'Solid',
      })

      series.push({
        name: '90+ days',
        data: alertTrends.get('90+ days')?.map(i => [Date.parse(i.x), i.y]) || [],
        type: 'area',
        color: 'var(--data-pink-color-emphasis, var(--data-pink-color))',
        dashStyle: 'ShortDashDot',
      })
    }

    if (grouping === 'tool') {
      // The first 3 tools in the chart (in the order in which they should appear).
      const firstPartyToolsOrder = ['Dependabot', `CodeQL`, 'Secret scanning']
      let lineStyleIndex = 0
      const lineStyleOrder = [
        {
          color: 'var(--data-green-color-emphasis, var(--data-green-color))',
          dashStyle: 'Solid',
        },
        {
          color: 'var(--data-blue-color-emphasis, var(--data-blue-color))',
          dashStyle: 'ShortDashDot',
        },
        {
          color: 'var(--data-orange-color-emphasis, var(--data-orange-color))',
          dashStyle: 'Dash',
        },
        {
          color: 'var(--data-pink-color-emphasis, var(--data-pink-color))',
          dashStyle: 'ShortDot',
        },
        {
          color: 'var(--data-gray-color-emphasis, var(--data-gray-color))',
          dashStyle: 'ShortDashDot',
        },
        {
          color: 'var(--data-yellow-color-emphasis, var(--data-yellow-color))',
          dashStyle: 'Solid',
        },
        {
          color: 'var(--data-red-color-emphasis, var(--data-red-color))',
          dashStyle: 'Dash',
        },
      ]

      // Series for the first-party tools.
      for (const tool of firstPartyToolsOrder) {
        if (lineStyleIndex >= lineStyleOrder.length - 1) break
        if (!alertTrends.has(tool)) continue

        const lineStyle = lineStyleOrder[lineStyleIndex++]
        if (lineStyle === undefined) continue

        series.push({
          name: tool,
          data: alertTrends.get(tool)?.map(i => [Date.parse(i.x), i.y]) || [],
          type: 'area',
          color: lineStyle.color,
          dashStyle: lineStyle.dashStyle,
        })
      }

      // Series for named third-party tools.
      if (alertTrends.size > 0) {
        for (const [tool, dataPoints] of alertTrends) {
          if (lineStyleIndex >= lineStyleOrder.length - 1) break
          if (['CodeQL', 'Dependabot', 'Secret scanning', 'Other third-party tools'].includes(tool)) continue

          const lineStyle = lineStyleOrder[lineStyleIndex++]
          if (lineStyle === undefined) continue

          series.push({
            name: tool,
            data: dataPoints.map(i => [Date.parse(i.x), i.y]) || [],
            type: 'area',
            color: lineStyle.color,
            dashStyle: lineStyle.dashStyle,
          })
        }
      }

      // Series for other third-party tools.
      const lineStyle = lineStyleOrder[lineStyleIndex]
      const tool = 'Other third-party tools'
      const dataPoints = alertTrends.get(tool)
      if (dataPoints !== undefined && lineStyle !== undefined) {
        series.push({
          name: tool,
          data: dataPoints.map(i => [Date.parse(i.x), i.y]) || [],
          type: 'area',
          color: lineStyle.color,
          dashStyle: lineStyle.dashStyle,
        })
      }
    }

    return series
  }, [alertTrends, grouping, isCurrentStateSuccess])

  function renderActionsMenu(): JSX.Element {
    const getGroupLabel = (groupingValue: string): string | undefined => {
      switch (groupingValue) {
        case 'age':
          return 'Age'
        case 'severity':
          return 'Severity'
        case 'tool':
          return 'Tool'
      }
    }

    const groupOptions = groupingValues.map(groupingValue => {
      return (
        <ActionList.Item
          key={groupingValue}
          onSelect={() => {
            logClick({action: 'select alert trends grouping', label: groupingValue})
            setSelectedGrouping(groupingValue)
          }}
          selected={grouping === groupingValue}
        >
          {getGroupLabel(groupingValue)}
        </ActionList.Item>
      )
    })

    return (
      <Box sx={{display: 'flex', justifyContent: 'end'}}>
        <ActionMenu>
          <ActionMenu.Button variant="invisible" data-testid="grouping-selector">
            <Text sx={{color: 'fg.subtle'}}>Group by: </Text>
            {getGroupLabel(grouping)}
          </ActionMenu.Button>
          <ActionMenu.Overlay>
            <ActionList selectionVariant="single">{groupOptions}</ActionList>
          </ActionMenu.Overlay>
        </ActionMenu>
      </Box>
    )
  }

  const formattedEndDate = humanReadableDate(new Date(endDate), {includeYear: true})

  return (
    <>
      <ChartCard
        blankslate={chartBlankslate}
        height={430}
        size="large"
        title={`${isOpenSelected ? 'Open' : 'Closed'} alerts over time`}
        type="area"
        series={chartSeries}
        xAxisTitle="Date"
        yAxisTitle={`Number of ${isOpenSelected ? 'open' : 'closed'} alerts`}
        yAxisMin={0}
      >
        <ChartCard.Description>
          <Box className="d-flex flex-justify-left flex-items-baseline fgColor-default" sx={{gap: '1em'}}>
            {totalAlertCount != null && <DataCard.Counter count={totalAlertCount} />}
            <TrendIndicator
              loading={isCurrentStatePending || isPreviousStatePending}
              error={isCurrentStateError || isPreviousStateError}
              value={trend}
              flipColor={!isOpenSelected}
            />
            <span className="fgColor-muted f6">{`as of ${formattedEndDate}`}</span>
          </Box>
        </ChartCard.Description>
        <ChartCard.Actions>{renderActionsMenu()}</ChartCard.Actions>
      </ChartCard>
      <HpcTag loading={isCurrentStatePending} />
    </>
  )
}
