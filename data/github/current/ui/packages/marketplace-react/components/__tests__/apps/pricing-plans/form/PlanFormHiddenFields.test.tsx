import {screen} from '@testing-library/react'
import type {AppListing} from '@github-ui/marketplace-common'
import {mockAppListing} from '@github-ui/marketplace-common/mock-data'
import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'
import {useCSRFToken} from '@github-ui/use-csrf-token'
import {mockPlanInfo, mockPlan} from '../../../../../test-utils/mock-data'
import type {PlanInfo, Plan} from '../../../../../types'
import {renderInPlanForm} from '../../../../../test-utils/RenderPlanForm'

jest.mock('@github-ui/react-core/use-feature-flag')
function mockUseFeatureFlag(flags: {[key: string]: boolean}): void {
  ;(useFeatureFlag as jest.Mock).mockImplementation(flagName => flags[flagName])
}

jest.mock('@github-ui/use-csrf-token')

interface RenderComponentOptions {
  marketplace_free_install?: boolean
  marketplace_purchase_reconciliation?: boolean
  listingOverrides?: Partial<AppListing>
  planInfoOverrides?: Partial<PlanInfo>
  planOverrides?: Partial<Plan>
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

  return {
    listing,
    planInfo,
    plan,
    // By default, the PlanForm component will render the hidden fields
    // so we don't render anything here.
    ...renderInPlanForm(<></>, {planInfo, listing, plan}),
  }
}

describe('PlanFormHiddenFields', () => {
  test('renders hidden input for quantity', () => {
    renderComponent()
    expect(screen.getByTestId('quantity')).toHaveAttribute('value', '1')
  })

  describe('when skipping order review', () => {
    test('renders hidden input for CSRF token', () => {
      const csrfToken = 'test-csrf-token'
      ;(useCSRFToken as jest.Mock).mockReturnValue(csrfToken)

      renderComponent({
        marketplace_free_install: true,
        listingOverrides: {copilotApp: true},
        planOverrides: {directBilling: false, isPaid: false},
      })

      expect(screen.getByTestId('csrf-token')).toHaveAttribute('value', csrfToken)
    })

    describe('when user can sign end user agreement', () => {
      test('renders hidden inputs for user agreement', () => {
        renderComponent({
          marketplace_free_install: true,
          listingOverrides: {copilotApp: true, id: 1},
          planOverrides: {directBilling: false, isPaid: false},
          planInfoOverrides: {
            canSignEndUserAgreement: true,
            endUserAgreement: {id: 2, html: 'test-agreement', version: '1.0'},
          },
        })

        expect(screen.getByTestId('marketplace-listing-id')).toHaveAttribute('value', '1')
        expect(screen.getByTestId('marketplace-agreement-id')).toHaveAttribute('value', '2')
      })
    })

    describe('when user can not sign end user agreement', () => {
      test('does not render hidden inputs for user agreement', () => {
        renderComponent({
          marketplace_free_install: true,
          listingOverrides: {copilotApp: true},
          planOverrides: {directBilling: false, isPaid: false},
          planInfoOverrides: {
            canSignEndUserAgreement: false,
            endUserAgreement: {id: 1, html: 'test-agreement', version: '1.0'},
          },
        })

        expect(screen.queryByTestId('marketplace-listing-id')).not.toBeInTheDocument()
        expect(screen.queryByTestId('marketplace-agreement-id')).not.toBeInTheDocument()
      })
    })
  })

  test('renders hidden input for CSRF token when user can reinstall', () => {
    renderComponent({
      marketplace_free_install: false,
      marketplace_purchase_reconciliation: true,
      planInfoOverrides: {
        installedForViewer: false,
        selectedAccount: 'monalisa',
        planIdByLogin: {monalisa: '1'},
      },
      listingOverrides: {copilotApp: false},
      planOverrides: {directBilling: false, isPaid: false},
    })

    expect(screen.getByTestId('csrf-token')).toBeInTheDocument()
  })

  test('does not render hidden input for CSRF token when not skipping order review and when user can not reinstall', () => {
    renderComponent({
      marketplace_free_install: true,
      marketplace_purchase_reconciliation: true,
      listingOverrides: {copilotApp: false},
      planOverrides: {directBilling: false, isPaid: false},
    })

    expect(screen.queryByTestId('csrf-token')).not.toBeInTheDocument()
  })
})
