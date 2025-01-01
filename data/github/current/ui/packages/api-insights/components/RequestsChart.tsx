import {ChartCard} from '@github-ui/chart-card'
import {useReplaceSearchParams} from '../hooks/UseReplaceSearchParams'
import {GraphIcon} from '@primer/octicons-react'
import styles from './RequestsChart.module.css'
import {clsx} from 'clsx'
import type {Point} from 'highcharts'

export interface RequestsChartProps {
  request_count: Array<[number, number]>
  rate_limited_request_count: Array<[number, number]>
  min?: number
  max?: number
  no_data?: boolean
}

function seriesOrSinglePoint(data: Array<[number, number]>) {
  if (data.length === 1) {
    const point = data[0]
    const x: number = point ? point[0] : 0
    const y: number = point ? point[1] : 0
    return [
      {
        x,
        y,
        marker: {
          enabled: true,
        },
      },
    ]
  }
  return data
}

function ghostMarkerFix(this: Point) {
  // After re-rendering the chart and hovering, some markers are not set back to opacity 0,
  // leaving ghost points. Remove this mouseOut event if an upstream fix is made
  if (this?.graphic?.attr('opacity') === 1) {
    setTimeout(() => {
      this?.graphic?.attr({opacity: 0})
    }, 5)
  }
}

export function RequestsChart({
  no_data = false,
  min,
  max,
  request_count,
  rate_limited_request_count,
}: RequestsChartProps) {
  const {searchParams} = useReplaceSearchParams()
  const singlePoint = request_count.length === 1
  return (
    <div className={clsx(styles.requestsChart, 'position-relative width-full')}>
      {no_data && (
        <div className="border rounded-2 d-flex flex-items-center flex-justify-center height-full flex-column">
          <GraphIcon className="fgColor-muted" size={24} />
          <h2 className="f3">No data available</h2>
          <p className="f4 fgColor-muted">No results were returned.</p>
        </div>
      )}
      {!no_data && (
        <ChartCard
          size="large"
          border
          padding="normal"
          visibleControls={false}
          className="position-absolute width-full"
        >
          <ChartCard.Title as="h2">Number of REST requests</ChartCard.Title>
          <ChartCard.Chart
            useUTC={searchParams.get('t') !== 'local'}
            xAxisTitle="Time"
            yAxisTitle="Requests"
            colors={['var(--fgColor-accent)', 'var(--fgColor-danger)']}
            series={[
              {
                name: 'Total requests',
                data: seriesOrSinglePoint(request_count),
                type: 'line',
              },
              {
                name: 'Primary-rate-limited requests',
                data: seriesOrSinglePoint(rate_limited_request_count),
                type: 'line',
              },
            ]}
            xAxisOptions={{
              type: 'datetime',
              dateTimeLabelFormats: {
                minute: '%H:%M',
              },
              gridLineDashStyle: 'Dash',
              min,
              max,
            }}
            yAxisOptions={{
              gridLineDashStyle: 'Solid',
            }}
            plotOptions={{
              series: {
                marker: {
                  enabled: false,
                },
                point: {
                  events: {
                    mouseOut: singlePoint ? undefined : ghostMarkerFix,
                  },
                },
              },
            }}
            type={'line'}
          />
        </ChartCard>
      )}
    </div>
  )
}

export default RequestsChart
