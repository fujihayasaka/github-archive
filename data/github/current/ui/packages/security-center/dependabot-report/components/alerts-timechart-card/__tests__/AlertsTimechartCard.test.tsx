import {setupUserEvent} from '@github-ui/react-core/test-utils'
import type {UseQueryResult} from '@github-ui/react-query'
import {act, screen} from '@testing-library/react'

import {OrgPaths} from '../../../../common/contexts/Paths'
import {render} from '../../../../test-utils/Render'
import {AlertsTimechartCard} from '../AlertsTimechartCard'
import {useAlertTrendsQuery} from '../use-alert-trends-query'

jest.mock('../use-alert-trends-query')
function mockUseAlertTrendsQuery<TResult>(result: Partial<UseQueryResult<TResult>>): void {
  ;(useAlertTrendsQuery as jest.Mock).mockReturnValue({
    isPending: false,
    isError: false,
    isSuccess: false,
    data: {},
    ...result,
  })
}

jest.mock('../FunnelOrderingDialog', () => ({
  FunnelOrderingDialog: ({
    onSubmit,
    closeDialog,
  }: {
    onSubmit: (order: string[]) => void
    closeDialog: () => void
  }): JSX.Element => {
    return (
      <div role="dialog" aria-labelledby="funnel-order-dialog-title">
        <h1 id="funnel-order-dialog-title">Configure funnel order</h1>
        <button
          onClick={() => {
            onSubmit(['epss_percentage:>=0.01', 'severity:critical,high', 'has:patch'])
          }}
        >
          Apply Reorder
        </button>
        <button onClick={closeDialog}>Cancel</button>
      </div>
    )
  },
}))

jest.mock('react-chartjs-2', () => ({
  Line: jest.fn(),
}))

const paths = new OrgPaths('my-org')

describe('AlertsTimechartCard', () => {
  beforeAll(() => {
    // push a fake URL so window.location.pathname === "/orgs/github"
    window.history.pushState({}, 'Test page', '/orgs/github')
  })

  it('should render', async () => {
    mockUseAlertTrendsQuery({
      isSuccess: true,
      data: {
        label: 'Open Alerts',
        points: [
          {x: 'Matching Alerts', y: 1},
          {x: 'has:patch', y: 1},
          {x: 'severity:critical,high', y: 1},
          {x: 'epss_percentage:>=0.01', y: 1},
        ],
      },
    })

    // AlertsTimechartCard renders DragAndDrop, which has some internal useEffect calls that perform async updates
    // so we wrap the render in an act()
    // eslint-disable-next-line testing-library/no-unnecessary-act
    await act(async () => {
      render(<AlertsTimechartCard allowedDependabotQualifiers={['severity', 'has:patch', 'epss_percentage']} />)
    })

    expect(screen.getByText('Alert prioritization')).toBeInTheDocument()
    expect(screen.getByTestId('chart-card')).toBeInTheDocument()
  })

  it('should render loading state', async () => {
    mockUseAlertTrendsQuery({
      isPending: true,
    })

    // eslint-disable-next-line testing-library/no-unnecessary-act
    await act(async () => {
      render(<AlertsTimechartCard allowedDependabotQualifiers={['severity', 'has:patch', 'epss_percentage']} />)
    })

    expect(screen.getByText('Alert prioritization')).toBeInTheDocument()
    expect(screen.getByTestId('loading-indicator')).toBeInTheDocument()
  })

  it('should render error state', async () => {
    mockUseAlertTrendsQuery({
      isError: true,
    })

    // eslint-disable-next-line testing-library/no-unnecessary-act
    await act(async () => {
      render(<AlertsTimechartCard allowedDependabotQualifiers={['severity', 'has:patch', 'epss_percentage']} />)
    })

    expect(screen.getByText('Alert prioritization')).toBeInTheDocument()
    expect(screen.getByTestId('error')).toBeInTheDocument()
  })

  it('should render no-data state if no series returned', async () => {
    mockUseAlertTrendsQuery({
      isSuccess: true,
      data: {},
    })

    // eslint-disable-next-line testing-library/no-unnecessary-act
    await act(async () => {
      render(<AlertsTimechartCard allowedDependabotQualifiers={['severity', 'has:patch', 'epss_percentage']} />)
    })

    expect(screen.getByText('Alert prioritization')).toBeInTheDocument()
    expect(screen.getByTestId('no-data')).toBeInTheDocument()
  })

  it('should render no-data state if no data points returned', async () => {
    mockUseAlertTrendsQuery({
      isSuccess: true,
      data: {
        label: 'Open Alerts',
        points: [],
      },
    })

    // eslint-disable-next-line testing-library/no-unnecessary-act
    await act(async () => {
      render(<AlertsTimechartCard allowedDependabotQualifiers={['severity', 'has:patch', 'epss_percentage']} />)
    })

    expect(screen.getByText('Alert prioritization')).toBeInTheDocument()
    expect(screen.getByTestId('no-data')).toBeInTheDocument()
  })

  it('should render no-data state if all data points are zero', async () => {
    mockUseAlertTrendsQuery({
      isSuccess: true,
      data: {
        label: 'Open Alerts',
        points: [
          {x: 'Matching Alerts', y: 0},
          {x: 'has:patch', y: 0},
          {x: 'severity:critical,high', y: 0},
          {x: 'epss_percentage:>=0.01', y: 0},
        ],
      },
    })

    // eslint-disable-next-line testing-library/no-unnecessary-act
    await act(async () => {
      render(<AlertsTimechartCard allowedDependabotQualifiers={['severity', 'has:patch', 'epss_percentage']} />)
    })

    expect(screen.getByText('Alert prioritization')).toBeInTheDocument()
    expect(screen.getByTestId('no-data')).toBeInTheDocument()
  })

  it('should open the funnel ordering dialog', async () => {
    const user = setupUserEvent()

    mockUseAlertTrendsQuery({
      isSuccess: true,
      data: {},
    })

    // eslint-disable-next-line testing-library/no-unnecessary-act
    await act(async () => {
      render(<AlertsTimechartCard allowedDependabotQualifiers={['severity', 'has:patch', 'epss_percentage']} />)
    })

    const configButton = screen.getByLabelText('Configure funnel categories')
    await user.click(configButton)

    expect(screen.getByRole('dialog')).toBeInTheDocument()
    expect(screen.getByText('Configure funnel order')).toBeInTheDocument()
  })

  it('should update state when a new funnel order is applied', async () => {
    const user = setupUserEvent()

    mockUseAlertTrendsQuery({
      isSuccess: true,
      data: {
        label: 'Open Alerts',
        points: [
          {x: 'Matching Alerts', y: 5},
          {x: 'has:patch', y: 10},
          {x: 'severity:critical,high', y: 20},
          {x: 'epss_percentage:>=0.01', y: 30},
        ],
      },
    })

    // eslint-disable-next-line testing-library/no-unnecessary-act
    await act(async () => {
      render(<AlertsTimechartCard allowedDependabotQualifiers={['severity', 'has:patch', 'epss_percentage']} />)
    })

    const gearButton = screen.getByLabelText('Configure funnel categories')
    await user.click(gearButton)

    const applyReorderButton = screen.getByText('Apply Reorder')
    await user.click(applyReorderButton)

    // TODO: we should also assert the Y values changed as expected, not just the reordering of the X category labels

    // The new order does not match the default → expect dirty state
    expect(screen.getByText('Reset to default')).toBeInTheDocument()
  })

  it('should cancel changes and close dialog without updating order', async () => {
    const user = setupUserEvent()

    mockUseAlertTrendsQuery({
      isSuccess: true,
      data: {},
    })

    // eslint-disable-next-line testing-library/no-unnecessary-act
    await act(async () => {
      render(<AlertsTimechartCard allowedDependabotQualifiers={['severity', 'has:patch', 'epss_percentage']} />)
    })

    // Open dialog
    const configButton = screen.getByLabelText('Configure funnel categories')
    await user.click(configButton)

    // Click cancel
    const cancelButton = screen.getByText('Cancel')
    await user.click(cancelButton)

    // Verify dialog is closed
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
  })

  it('should render clickable links with cumulative filters for each category', async () => {
    mockUseAlertTrendsQuery({
      isSuccess: true,
      data: {
        label: 'Open Alerts',
        points: [
          {x: 'Matching Alerts', y: 5},
          {x: 'has:patch', y: 10},
          {x: 'severity:critical,high', y: 20},
          {x: 'epss_percentage:>=0.01', y: 30},
        ],
      },
    })

    // eslint-disable-next-line testing-library/no-unnecessary-act
    await act(async () => {
      render(<AlertsTimechartCard allowedDependabotQualifiers={['severity', 'has:patch', 'epss_percentage']} />)
    })

    const epssHref = paths.dependabotAlertsListPath({
      query: 'has:patch severity:critical,high epss_percentage:>=0.01',
    })
    const patchHref = paths.dependabotAlertsListPath({query: 'has:patch'})

    const chartCard = screen.getByTestId('chart-card')
    expect(chartCard.innerHTML).toContain(`href="${epssHref}"`)
    expect(chartCard.innerHTML).toContain(`href="${patchHref}"`)
  })

  it('should update links based on new funnel order', async () => {
    mockUseAlertTrendsQuery({
      isSuccess: true,
      data: {
        label: 'Open Alerts',
        points: [
          {x: 'Matching Alerts', y: 5},
          {x: 'epss_percentage:>=0.01', y: 30},
          {x: 'severity:critical,high', y: 20},
          {x: 'has:patch', y: 10},
        ],
      },
    })

    // eslint-disable-next-line testing-library/no-unnecessary-act
    await act(async () => {
      render(<AlertsTimechartCard allowedDependabotQualifiers={['severity', 'has:patch', 'epss_percentage']} />)
    })

    const user = setupUserEvent()
    await user.click(screen.getByLabelText('Configure funnel categories'))
    await user.click(screen.getByText('Apply Reorder'))

    const epssHref = paths.dependabotAlertsListPath({
      query: 'epss_percentage:>=0.01',
    })
    const patchHref = paths.dependabotAlertsListPath({
      query: 'epss_percentage:>=0.01 severity:critical,high has:patch',
    })

    const chartCard = screen.getByTestId('chart-card')
    expect(chartCard.innerHTML).toContain(`href="${epssHref}"`)
    expect(chartCard.innerHTML).toContain(`href="${patchHref}"`)
  })

  it('should render cumulative filter link when clicking on Critical or High Severity (2-category order)', async () => {
    mockUseAlertTrendsQuery({
      isSuccess: true,
      data: {
        label: 'Open Alerts',
        points: [
          {x: 'Matching Alerts', y: 5},
          {x: 'has:patch', y: 10},
          {x: 'Critical or High Severity', y: 20},
        ],
      },
    })

    // eslint-disable-next-line testing-library/no-unnecessary-act
    await act(async () => {
      render(<AlertsTimechartCard allowedDependabotQualifiers={['severity', 'has:patch', 'epss_percentage']} />)
    })

    const user = setupUserEvent()
    await user.click(screen.getByLabelText('Configure funnel categories'))

    // Expected: Cumulative filters should be "has:patch severity:critical,high"
    const expectedHref = paths.dependabotAlertsListPath({
      query: 'has:patch severity:critical,high',
    })

    const chartCard = screen.getByTestId('chart-card')
    expect(chartCard.innerHTML).toContain(`href="${expectedHref}"`)
  })

  it('should reset to default funnel order when "Reset to default" is clicked', async () => {
    const user = setupUserEvent()

    mockUseAlertTrendsQuery({
      isSuccess: true,
      data: {
        label: 'Open Alerts',
        points: [
          {x: 'Matching Alerts', y: 5},
          {x: 'has:patch', y: 10},
          {x: 'severity:critical,high', y: 20},
          {x: 'epss_percentage:>=0.01', y: 30},
        ],
      },
    })

    // eslint-disable-next-line testing-library/no-unnecessary-act
    await act(async () => {
      render(<AlertsTimechartCard allowedDependabotQualifiers={['severity', 'has:patch', 'epss_percentage']} />)
    })

    // 1. Open funnel ordering dialog
    const configButton = screen.getByLabelText('Configure funnel categories')
    await user.click(configButton)

    // 2. Apply new order: epss_percentage:>=0.01 → severity:critical,high → Patch
    const applyReorderButton = screen.getByText('Apply Reorder')
    await user.click(applyReorderButton)

    // 3. Click "Reset to default"
    const resetButton = screen.getByText('Reset to default')
    await user.click(resetButton)

    // 4. Verify that Patch → severity:critical,high → epss_percentage:>=0.01 is the restored order in URL
    const expectedHref = paths.dependabotAlertsListPath({
      query: 'has:patch severity:critical,high epss_percentage:>=0.01',
    })
    const chartCard = screen.getByTestId('chart-card')
    expect(chartCard.innerHTML).toContain(`href="${expectedHref}"`)
  })

  it('formats large counts with commas in the label', async () => {
    mockUseAlertTrendsQuery({
      isSuccess: true,
      data: {
        label: 'Open Alerts',
        points: [
          {x: 'Matching Alerts', y: 179457},
          {x: 'has:patch', y: 0},
          {x: 'severity:critical,high', y: 0},
          {x: 'epss_percentage:>=0.01', y: 0},
        ],
      },
    })

    // eslint-disable-next-line testing-library/no-unnecessary-act
    await act(async () => {
      render(<AlertsTimechartCard allowedDependabotQualifiers={['severity', 'has:patch', 'epss_percentage']} />)
    })

    const chartCard = screen.getByTestId('chart-card')
    // look for the <strong> wrapper with the formatted number:
    expect(chartCard.innerHTML).toContain('<strong>179,457</strong>')
  })
})
