import {render, screen} from '@testing-library/react'
import {SecurityCampaignListItemDescription} from '../../components/SecurityCampaignListItemDescription'
import {calculateDaysLeft} from '../../utils/calculate-days-left'
import {RelativeTime} from '@primer/react'
import type {User} from '@github-ui/filter/providers'
import {getSecurityCampaignWithCounts, getUser} from '../../test-utils/mock-data'
import type {SecurityCampaignWithCounts} from '../../types/security-campaign'

jest.mock('../../utils/calculate-days-left')

jest.mock('@github-ui/list-view/ListItemDescription', () => ({
  ListItemDescription: ({children}: {children: React.ReactNode}) => <div>{children}</div>,
}))

jest.mock('@primer/react', () => ({
  RelativeTime: jest.fn(({datetime}: {datetime: string}) => <time>{datetime}</time>),
}))

jest.mock('../../components/CampaignManagersText', () => ({
  CampaignManagersText: ({managers}: {managers: User[]}) => <div>{managers.map(m => m.login).join(', ')}</div>,
}))

describe('SecurityCampaignListItemDescription', () => {
  const mockCalculateDaysLeft = calculateDaysLeft as jest.Mock
  const mockRelativeTime = RelativeTime as jest.Mock

  beforeEach(() => {
    jest.clearAllMocks()
  })

  it('renders days left for open campaigns', () => {
    const campaign = getSecurityCampaignWithCounts()

    render(<SecurityCampaignListItemDescription campaign={campaign} status="open" showManagers={false} />)

    expect(screen.getByText(/days left/)).toBeInTheDocument()
  })

  it('renders days overdue for overdue campaigns', () => {
    const campaign = getSecurityCampaignWithCounts()
    mockCalculateDaysLeft.mockReturnValue(-2)

    render(<SecurityCampaignListItemDescription campaign={campaign} status="overdue" showManagers={false} />)

    expect(screen.getByText(/days/)).toBeInTheDocument()
    expect(screen.getByText(/overdue/)).toBeInTheDocument()
  })

  it('renders "complete" for completed campaigns', () => {
    const campaign: SecurityCampaignWithCounts = {
      ...getSecurityCampaignWithCounts(),
      openCount: 0,
      closedAt: null,
    }

    render(<SecurityCampaignListItemDescription campaign={campaign} status="completed" showManagers={false} />)

    expect(screen.getByText(/Complete/)).toBeInTheDocument()
  })

  it('renders "Closed" for closed campaigns', () => {
    const closedAt = new Date().toISOString()
    const campaign: SecurityCampaignWithCounts = {
      ...getSecurityCampaignWithCounts(),
      closedAt,
    }

    render(<SecurityCampaignListItemDescription campaign={campaign} status="closed" showManagers={false} />)

    expect(screen.getByText(/Closed/)).toBeInTheDocument()
    expect(mockRelativeTime).toHaveBeenCalledWith({datetime: closedAt}, {})
  })

  it('renders managers if showManagers is true', () => {
    const manager = getUser()
    const campaign = getSecurityCampaignWithCounts({managers: [manager]})

    render(<SecurityCampaignListItemDescription campaign={campaign} status="open" showManagers />)

    expect(screen.getByText(manager.login)).toBeInTheDocument()
  })

  it('does not render managers if showManagers is false', () => {
    const manager = getUser()
    const campaign = getSecurityCampaignWithCounts({managers: [manager]})

    render(<SecurityCampaignListItemDescription campaign={campaign} status="open" showManagers={false} />)

    expect(screen.queryByText(manager.login)).not.toBeInTheDocument()
  })

  it('renders Created for draft campaigns', () => {
    const createdAt = '2024-05-01T00:00:00.000Z'
    const campaign = getSecurityCampaignWithCounts({publishedAt: null, createdAt})

    render(<SecurityCampaignListItemDescription campaign={campaign} status="draft" showManagers={false} />)

    expect(screen.getByText(/Created/)).toBeInTheDocument()
    expect(mockRelativeTime).toHaveBeenCalledWith({datetime: createdAt}, {})
  })
})
