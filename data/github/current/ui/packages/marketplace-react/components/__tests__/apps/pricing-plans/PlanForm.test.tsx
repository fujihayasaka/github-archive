import {PlanForm} from '../../../apps/pricing-plans/PlanForm'
import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import {mockAppListing} from '@github-ui/marketplace-common/mock-data'
import {mockPlanInfo, mockPlan} from '../../../../test-utils/mock-data'
import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'
import type {AppListing} from '@github-ui/marketplace-common'
import type {PlanInfo, Plan} from '../../../../types'

jest.mock('@github-ui/react-core/use-feature-flag')
function mockUseFeatureFlag(flags: {[key: string]: boolean}): void {
  ;(useFeatureFlag as jest.Mock).mockImplementation(flagName => flags[flagName])
}

interface RenderComponentOptions {
  marketplace_free_install?: boolean
  marketplace_purchase_reconciliation?: boolean
  listingOverrides?: Partial<AppListing>
  planInfoOverrides?: Partial<PlanInfo>
  planOverrides?: Partial<Plan>
  standaloneButton?: boolean
}

function renderComponent({
  marketplace_free_install = false,
  marketplace_purchase_reconciliation = false,
  listingOverrides = {},
  planInfoOverrides = {},
  planOverrides = {},
}: RenderComponentOptions = {}) {
  mockUseFeatureFlag({
    marketplace_free_install,
    marketplace_purchase_reconciliation,
  })
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

  test('skips order review for free copilot extensions when the marketplace_free_install flag is true', () => {
    renderComponent({
      marketplace_free_install: true,
      listingOverrides: {copilotApp: true},
      planOverrides: {directBilling: false, isPaid: false},
    })

    expect(screen.getByTestId('plan-form')).toHaveAttribute('method', 'POST')
  })

  test('does not skip order review for copilot extensions when the marketplace_free_install flag is false', () => {
    renderComponent({
      marketplace_free_install: false,
      listingOverrides: {copilotApp: true},
      planOverrides: {directBilling: false, isPaid: false},
    })

    expect(screen.getByTestId('plan-form')).toHaveAttribute('method', 'GET')
  })

  test('does not skip order review for paid copilot extensions', () => {
    renderComponent({
      marketplace_free_install: false,
      listingOverrides: {copilotApp: true},
      planOverrides: {directBilling: false, isPaid: true},
    })

    expect(screen.getByTestId('plan-form')).toHaveAttribute('method', 'GET')
  })

  test('skips order review for direct billing plans', () => {
    renderComponent({
      marketplace_free_install: false,
      planOverrides: {directBilling: true},
    })

    expect(screen.getByTestId('plan-form')).toHaveAttribute('method', 'POST')
  })

  test('does not skip order review for other plans', () => {
    renderComponent({
      marketplace_free_install: false,
      planOverrides: {directBilling: false},
    })

    expect(screen.getByTestId('plan-form')).toHaveAttribute('method', 'GET')
  })

  describe('when skipping order review', () => {
    test('sends to upgrade path when updating plan', () => {
      const {listing, plan} = renderComponent({
        marketplace_free_install: true,
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

  describe('when the marketplace_purchase_reconciliation flag is enabled', () => {
    test('directs to upgrade path when plan has been purchased but not installed for selected account', () => {
      const {listing, plan} = renderComponent({
        marketplace_purchase_reconciliation: true,
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
        marketplace_purchase_reconciliation: true,
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
        marketplace_purchase_reconciliation: true,
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

    test('directs to upgrade path when plan purchased but not installed and marketplace_free_install flag enabled', () => {
      const {listing, plan} = renderComponent({
        marketplace_purchase_reconciliation: true,
        marketplace_free_install: true,
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
  })

  describe('when the marketplace_purchase_reconciliation flag is disabled', () => {
    test('does not direct to upgrade path when plan has been purchased but not installed for selected account', () => {
      const {listing, plan} = renderComponent({
        marketplace_purchase_reconciliation: false,
        planInfoOverrides: {
          installedForViewer: false,
          selectedAccount: 'monalisa',
          planIdByLogin: {monalisa: '1'},
          plans: [mockPlan({id: '1'})],
        },
      })

      expect(screen.queryByTestId('csrf-token')).not.toBeInTheDocument()
      expect(screen.getByTestId('plan-form')).toHaveAttribute('action', `/marketplace/${listing.slug}/order/${plan.id}`)
      expect(screen.getByTestId('plan-form')).toHaveAttribute('method', 'GET')
    })
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
