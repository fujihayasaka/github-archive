import {screen, waitFor} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {Box} from '@primer/react'
import {DateProvider} from '../stories/Props/RangeSelector/DateContext'
import {PeriodMenu} from '../stories/Props/RangeSelector/PeriodMenu'
import {ChartWithRangeSelector} from '../stories/Props/RangeSelector/ChartWithRangeSelector'

function createChartCard({children}: Parameters<typeof ChartWithRangeSelector>[0] = {children: null}) {
  return render(
    <div>
      <h1>Some page heading</h1>
      <DateProvider>
        <Box
          sx={{
            display: 'flex',
            justifyContent: 'flex-end',
            mb: 3,
          }}
        >
          <PeriodMenu />
        </Box>
        <ChartWithRangeSelector size="medium" border padding="normal" visibleControls>
          {children}
        </ChartWithRangeSelector>
      </DateProvider>
    </div>,
  )
}

beforeEach(() => {
  jest.useFakeTimers()
  jest.setSystemTime(new Date('December 20, 2024 00:00:00Z'))
})

test('Range selector handles have meaningful labels on load', async () => {
  createChartCard()

  await waitFor(() => {
    expect(screen.getByTestId('chart-card')).toBeInTheDocument()
  })

  // Verify Highcharts’ default labels are not present
  expect(screen.queryByRole('slider', {name: 'Start, percent'})).not.toBeInTheDocument()
  expect(screen.queryByRole('slider', {name: 'End, percent'})).not.toBeInTheDocument()

  // Verify ChartCard’s labels are related attributes are present
  const leftHandleProxy = screen.getByRole('slider', {name: 'Start of selected range'})
  const rightHandleProxy = screen.getByRole('slider', {name: 'End of selected range'})
  expect(leftHandleProxy).toBeInTheDocument()
  expect(leftHandleProxy).toHaveAttribute('aria-valuenow', '870393600000')
  expect(leftHandleProxy).toHaveAttribute('aria-valuemin', '870393600000')
  expect(leftHandleProxy).toHaveAttribute('aria-valuemax', '1734652800000')
  expect(leftHandleProxy).toHaveAttribute('aria-valuetext', '1997-08-01')
  expect(rightHandleProxy).toBeInTheDocument()
  expect(rightHandleProxy).toHaveAttribute('aria-valuenow', '1734652800000')
  expect(rightHandleProxy).toHaveAttribute('aria-valuemin', '870393600000')
  expect(rightHandleProxy).toHaveAttribute('aria-valuemax', '1734652800000')
  expect(rightHandleProxy).toHaveAttribute('aria-valuetext', '2024-12-20')
})
