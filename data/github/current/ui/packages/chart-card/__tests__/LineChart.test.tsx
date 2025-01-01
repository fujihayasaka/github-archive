import {render} from '@github-ui/react-core/test-utils'
import {ChartCard} from '../ChartCard'

interface CreateChartProps {
  count?: number
  className?: string
  noTitle?: boolean
}

function createChartCard({count = 2, className, noTitle = false}: CreateChartProps = {}) {
  const series = Array.from({length: count}, (_, index) => index + 1).map((_, i) => ({
    name: `Series ${i + 1}`,
    data: new Array(10).fill(0).map(() => Math.floor(Math.random() * 100)),
  }))

  return render(
    <div>
      <h1>Some page heading</h1>
      {/* Disabling the ESLint rule that enforces ChartCard.Title, because we’re deliberately _not_ providing one in order to test Highcharts’ fallback. */}
      <ChartCard className={className}>
        {!noTitle && <ChartCard.Title as="h2">Accessible Chart</ChartCard.Title>}
        <ChartCard.Description>Chart of issues over time</ChartCard.Description>
        <ChartCard.LineChart
          series={series}
          options={{
            xAxis: {
              title: 'Time',
              type: 'datetime',
              labels: {
                format: 'Jan {value}',
              },
            },
            yAxis: {
              title: 'Issues',
              labels: {
                formatter: ({value}) => `${value} issues`,
              },
            },
            plot: {
              pointStart: 2012,
            },
          }}
        />
      </ChartCard>
    </div>,
  )
}

test('ChartCard calls console.errors when there are more than 11 lines', () => {
  const errorHandler = jest.spyOn(console, 'error').mockImplementation()

  createChartCard({count: 12})
  expect(errorHandler).toHaveBeenCalled()
})

test('ChartCard does not call console.errors when there are less than 11 lines', () => {
  const errorHandler = jest.spyOn(console, 'error').mockImplementation()

  createChartCard()
  expect(errorHandler).not.toHaveBeenCalled()
})
