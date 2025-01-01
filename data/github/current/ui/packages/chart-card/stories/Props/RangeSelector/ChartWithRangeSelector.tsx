// Disabling a lint rule that wants this Storybook story’s dependency to be in `dependencies` instead of `devDependencies`, which is wrong.
// eslint-disable-next-line import/no-extraneous-dependencies
import {GitHubAvatar} from '@github-ui/github-avatar'
import {Label} from '@primer/react'
import {useContext, useEffect, useMemo, useRef} from 'react'
import {ChartCard, type ChartCardProps} from '../../../ChartCard'
import {DateContext} from './DateContext'
import {debounce} from './debounce'

// `import type {HighchartsReactRefObject} from 'highcharts-react-official'` would work too;
// this shows that imports outside `ChartCard` aren’t required.
type HighchartsReactRefObject = NonNullable<ChartCardProps['chartRef']> extends React.RefObject<infer T> ? T : never

type AxisSetExteremesEventObject = Parameters<
  NonNullable<
    NonNullable<NonNullable<React.ComponentProps<typeof ChartCard.Chart>['xAxisOptions']>['events']>['setExtremes']
  >
>[0]

export function ChartWithRangeSelector(args: ChartCardProps) {
  /** An array of 10,000 tuples. Each tuple contains a date and a random number of commits on that date. */
  const thousandsOfDataPoints = useMemo(() => {
    const dataPoints: Array<[number, number]> = []
    for (
      let date = Date.now(), value = Math.floor(Math.random() * 40);
      dataPoints.length <= 10000;
      date = date - 86400000, value = Math.max(0, value + Math.floor(Math.random() * 10) - 5)
    ) {
      dataPoints.push([date, value])
    }
    return dataPoints.sort(([a], [b]) => a - b)
  }, [])

  // Get context
  const {from, to, setDate} = useContext(DateContext)

  // Prepare props that will be passed to ChartCard or ChartCard.Chart
  const chartRef = useRef<HighchartsReactRefObject>(null)
  const series = useMemo(
    () => [
      {
        type: 'areaspline',
        name: 'Commits',
        data: thousandsOfDataPoints,
      },
    ],
    [thousandsOfDataPoints],
  )
  const xAxisOptions = useMemo(
    () => ({
      min: from,
      max: to,
      type: 'datetime' as const,
      events: {
        afterSetExtremes: debounce((event: AxisSetExteremesEventObject) => {
          // Only respond to user interaction, not programmatic changes (to prevent infinite loops)
          if (event.trigger === 'navigator') {
            setDate({from: event.min, to: event.max})
          }
        }, 100),
      },
    }),
    // FIXME: Find a way to add `from` and `to` here without causing [focus loss](https://github.com/github/github/pull/341018#issuecomment-2407609939).
    // eslint-disable-next-line react-compiler/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [setDate],
  )
  const plotOptions = useMemo(
    () => ({
      series: {
        marker: {
          enabled: false,
        },
      },
    }),
    [],
  )

  const totalCommits = useMemo(
    () => thousandsOfDataPoints.reduce((total, [, value]) => total + value, 0).toLocaleString(),
    [thousandsOfDataPoints],
  )

  // When dates change, update the chart’s navigator (the range selector)
  useEffect(() => {
    const {dataMin, dataMax} = chartRef.current?.chart.xAxis[0]?.getExtremes() ?? {}
    chartRef.current?.chart.xAxis[0]?.setExtremes(from ?? dataMin, to ?? dataMax, true)
  }, [chartRef, from, to])
  // Note that this effect must be on a _child_ of the component that renders `<DateProvider>`.

  return (
    <ChartCard {...args} chartRef={chartRef}>
      <ChartCard.LeadingVisual>
        <GitHubAvatar src="https://avatars.githubusercontent.com/u/90379286?s=60&amp;v=4" size={40} />
      </ChartCard.LeadingVisual>
      <ChartCard.Title as="h4" sx={{fontSize: 1}}>
        accessibility-bot
      </ChartCard.Title>
      <ChartCard.Description sx={{fontSize: 1}}>{totalCommits} commits</ChartCard.Description>
      <ChartCard.TrailingVisual>
        <Label>#1</Label>
      </ChartCard.TrailingVisual>
      <ChartCard.Chart
        series={series}
        xAxisTitle="Time"
        xAxisOptions={xAxisOptions}
        yAxisTitle="Commits"
        plotOptions={plotOptions}
        type="areaspline"
        showRangeSelector
      />
    </ChartCard>
  )
}
