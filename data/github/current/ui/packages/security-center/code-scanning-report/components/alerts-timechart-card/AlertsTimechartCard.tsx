import {addUrlToHistoryStack} from '@github-ui/history'
import type {SeriesOptionsType} from 'highcharts'
import {useEffect, useMemo, useState} from 'react'
import {useSearchParams} from 'react-router-dom'

import ChartCard from '../../../common/components/chart-card'
import {HpcTag} from '../../../common/components/HpcTag'
import GroupMenu, {type GroupKey} from './GroupMenu'
import {useAlertTrendsQuery} from './use-alert-trends-query'

const DEFAULT_GROUP_KEY: GroupKey = 'status'

interface AlertsTimechartCardProps {
  query: string
  startDate: string
  endDate: string
  allowAutofixFeatures: boolean
}

export default function AlertsTimechartCard(props: AlertsTimechartCardProps): JSX.Element {
  const [searchParams] = useSearchParams()

  // track selected grouping
  const [groupKey, setGroupKey] = useState<GroupKey>(() => {
    return (searchParams.get('trends[groupBy]') as GroupKey | null) ?? DEFAULT_GROUP_KEY
  })

  // keep browser URL in sync with selected trend grouping
  useEffect(() => {
    const url = new URL(window.location.href, window.location.origin)
    const nextParams = url.searchParams

    if (groupKey === DEFAULT_GROUP_KEY) {
      nextParams.delete('trends[groupBy]')
    } else {
      nextParams.set('trends[groupBy]', groupKey)
    }

    addUrlToHistoryStack(`${url.pathname}${url.search}`)
  }, [groupKey])

  const dataQuery = useAlertTrendsQuery({...props, groupKey})

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
        ariaLabel: 'Empty chart. Alert trends could not be loaded right now.',
      }
    }

    const totalAlertCount = dataQuery.data.reduce((accOuter, series) => {
      const seriesSum = series.data.reduce((acc, dataPoint) => acc + dataPoint.y, 0)
      return accOuter + seriesSum
    }, 0)

    if (totalAlertCount === 0) {
      return {
        isLoading: false,
        message: 'Try modifying your filters to see the security impact on your organization.',
        isError: false,
        ariaLabel: 'Empty chart. There are no pull request alerts in this period.',
      }
    }

    return undefined
  }, [dataQuery])

  const lineStyles = useMemo(() => {
    if (groupKey === 'severity') {
      return [
        {
          color: 'var(--data-pink-color-muted)',
          borderColor: 'var(--data-pink-color-emphasis)',
        },
        {
          color: 'var(--data-orange-color-muted)',
          borderColor: 'var(--data-orange-color-emphasis)',
        },
        {
          color: 'var(--data-yellow-color-muted)',
          borderColor: 'var(--data-yellow-color-emphasis)',
        },
        {
          color: 'var(--data-gray-color-muted)',
          borderColor: 'var(--data-gray-color-emphasis)',
        },
      ]
    } else {
      return [
        {
          color: 'var(--data-yellow-color-muted)',
          borderColor: 'var(--data-yellow-color-emphasis)',
        },
        {
          color: 'var(--data-purple-color-muted)',
          borderColor: 'var(--data-purple-color-emphasis)',
        },
        {
          color: 'var(--data-blue-color-muted)',
          borderColor: 'var(--data-blue-color-emphasis)',
        },
        {
          color: 'var(--data-green-color-muted)',
          borderColor: 'var(--data-green-color-emphasis)',
        },
        {
          color: 'var(--data-orange-color-muted)',
          borderColor: 'var(--data-orange-color-emphasis)',
        },
      ]
    }
  }, [groupKey])

  const chartSeries = useMemo(() => {
    if (!dataQuery.isSuccess) {
      return [] as SeriesOptionsType[]
    }

    return dataQuery.data.reduce((acc, series, index) => {
      let name = series.label

      if (!props.allowAutofixFeatures) {
        if (series.label === 'Fixed with autofix') {
          return acc
        }
        if (series.label === 'Fixed without autofix') {
          name = 'Fixed'
        }
      }

      acc.push({
        name,
        data: series.data.map(i => [Date.parse(i.x), i.y]) || [],
        type: 'column',
        color: lineStyles[index]?.color,
        borderColor: lineStyles[index]?.borderColor,
        borderWidth: 2,
        borderRadius: 0,
      })

      return acc
    }, [] as SeriesOptionsType[])
  }, [dataQuery, props, lineStyles])

  return (
    <>
      <ChartCard
        blankslate={chartBlankslate}
        height={384}
        size="large"
        title="Alerts in pull requests"
        type="column"
        series={chartSeries}
        xAxisTitle="Date"
        yAxisTitle="Number of merged alerts"
        yAxisMin={0}
        showTooltipTotalCount
      >
        <ChartCard.Actions>
          <GroupMenu groupKey={groupKey} onGroupKeyChanged={setGroupKey} />
        </ChartCard.Actions>
      </ChartCard>
      <HpcTag loading={dataQuery.isPending} />
    </>
  )
}
