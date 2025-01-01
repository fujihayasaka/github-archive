import {PlanForm} from '../../../apps/pricing-plans/PlanForm'
import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import {mockAppListing} from '@github-ui/marketplace-common/mock-data'
import {mockPlanInfo, mockPlan} from '../../../../test-utils/mock-data'
import type {AppListing} from '@github-ui/marketplace-common'
import type {PlanInfo, Plan} from '../../../../types'

interface RenderComponentOptions {
  listingOverrides?: Partial<AppListing>
  planInfoOverrides?: Partial<PlanInfo>
  planOverrides?: Partial<Plan>
  standaloneButton?: boolean
}

function renderComponent({
  listingOverrides = {},
  planInfoOverrides = {},
  planOverrides = {},
}: RenderComponentOptions = {}) {
  const listing = mockAppListing(listingOverrides)
  const planInfo = mockPlanInfo(planInfoOverrides)
  const plan = mockPlan(planOverrides)
  const account = planInfo.selectedAccount

  return {
    listing,
    planInfo,
    plan,
    ...render(
      <PlanForm
        listing={listing}
        planInfo={planInfo}
        plan={plan}
        selectedAccount={account}
        onAccountSelect={() => {}}
      />,
    ),
  }
}

describe('PlanForm', () => {
  beforeEach(() => {
    jest.clearAllMocks()
  })

  test('Renders component', () => {
    renderComponent()

    expect(screen.getByTestId('plan-form')).toBeInTheDocument()
  })

  test('skips order review for free copilot extensions', () => {
    renderComponent({
      listingOverrides: {copilotApp: true},
      planOverrides: {directBilling: false, isPaid: false},
    })

    expect(screen.getByTestId('plan-form')).toHaveAttribute('method', 'POST')
  })

  test('does not skip order review for paid copilot extensions', () => {
    renderComponent({
      listingOverrides: {copilotApp: true},
      planOverrides: {directBilling: false, isPaid: true},
    })

    expect(screen.getByTestId('plan-form')).toHaveAttribute('method', 'GET')
  })

  test('skips order review for direct billing plans', () => {
    renderComponent({
      planOverrides: {directBilling: true},
    })

    expect(screen.getByTestId('plan-form')).toHaveAttribute('method', 'POST')
  })

  test('does not skip order review for other plans', () => {
    renderComponent({
      planOverrides: {directBilling: false},
    })

    expect(screen.getByTestId('plan-form')).toHaveAttribute('method', 'GET')
  })

  describe('when skipping order review', () => {
    test('sends to upgrade path when updating plan', () => {
      const {listing, plan} = renderComponent({
        listingOverrides: {copilotApp: true},
        planOverrides: {id: '2', directBilling: false, isPaid: false},
        planInfoOverrides: {
          planIdByLogin: {monalisa: '1'},
          selectedAccount: 'monalisa',
        },
      })

      expect(screen.getByTestId('csrf-token')).toBeInTheDocument()
      expect(screen.getByTestId('plan-form')).toHaveAttribute(
        'action',
        `/marketplace/${listing.slug}/order/${plan.id}/upgrade`,
      )
      expect(screen.getByTestId('plan-form')).toHaveAttribute('method', 'POST')
    })
  })

  test('directs to upgrade path when plan has been purchased but not installed for selected account', () => {
    const {listing, plan} = renderComponent({
      planInfoOverrides: {
        installedForViewer: false,
        selectedAccount: 'monalisa',
        planIdByLogin: {monalisa: '1'},
      },
    })

    expect(screen.getByTestId('csrf-token')).toBeInTheDocument()
    expect(screen.getByTestId('plan-form')).toHaveAttribute(
      'action',
      `/marketplace/${listing.slug}/order/${plan.id}/upgrade`,
    )
    expect(screen.getByTestId('plan-form')).toHaveAttribute('method', 'POST')
  })

  test('directs to upgrade path when plan has been purchased but not installed for selected organization', () => {
    const {listing, plan} = renderComponent({
      planInfoOverrides: {
        installedForViewer: true,
        organizations: [
          {
            displayLogin: 'org-login',
            installedForOrg: false,
            hasExtensibilityAccess: true,
            image: 'www.image.url',
            isEnterpriseOwned: false,
          },
        ],
        selectedAccount: 'org-login',
        planIdByLogin: {'org-login': '1'},
      },
    })

    expect(screen.getByTestId('csrf-token')).toBeInTheDocument()
    expect(screen.getByTestId('plan-form')).toHaveAttribute(
      'action',
      `/marketplace/${listing.slug}/order/${plan.id}/upgrade`,
    )
    expect(screen.getByTestId('plan-form')).toHaveAttribute('method', 'POST')
  })

  test('form can not be submitted when the selected account has purchased and installed plan', () => {
    renderComponent({
      planInfoOverrides: {
        installedForViewer: true,
        currentUser: {
          displayLogin: 'monalisa',
          hasExtensibilityAccess: true,
        },
        selectedAccount: 'monalisa',
        planIdByLogin: {monalisa: '1'},
        plans: [mockPlan({id: '1'})],
      },
    })

    expect(screen.getByRole('button', {name: 'Already installed'})).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Already installed'})).toBeDisabled()
  })

  test('directs to upgrade path when plan purchased but not installed', () => {
    const {listing, plan} = renderComponent({
      listingOverrides: {copilotApp: true},
      planOverrides: {id: '1', directBilling: false, isPaid: false},
      planInfoOverrides: {
        installedForViewer: false,
        selectedAccount: 'monalisa',
        planIdByLogin: {monalisa: '1'},
        plans: [mockPlan({id: '1'})],
      },
    })

    expect(screen.getByTestId('csrf-token')).toBeInTheDocument()
    expect(screen.getByTestId('plan-form')).toHaveAttribute(
      'action',
      `/marketplace/${listing.slug}/order/${plan.id}/upgrade`,
    )
    expect(screen.getByTestId('plan-form')).toHaveAttribute('method', 'POST')
  })

  test('renders pricing information for paid plans', () => {
    renderComponent({
      planInfoOverrides: {isUserBilledMonthly: true},
      planOverrides: {isPaid: true, price: '$5', perUnit: true, unitName: 'seat'},
    })

    expect(screen.getByText('$5')).toBeInTheDocument()
    expect(screen.getByText('/ month')).toBeInTheDocument()
  })
})
