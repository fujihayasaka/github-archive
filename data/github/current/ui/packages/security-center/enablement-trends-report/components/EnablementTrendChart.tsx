import type {SeriesOptionsType} from 'highcharts'
import {useMemo} from 'react'

import ChartCard from '../../common/components/chart-card'
import {HpcTag} from '../../common/components/HpcTag'
import {TrendIndicator} from '../../common/components/trend-indicator'
import {humanReadableDate} from '../../common/utils/date-formatter'
import {
  asDataState,
  type DataState,
  isErrorState,
  isLoadingState,
  isNoDataState,
} from '../hooks/use-enablement-trend-data'
import type {Dataset} from '../types/dataset'

export interface EnablementTrendChartProps {
  state: 'loading' | 'error' | 'no-data' | 'ready'
  description: string
  datasets: Dataset[]
  trendValue: number
}

export function EnablementTrendChart({
  state,
  description,
  datasets,
  trendValue,
}: EnablementTrendChartProps): JSX.Element {
  const dataState: DataState<Dataset[]> = asDataState(state, datasets)

  const title = useMemo(() => {
    const lastValues = datasets.map(dataset => dataset.data[dataset.data.length - 1]?.y || 0)
    const maxValueOnLastDate = Math.max(...lastValues)
    return `${maxValueOnLastDate}% enabled`
  }, [datasets])

  const formattedEndDate = useMemo(() => {
    const data = datasets[0]?.data
    const lastDate = data?.at(-1)?.x
    if (!lastDate) return ''

    return humanReadableDate(new Date(lastDate), {includeYear: true})
  }, [datasets])

  const chartBlankslate = useMemo(() => {
    if (isLoadingState(dataState)) {
      return {
        isLoading: true,
      }
    }

    if (isErrorState(dataState)) {
      return {
        isLoading: false,
        message: 'Adoption data could not be loaded right now.',
        isError: true,
        ariaLabel: 'Empty chart. Adoption trends could not be loaded right now.',
      }
    }

    if (isNoDataState(dataState)) {
      return {
        isLoading: false,
        message: 'Try modifying your filters to see the security impact on your organization.',
        isError: false,
        ariaLabel: 'Empty chart. There are no enabled features in this period.',
      }
    }

    return undefined
  }, [dataState])

  const lineStyles = useMemo(() => {
    return [
      {
        color: 'var(--data-blue-color-emphasis, var(--data-blue-color))',
        dashStyle: 'ShortDot',
      },
      {
        color: 'var(--data-green-color-emphasis, var(--data-green-color))',
        dashStyle: 'Solid',
      },
    ]
  }, [])

  const chartSeries = useMemo(() => {
    if (isErrorState(dataState)) return [] as SeriesOptionsType[]

    return datasets.map((dataset, index) => {
      return {
        name: dataset.label,
        data: dataset.data.map(i => [Date.parse(i.x), i.y]),
        type: 'line',
        color: lineStyles[index]?.color,
        dashStyle: lineStyles[index]?.dashStyle,
      } as SeriesOptionsType
    })
  }, [dataState, datasets, lineStyles])

  return (
    <>
      <ChartCard
        blankslate={chartBlankslate}
        height={433}
        size="large"
        title="Enablement trends"
        type="line"
        series={chartSeries}
        xAxisTitle="Date"
        yAxisTitle="Repositories enabled (%)"
        isPercentage
        hideTitle
      >
        <ChartCard.Description>
          <div className="d-flex flex-items-baseline">
            <h3 className="f2 text-normal fgColor-default mr-3">{title}</h3>
            <TrendIndicator value={trendValue} flipColor loading={false} error={false} />
            <p className="fgColor-muted f6 ml-3">{`as of ${formattedEndDate}`}</p>
          </div>
          {description}
        </ChartCard.Description>
      </ChartCard>
      <HpcTag loading={isLoadingState(dataState)} />
    </>
  )
}
