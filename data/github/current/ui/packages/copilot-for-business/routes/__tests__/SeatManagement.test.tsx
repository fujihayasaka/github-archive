import {render} from '@github-ui/react-core/test-utils'
import {fireEvent, screen} from '@testing-library/react'
import {
  getSeatManagementRoutePayload,
  getSeatManagementRoutePayloadWithoutSeats,
  testFeatureRequestInfo,
} from '../../test-utils/mock-data'
import {CopilotForBusinessSeatPolicy} from '../../types'
import SeatManagement from '../SeatManagement'
import {expectAnalyticsEvents} from '@github-ui/analytics-test-utils'

describe('SeatManagement component', () => {
  it('renders the index page', () => {
    const routePayload = getSeatManagementRoutePayload()
    render(<SeatManagement />, {routePayload})
    expect(screen.getByRole('heading', {level: 2})).toHaveTextContent('GitHub Copilot')
  })

  it('renders the header correctly when on a Copilot Business trial', () => {
    const routePayload = {
      ...getSeatManagementRoutePayload(),
      business_trial: {
        has_trial: true,
        copilot_plan: 'business',
      },
    }
    render(<SeatManagement />, {routePayload})
    expect(screen.getByRole('heading', {level: 2})).toHaveTextContent('GitHub Copilot Business')
    expect(screen.getByText('Trial')).toBeInTheDocument()
  })

  it('renders the header correctly when on a Copilot Business plan', () => {
    const routePayload = {
      ...getSeatManagementRoutePayload(),
      business_trial: {
        has_trial: false,
        copilot_plan: 'business',
      },
    }
    render(<SeatManagement />, {routePayload})
    expect(screen.getByRole('heading', {level: 2})).toHaveTextContent('GitHub Copilot Business')
    expect(screen.queryByText('Trial')).not.toBeInTheDocument()
  })

  it('renders the header correctly when on a Copilot Enterprise trial', () => {
    const routePayload = {
      ...getSeatManagementRoutePayload(),
      business_trial: {
        has_trial: true,
        copilot_plan: 'enterprise',
      },
    }
    render(<SeatManagement />, {routePayload})
    expect(screen.getByRole('heading', {level: 2})).toHaveTextContent('GitHub Copilot Enterprise')
    expect(screen.getByText('Trial')).toBeInTheDocument()
  })

  it('renders the header correctly when on a Copilot Enterprise plan', () => {
    const routePayload = {
      ...getSeatManagementRoutePayload(),
      business_trial: {
        has_trial: false,
        copilot_plan: 'enterprise',
      },
      plan_text: 'Enterprise',
    }
    render(<SeatManagement />, {routePayload})
    expect(screen.getByRole('heading', {level: 2})).toHaveTextContent('GitHub Copilot Enterprise')
    expect(screen.queryByText('Trial')).not.toBeInTheDocument()
  })

  describe('when the enablement policy is Disabled', () => {
    it('renders the seats when the organization has an org-level seat', () => {
      const routePayload = {
        ...getSeatManagementRoutePayload(),
        policy: CopilotForBusinessSeatPolicy.Disabled,
        organization: {
          ...getSeatManagementRoutePayload().organization,
          has_seat: true,
        },
      }
      render(<SeatManagement />, {routePayload})

      const seatsComponent = screen.getByTestId('seats-summary')
      expect(seatsComponent).toBeInTheDocument()
    })
  })

  describe('when the enablement policy is EnabledForSelected', () => {
    it('renders the seats', () => {
      const routePayload = {
        ...getSeatManagementRoutePayload(),
        policy: CopilotForBusinessSeatPolicy.EnabledForSelected,
      }
      render(<SeatManagement />, {routePayload})

      const seatsComponent = screen.getByTestId('seats-summary')
      expect(seatsComponent).toBeInTheDocument()
    })
  })

  describe('when the enablement policy is EnabledForAll', () => {
    it('renders the seats when the organization has an org-level seat', () => {
      const routePayload = {
        ...getSeatManagementRoutePayload(),
        policy: CopilotForBusinessSeatPolicy.EnabledForAll,
        organization: {
          ...getSeatManagementRoutePayload().organization,
          has_seat: true,
        },
      }
      render(<SeatManagement />, {routePayload})

      const seatsComponent = screen.getByTestId('seats-summary')
      expect(seatsComponent).toBeInTheDocument()
    })
  })

  describe('when the user can allow the organization to assign seats', () => {
    const routePayload = {
      ...getSeatManagementRoutePayload(),
      can_allow_to_assign_seats_on_business: true,
      business: {
        name: 'GitHub',
        slug: 'github',
      },
    }

    it('renders the Allow to assign seats button', () => {
      render(<SeatManagement />, {routePayload})

      expect(screen.getByTestId('allow-this-organization-to-assign-seats-button')).toBeInTheDocument()
    })

    it('does not render the enablement policy', () => {
      render(<SeatManagement />, {routePayload})

      expect(screen.queryByTestId('cfb-no-seats')).not.toBeInTheDocument()
    })

    it('triggers hydro event when Allow to assign seats button is clicked', () => {
      render(<SeatManagement />, {routePayload})

      const button = screen.getByTestId('allow-this-organization-to-assign-seats-button')
      // eslint-disable-next-line testing-library/prefer-user-event
      fireEvent.click(button)

      expectAnalyticsEvents({
        type: 'analytics.click',
        data: {
          category: 'assign_seats_cta',
          action: `click_to_allow_to_assign_seats`,
          label: `ref_cta:allow_to_assign_seats;ref_loc:seat_management`,
        },
      })
    })
  })

  describe('when the user is unable to allow the org to assign seats (enterprise-owned)', () => {
    const routePayload = {
      ...getSeatManagementRoutePayload(),
      can_allow_to_assign_seats_on_business: false,
      featureRequestInfo: {
        ...testFeatureRequestInfo,
        showFeatureRequest: true,
        isEnterpriseRequest: true,
        billingEntityId: '123',
      },
    }

    it('renders correct `FeatureRequest` action', () => {
      render(<SeatManagement />, {routePayload})

      expect(screen.queryByTestId('allow-this-organization-to-assign-seats-button')).not.toBeInTheDocument()

      const requestButton = screen.getByTestId('request-feature-enterprise-owners-button')
      expect(requestButton.textContent).toBe('Ask enterprise owners for access')
    })
  })

  it('renders correct text when when 1 or more members requested copilot', () => {
    const routePayload = {
      ...getSeatManagementRoutePayload(),
      can_allow_to_assign_seats_on_business: false,
      featureRequestInfo: {
        ...testFeatureRequestInfo,
        showFeatureRequest: true,
        isEnterpriseRequest: true,
        billingEntityId: '123',
        amountOfUserRequests: 1,
        latestUsernameRequests: ['username'],
      },
    }

    render(<SeatManagement />, {routePayload})

    const requestButton = screen.getByTestId('request-feature-enterprise-owners-button')
    const memberRequestText = screen.getByTestId('member-request-text')

    expect(requestButton.textContent).toBe('Ask enterprise owners for access')
    expect(memberRequestText.textContent).toBe('@username is')
  })

  it('renders correct text when when 2 or more members requested copilot', () => {
    const routePayload = {
      ...getSeatManagementRoutePayload(),
      can_allow_to_assign_seats_on_business: false,
      featureRequestInfo: {
        ...testFeatureRequestInfo,
        showFeatureRequest: true,
        isEnterpriseRequest: true,
        billingEntityId: '123',
        amountOfUserRequests: 2,
        latestUsernameRequests: ['username1', 'username2'],
      },
    }

    render(<SeatManagement />, {routePayload})

    const requestButton = screen.getByTestId('request-feature-enterprise-owners-button')
    const memberRequestText = screen.getByTestId('member-request-text')

    expect(requestButton.textContent).toBe('Ask enterprise owners for access')
    expect(memberRequestText.textContent).toBe('@username1 and 1 more member are')
  })

  it('renders correct text when when 3 or more members requested copilot', () => {
    const routePayload = {
      ...getSeatManagementRoutePayload(),
      can_allow_to_assign_seats_on_business: false,
      featureRequestInfo: {
        ...testFeatureRequestInfo,
        showFeatureRequest: true,
        isEnterpriseRequest: true,
        billingEntityId: '123',
        amountOfUserRequests: 3,
        latestUsernameRequests: ['username1', 'username2', 'username3'],
      },
    }

    render(<SeatManagement />, {routePayload})

    const requestButton = screen.getByTestId('request-feature-enterprise-owners-button')
    const memberRequestText = screen.getByTestId('member-request-text')

    expect(requestButton.textContent).toBe('Ask enterprise owners for access')
    expect(memberRequestText.textContent).toBe('@username1 and 2 more members are')
  })
})

test('Renders seat assignment blankslate when there are no seats', () => {
  const routePayload = getSeatManagementRoutePayloadWithoutSeats()
  render(<SeatManagement />, {
    routePayload,
  })

  expect(screen.getByText(/No members are using GitHub Copilot in this organization/)).toBeInTheDocument()
})

test('Renders seat management when there are seats', () => {
  const routePayload = getSeatManagementRoutePayload()
  render(<SeatManagement />, {
    routePayload,
  })

  expect(screen.getByText('Copilot Business is active in your organization')).toBeInTheDocument()
})

describe('Warning messages', () => {
  it('Renders warning when org has no payment method', () => {
    const routePayload = getSeatManagementRoutePayload()
    routePayload.organization.billable = false
    routePayload.business = undefined
    render(<SeatManagement />, {routePayload})
    expect(screen.getByText('Provide payment details to start adding seats')).toBeInTheDocument()
  })

  it('Renders warning when org with business account has no payment method', () => {
    const routePayload = getSeatManagementRoutePayload()
    routePayload.organization.billable = false
    render(<SeatManagement />, {routePayload})
    expect(screen.getByText(/Contact your enterprise's adminstrator to add a payment method/)).toBeInTheDocument()
  })

  it('Renders warning about Copilot Business trial ending soon', () => {
    const routePayload = getSeatManagementRoutePayload()
    routePayload.business_trial = {
      started: true,
      ended: false,
      has_trial: true,
      upgradable: true,
      cancelable: true,
      days_left: 14,
      started_at: String(Date.now()),
      ends_at: String(Date.now() + 14),
      trial_length: 14,
      active: true,
      expired: false,
      pending: false,
      copilot_plan: 'business',
    }
    render(<SeatManagement />, {routePayload})
    expect(screen.getByTestId('cfb-trial-expiration-warning')).toHaveTextContent(
      'Your GitHub Copilot free trial expires in 14 days.',
    )
  })

  it('Renders warning about Copilot Business trial ending today', () => {
    const routePayload = getSeatManagementRoutePayload()
    routePayload.business_trial = {
      started: true,
      ended: false,
      has_trial: true,
      upgradable: true,
      cancelable: true,
      days_left: 0,
      started_at: String(Date.now()),
      ends_at: String(Date.now() + 14),
      trial_length: 14,
      active: true,
      expired: false,
      pending: false,
      copilot_plan: 'business',
    }
    render(<SeatManagement />, {routePayload})
    expect(screen.getByTestId('cfb-trial-expiration-warning')).toHaveTextContent(
      'Your GitHub Copilot free trial expires today.',
    )
  })

  it('Renders warning about Copilot Business trial ending in 1 day', () => {
    const routePayload = getSeatManagementRoutePayload()
    routePayload.business_trial = {
      started: true,
      ended: false,
      has_trial: true,
      upgradable: true,
      cancelable: true,
      days_left: 1,
      started_at: String(Date.now()),
      ends_at: String(Date.now() + 14),
      trial_length: 14,
      active: true,
      expired: false,
      pending: false,
      copilot_plan: 'business',
    }
    render(<SeatManagement />, {routePayload})
    expect(screen.getByTestId('cfb-trial-expiration-warning')).toHaveTextContent(
      'Your GitHub Copilot free trial expires in 1 day.',
    )
  })

  it('Renders warning about when Copilot Business trial starts', () => {
    const routePayload = getSeatManagementRoutePayload()
    routePayload.business_trial = {
      started: false,
      ended: false,
      has_trial: true,
      upgradable: true,
      cancelable: true,
      days_left: 14,
      started_at: String(Date.now()),
      ends_at: String(Date.now() + 14),
      trial_length: 14,
      active: true,
      expired: false,
      pending: true,
      copilot_plan: 'business',
    }
    render(<SeatManagement />, {routePayload})
    expect(screen.getByTestId('cfb-trial-expiration-warning')).toHaveTextContent(
      'Your GitHub Copilot free trial expires 14 days after the first seat is added.',
    )
  })

  it('Renders warning about Copilot Enterprise trial ending soon', () => {
    const routePayload = getSeatManagementRoutePayload()
    routePayload.business_trial = {
      started: true,
      ended: false,
      has_trial: true,
      upgradable: true,
      cancelable: true,
      days_left: 14,
      started_at: String(Date.now()),
      ends_at: String(Date.now() + 14),
      trial_length: 14,
      active: true,
      expired: false,
      pending: false,
      copilot_plan: 'enterprise',
    }
    render(<SeatManagement />, {routePayload})
    expect(screen.getByTestId('cfb-trial-expiration-warning')).toHaveTextContent(
      'Your GitHub Copilot Enterprise trial expires in 14 days. Upgrade to the paid version of Copilot Enterprise or your access will be downgraded to Copilot Business.',
    )
  })

  it('Renders warning about Copilot Enterprise trial ending today', () => {
    const routePayload = getSeatManagementRoutePayload()
    routePayload.business_trial = {
      started: true,
      ended: false,
      has_trial: true,
      upgradable: true,
      cancelable: true,
      days_left: 0,
      started_at: String(Date.now()),
      ends_at: String(Date.now() + 14),
      trial_length: 14,
      active: true,
      expired: false,
      pending: false,
      copilot_plan: 'enterprise',
    }
    render(<SeatManagement />, {routePayload})
    expect(screen.getByTestId('cfb-trial-expiration-warning')).toHaveTextContent(
      'Your GitHub Copilot Enterprise trial expires today. Upgrade to the paid version of Copilot Enterprise or your access will be downgraded to Copilot Business.',
    )
  })

  it('Renders warning about Copilot Enterprise trial ending in 1 day', () => {
    const routePayload = getSeatManagementRoutePayload()
    routePayload.business_trial = {
      started: true,
      ended: false,
      has_trial: true,
      upgradable: true,
      cancelable: true,
      days_left: 1,
      started_at: String(Date.now()),
      ends_at: String(Date.now() + 1),
      trial_length: 1,
      active: true,
      expired: false,
      pending: false,
      copilot_plan: 'enterprise',
    }
    render(<SeatManagement />, {routePayload})
    expect(screen.getByTestId('cfb-trial-expiration-warning')).toHaveTextContent(
      'Your GitHub Copilot Enterprise trial expires in 1 day. Upgrade to the paid version of Copilot Enterprise or your access will be downgraded to Copilot Business.',
    )
  })

  it('Renders warning about when Copilot Enterprise trial starts', () => {
    const routePayload = getSeatManagementRoutePayload()
    routePayload.business_trial = {
      started: false,
      ended: false,
      has_trial: true,
      upgradable: true,
      cancelable: true,
      days_left: 14,
      started_at: String(Date.now()),
      ends_at: String(Date.now() + 14),
      trial_length: 14,
      active: true,
      expired: false,
      pending: true,
      copilot_plan: 'enterprise',
    }
    render(<SeatManagement />, {routePayload})
    expect(screen.getByTestId('cfb-trial-expiration-warning')).toHaveTextContent(
      'Your GitHub Copilot Enterprise trial expires 14 days after Copilot in github.com policy is enabled and seats are assigned. Upgrade to the paid version of Copilot Enterprise or your access will be downgraded to Copilot Business.',
    )
  })

  it('renders warning but does not include the instruction on how to upgrade when the business already has a Copilot Enterprise plan', () => {
    const routePayload = getSeatManagementRoutePayload()
    routePayload.business_trial = {
      started: false,
      ended: false,
      has_trial: true,
      upgradable: true,
      cancelable: true,
      days_left: 14,
      started_at: String(Date.now()),
      ends_at: String(Date.now() + 14),
      trial_length: 14,
      active: true,
      expired: false,
      pending: true,
      copilot_plan: 'enterprise',
    }
    routePayload.plan_text = 'Enterprise'
    render(<SeatManagement />, {routePayload})
    expect(screen.getByTestId('cfb-trial-expiration-warning')).toHaveTextContent(
      'Your GitHub Copilot Enterprise trial expires 14 days after Copilot in github.com policy is enabled and seats are assigned.',
    )
    expect(screen.getByTestId('cfb-trial-expiration-warning')).not.toHaveTextContent(
      'Upgrade to the paid version of Copilot Enterprise or your access will be downgraded to Copilot Business.',
    )
  })

  it("renders a banner when the organization's Copilot Enterprise trial has expired", () => {
    const routePayload = getSeatManagementRoutePayload()

    routePayload.business_trial = {
      started: false,
      ended: true,
      has_trial: false,
      upgradable: false,
      cancelable: false,
      days_left: 0,
      started_at: String(Date.now() - 2),
      ends_at: String(Date.now() - 1),
      trial_length: 14,
      active: false,
      expired: true,
      pending: false,
      copilot_plan: 'enterprise',
    }
    routePayload.render_trial_expired_banner = true

    const portal = document.createElement('div')
    portal.setAttribute('id', 'js-flash-container')
    document.body.appendChild(portal)
    render(<SeatManagement />, {routePayload})
    expect(screen.getByTestId('cfb-trial-expired')).toHaveTextContent(
      'Your GitHub Copilot Enterprise trial has expired and your access has been downgraded to Copilot Business. You can purchase Copilot Enterprise or contact your sales representative to continue using Enterprise features.',
    )
  })

  it("renders a banner when the organization's Copilot Enterprise trial has expired and the mixed licensing feature is enabled", () => {
    const routePayload = getSeatManagementRoutePayload()

    routePayload.business_trial = {
      started: false,
      ended: true,
      has_trial: false,
      upgradable: false,
      cancelable: false,
      days_left: 0,
      started_at: String(Date.now() - 2),
      ends_at: String(Date.now() - 1),
      trial_length: 14,
      active: false,
      expired: true,
      pending: false,
      copilot_plan: 'enterprise',
    }
    routePayload.render_trial_expired_banner = true

    const portal = document.createElement('div')
    portal.setAttribute('id', 'js-flash-container')
    document.body.appendChild(portal)
    render(<SeatManagement />, {
      routePayload,
      appPayload: makeFeatureFlags({copilot_mixed_licenses: true}),
    })
    expect(screen.getByTestId('cfb-trial-expired')).toHaveTextContent(
      'Your GitHub Copilot Enterprise trial has expired and your access has been downgraded to Copilot Business. You can contact your enterprise administrator to continue using Enterprise features.',
    )
  })

  it("does not render a banner when the organization's enterprise has a Copilot Enterprise plan", () => {
    const routePayload = getSeatManagementRoutePayload()

    routePayload.business_trial = {
      started: false,
      ended: true,
      has_trial: false,
      upgradable: false,
      cancelable: false,
      days_left: 0,
      started_at: String(Date.now() - 2),
      ends_at: String(Date.now() - 1),
      trial_length: 14,
      active: false,
      expired: true,
      pending: false,
      copilot_plan: 'enterprise',
    }
    routePayload.render_trial_expired_banner = false
    routePayload.plan_text = 'Enterprise'

    const portal = document.createElement('div')
    portal.setAttribute('id', 'js-flash-container')
    document.body.appendChild(portal)
    render(<SeatManagement />, {routePayload})
    expect(screen.queryByTestId('cfb-trial-expired')).not.toBeInTheDocument()
  })

  it("renders a pending downgrade banner when the organization's Copilot plan is scheduled to be downgraded", () => {
    const routePayload = getSeatManagementRoutePayload()
    routePayload.render_pending_downgrade_banner = true

    render(<SeatManagement />, {routePayload})
    expect(screen.getByTestId('pending-downgrade-banner')).toBeInTheDocument()
  })

  it("does not render a pending downgrade banner when the organization's Copilot plan is scheduled to be downgraded", () => {
    const routePayload = getSeatManagementRoutePayload()
    routePayload.render_pending_downgrade_banner = false

    render(<SeatManagement />, {routePayload})
    expect(screen.queryByTestId('pending-downgrade-banner')).not.toBeInTheDocument()
  })

  it('renders a banner when the organization has a misconfigured plan', () => {
    // Fixes issues described here https://github.com/github/primer/issues/3882
    // Note: this error occurs due to our usage of `@container` within a
    // `<style>` tag in Banner. The CSS parser for jsdom does not support this
    // syntax and will fail with an error containing the message below.
    // Tracking issue: https://github.com/github/primer/issues/3882
    // eslint-disable-next-line no-console
    const originalConsoleError = console.error
    jest.spyOn(console, 'error').mockImplementation((value, ...args) => {
      if (!value?.message?.includes('Could not parse CSS stylesheet')) {
        originalConsoleError(value, ...args)
      }
    })

    const routePayload = getSeatManagementRoutePayload()
    routePayload.render_misconfigured_plan_for_org_banner = true

    render(<SeatManagement />, {routePayload})
    expect(screen.getByTestId('cfb-unconfigured-org-banner')).toBeInTheDocument()
  })
  it('does not render a banner when the organization plan is configured', () => {
    const routePayload = getSeatManagementRoutePayload()

    render(<SeatManagement />, {routePayload})
    expect(screen.queryByTestId('cfb-unconfigured-org-banner')).not.toBeInTheDocument()
  })
})

function makeFeatureFlags(flags: Record<string, boolean> = {}) {
  return {
    enabled_features: {
      ...flags,
    },
  }
}
