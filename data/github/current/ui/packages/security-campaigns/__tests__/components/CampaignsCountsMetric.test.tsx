import {screen} from '@testing-library/react'
import {CampaignsCountsMetric, type CampaignsCountsMetricProps} from '../../components/CampaignsCountsMetric'
import {render as reactRender} from '@github-ui/react-core/test-utils'

const defaultProps: CampaignsCountsMetricProps = {
  title: 'Open campaigns',
  description: 'Campaigns with open alerts',
  campaignsCount: 6,
  totalAlertCount: 620,
  openAlertsCount: 440,
  inProgressAlertsCount: 40,
  fixedAlertsCount: 40,
  dismissedAlertsCount: 10,
}

const render = (props?: Partial<CampaignsCountsMetricProps>) =>
  reactRender(<CampaignsCountsMetric {...defaultProps} {...props} />)

test('Renders open campaign counts', () => {
  render()

  expect(screen.getByText('Open campaigns')).toBeInTheDocument()
  expect(screen.getByText(`${defaultProps.totalAlertCount} alerts`)).toBeInTheDocument()
  expect(screen.getByText(`in ${defaultProps.campaignsCount} campaigns`)).toBeInTheDocument()
  expect(screen.getByText(`${defaultProps.openAlertsCount} open`)).toBeInTheDocument()
  expect(screen.getByText(`${defaultProps.inProgressAlertsCount} in progress`)).toBeInTheDocument()
  expect(screen.getByText(`${defaultProps.fixedAlertsCount} fixed`)).toBeInTheDocument()
  expect(screen.getByText(`${defaultProps.dismissedAlertsCount} dismissed`)).toBeInTheDocument()
})

test('Renders closed campaign counts', () => {
  render({title: 'Closed campaigns', inProgressAlertsCount: undefined})

  expect(screen.getByText('Closed campaigns')).toBeInTheDocument()
  expect(screen.getByText(`${defaultProps.totalAlertCount} alerts`)).toBeInTheDocument()
  expect(screen.getByText(`in ${defaultProps.campaignsCount} campaigns`)).toBeInTheDocument()
  expect(screen.getByText(`${defaultProps.openAlertsCount} open`)).toBeInTheDocument()
  expect(screen.getByText(`${defaultProps.fixedAlertsCount} fixed`)).toBeInTheDocument()
  expect(screen.getByText(`${defaultProps.dismissedAlertsCount} dismissed`)).toBeInTheDocument()
  expect(screen.queryByText('in progress')).not.toBeInTheDocument()
})
