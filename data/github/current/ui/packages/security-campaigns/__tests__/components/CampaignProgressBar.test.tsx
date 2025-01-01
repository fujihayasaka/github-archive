import {screen} from '@testing-library/react'
import {render as reactRender} from '@github-ui/react-core/test-utils'
import {CampaignProgressBar, type CampaignProgressBarProps} from '../../components/CampaignProgressBar'

const defaultProps: CampaignProgressBarProps = {
  openCount: undefined,
  closedCount: undefined,
  openWithLinksCount: undefined,
}

const render = (props?: Partial<CampaignProgressBarProps>) =>
  reactRender(<CampaignProgressBar {...defaultProps} {...props} />)

describe('CampaignProgressBar', () => {
  test('renders with default values', () => {
    render()
    expect(screen.getByText('0% closed (0 alerts)')).toBeInTheDocument()
    expect(screen.getByRole('progressbar')).toHaveAttribute('aria-valuetext', '0% alerts closed, 0% in progress')
  })

  test('renders with open, in-progress and closed counts', () => {
    render({openCount: 5, closedCount: 5, openWithLinksCount: 2})
    expect(screen.getByText('50% closed (10 alerts)')).toBeInTheDocument()
    expect(screen.getByLabelText('Campaign alerts closed')).toHaveAttribute('aria-valuenow', '50')
    expect(screen.getByLabelText('Campaign alerts in progress')).toHaveAttribute('aria-valuenow', '20')
  })

  test('renders with all alerts closed', () => {
    render({openCount: 0, closedCount: 10})
    expect(screen.getByText('100% closed (10 alerts)')).toBeInTheDocument()
    expect(screen.getByLabelText('Campaign alerts closed')).toHaveAttribute('aria-valuenow', '100')
  })
})
