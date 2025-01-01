import {render, screen, fireEvent, waitFor} from '@testing-library/react'
import {MembersSummaryCard} from '../MembersSummaryCard'
import type {CopilotForBusinessTrial, SeatBreakdown, PlanText} from '../../../types'
import {currency as formatCurrency} from '@github-ui/formatters'
import {planCost} from '../../../helpers/plan'
import {verifiedFetch} from '@github-ui/verified-fetch'
import {ThemeProvider, BaseStyles} from '@primer/react'

// Mock dependencies
// eslint-disable-next-line no-restricted-syntax
jest.mock('@github-ui/verified-fetch', () => ({
  verifiedFetch: jest.fn().mockResolvedValue({}),
}))

jest.mock('@github-ui/ssr-utils', () => ({
  ssrSafeLocation: {
    origin: 'https://github.com',
  },
}))

describe('MembersSummaryCard', () => {
  // Common test props
  const defaultProps = {
    slug: 'test-org',
    renderCopilotInsightsBanner: false,
    adoptionMetrics: {
      total: 100,
      active: 60,
      inactive: 30,
      dormant: 10,
    },
    seatBreakdown: {
      seats_billed: 100,
      seats_pending: 10,
      seats_assigned: 90,
      description: 'Test seats',
    },
    planText: 'Business' as PlanText,
  }

  // For tests that need date formatting
  beforeEach(() => {
    jest.clearAllMocks()
    jest.spyOn(Date.prototype, 'toLocaleDateString').mockReturnValue('March 15, 2025')
  })

  afterEach(() => {
    jest.restoreAllMocks()
  })

  describe('Component rendering', () => {
    test('renders the component with all required sections', () => {
      render(<MembersSummaryCard {...defaultProps} />)

      // Check main sections
      expect(screen.getByText('Members')).toBeInTheDocument()
      expect(screen.getByText('Estimated next payment')).toBeInTheDocument()
      expect(screen.getByText('View insights')).toBeInTheDocument()
      expect(screen.getByText('View billing')).toBeInTheDocument()
    })

    test('renders correct links with organization slug', () => {
      render(<MembersSummaryCard {...defaultProps} />)

      const insightsLink = screen.getByText('View insights')
      expect(insightsLink).toHaveAttribute(
        'href',
        'https://github.com/orgs/test-org/insights/metrics/copilot-user-onboarding',
      )

      const billingLink = screen.getByText('View billing')
      expect(billingLink).toHaveAttribute('href', 'https://github.com/organizations/test-org/settings/billing/summary')
    })
  })

  describe('Adoption metrics rendering', () => {
    test('renders all adoption metrics with correct values', () => {
      render(<MembersSummaryCard {...defaultProps} />)

      expect(screen.getByTestId('members-total')).toHaveTextContent('100')
      expect(screen.getByTestId('members-active')).toHaveTextContent('60')
      expect(screen.getByTestId('members-inactive')).toHaveTextContent('30')
      expect(screen.getByTestId('members-dormant')).toHaveTextContent('10')
    })

    test('renders zero values correctly when all metrics are zero', () => {
      const zeroMetrics = {
        total: 0,
        active: 0,
        inactive: 0,
        dormant: 0,
      }

      render(<MembersSummaryCard {...defaultProps} adoptionMetrics={zeroMetrics} />)

      expect(screen.getByTestId('members-total')).toHaveTextContent('0')
      expect(screen.getByTestId('members-active')).toHaveTextContent('0')
      expect(screen.getByTestId('members-inactive')).toHaveTextContent('0')
      expect(screen.getByTestId('members-dormant')).toHaveTextContent('0')
    })
  })

  describe('Cost calculation and display', () => {
    test('displays fallback text when seat count is zero', () => {
      const emptySeatBreakdown: SeatBreakdown = {
        seats_billed: 0,
        seats_pending: 0,
        seats_assigned: 0,
        description: 'Empty seats',
      }

      render(<MembersSummaryCard {...defaultProps} seatBreakdown={emptySeatBreakdown} />)

      expect(screen.getByTestId('members-cost')).toHaveTextContent('No data yet')
    })

    test('calculates and renders correct cost for non-trial accounts', () => {
      render(<MembersSummaryCard {...defaultProps} />)

      const seatCount = defaultProps.seatBreakdown.seats_billed + defaultProps.seatBreakdown.seats_pending
      const expectedCost = formatCurrency(seatCount * planCost('Business'))

      expect(screen.getByTestId('members-cost')).toHaveTextContent(expectedCost)
      expect(screen.getByTestId('members-per-seat')).toHaveTextContent(
        `Each assigned license is $${planCost('Business')} per month`,
      )
    })

    test('displays free cost text for business trial accounts', () => {
      const trial = {
        has_trial: true,
        active: true,
        ends_at: String(new Date()),
        copilot_plan: 'business',
      } as CopilotForBusinessTrial

      render(<MembersSummaryCard {...defaultProps} trial={trial} />)

      expect(screen.getByTestId('members-cost')).toHaveTextContent('Free')
      expect(screen.getByTestId('members-per-seat')).toHaveTextContent(
        'Free Copilot Business trial until March 15, 2025',
      )
    })

    test('displays free cost text but no trial text for inactive trials', () => {
      const trial = {
        has_trial: true,
        active: false,
        ends_at: String(new Date()),
        copilot_plan: 'business',
      } as CopilotForBusinessTrial

      render(<MembersSummaryCard {...defaultProps} trial={trial} />)

      expect(screen.getByTestId('members-cost')).toHaveTextContent('Free')
      expect(screen.getByTestId('members-per-seat')).toHaveTextContent('')
    })
  })

  describe('InsightPopover functionality', () => {
    test('renders insight popover when renderCopilotInsightsBanner is true', () => {
      render(<MembersSummaryCard {...defaultProps} renderCopilotInsightsBanner />)

      expect(screen.getByTestId('insight-popover')).toBeInTheDocument()
      expect(screen.getByText('Introducing Copilot Insights')).toBeInTheDocument()
      expect(screen.getByText(/You can now track how Copilot is being used/)).toBeInTheDocument()
    })

    test('does not render insight popover when renderCopilotInsightsBanner is false', () => {
      render(<MembersSummaryCard {...defaultProps} renderCopilotInsightsBanner={false} />)

      expect(screen.queryByTestId('insight-popover')).not.toBeInTheDocument()
      expect(screen.queryByText('Introducing Copilot Insights')).not.toBeInTheDocument()
    })

    test('dismisses the popover and calls verifiedFetch when "OK, got it" button is clicked', async () => {
      ;(verifiedFetch as jest.Mock).mockClear()

      render(<MembersSummaryCard {...defaultProps} renderCopilotInsightsBanner />)

      const dismissButton = screen.getByTestId('dismiss-forever-button')
      // eslint-disable-next-line testing-library/prefer-user-event
      fireEvent.click(dismissButton)

      await waitFor(() => {
        expect(verifiedFetch).toHaveBeenCalledWith(expect.stringContaining('copilot_insights_banner'), {
          method: 'POST',
        })
      })

      expect(screen.queryByTestId('insight-popover')).not.toBeInTheDocument()
    })
  })

  describe('MembersInfoOverlay functionality', () => {
    test('opens info overlay when info icon is clicked', () => {
      render(
        <ThemeProvider>
          <BaseStyles>
            <MembersSummaryCard {...defaultProps} />
          </BaseStyles>
        </ThemeProvider>,
      )

      const infoButton = screen.getByTestId('members-info-overlay-button')
      // eslint-disable-next-line testing-library/prefer-user-event
      fireEvent.click(infoButton)

      expect(screen.getByText('GitHub Copilot members')).toBeInTheDocument()
      expect(screen.getByText(/Each member is assigned a Copilot license/)).toBeInTheDocument()
      expect(screen.getByText('Learn more about licenses')).toBeInTheDocument()
    })
  })

  describe('Edge cases', () => {
    test('handles undefined trial gracefully', () => {
      render(<MembersSummaryCard {...defaultProps} trial={undefined} />)

      const seatCount = defaultProps.seatBreakdown.seats_billed + defaultProps.seatBreakdown.seats_pending
      const expectedCost = formatCurrency(seatCount * planCost('Business'))

      expect(screen.getByTestId('members-cost')).toHaveTextContent(expectedCost)
    })
  })
})
