import {CallToAction, callToActionText} from '../../apps/CallToAction'
import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import {mockPlan, mockPlanInfo} from '../../../test-utils/mock-data'
import {mockAppListing} from '@github-ui/marketplace-common/mock-data'
import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'

jest.mock('@github-ui/react-core/use-feature-flag')
function mockUseFeatureFlag(flags: {[key: string]: boolean}): void {
  ;(useFeatureFlag as jest.Mock).mockImplementation(flagName => flags[flagName])
}

function renderComponent({
  freeInstall = false,
  purchaseReconciliation = false,
  viewerHasPurchased = false,
  viewerHasPurchasedForAllOrganizations = false,
  anyOrgsPurchased = false,
  copilotApp = false,
  planInfoOverrides = {},
} = {}) {
  mockUseFeatureFlag({
    marketplace_free_install: freeInstall,
    marketplace_purchase_reconciliation: purchaseReconciliation,
  })

  return render(
    <CallToAction
      planInfo={mockPlanInfo({
        viewerHasPurchased,
        viewerHasPurchasedForAllOrganizations,
        anyOrgsPurchased,
        ...planInfoOverrides,
      })}
      app={mockAppListing({
        copilotApp,
      })}
    />,
  )
}

describe('callToActionText', () => {
  test('returns "Add" when the viewer has purchased the listing', () => {
    const result = callToActionText(
      mockPlanInfo({
        viewerHasPurchased: true,
        anyOrgsPurchased: false,
        plans: [
          mockPlan({
            hasFreeTrial: false,
          }),
        ],
      }),
    )

    expect(result).toBe('Add')
  })

  test('returns "Add" when a viewers org has purchased the listing', () => {
    const result = callToActionText(
      mockPlanInfo({
        viewerHasPurchased: false,
        anyOrgsPurchased: true,
        plans: [
          mockPlan({
            hasFreeTrial: false,
          }),
        ],
      }),
    )

    expect(result).toBe('Add')
  })

  test('returns "Set up a free trial" when there is a free trial available and the listing has not been purchased', () => {
    const result = callToActionText(
      mockPlanInfo({
        viewerHasPurchased: false,
        anyOrgsPurchased: false,
        plans: [
          mockPlan({
            hasFreeTrial: true,
          }),
          mockPlan({
            id: 'plan-2',
            hasFreeTrial: false,
          }),
        ],
      }),
    )

    expect(result).toBe('Set up a free trial')
  })

  test('returns "Add" when there is no free trial available and the listing has not been purchased', () => {
    const result = callToActionText(
      mockPlanInfo({
        viewerHasPurchased: false,
        anyOrgsPurchased: false,
        plans: [
          mockPlan({
            hasFreeTrial: false,
          }),
          mockPlan({
            id: 'plan-2',
            hasFreeTrial: false,
          }),
        ],
      }),
    )

    expect(result).toBe('Add')
  })
})

describe('CallToAction', () => {
  describe('When the viewer has purchased the app for themselves and all organizations', () => {
    test('Hides the button', () => {
      const {container} = renderComponent({viewerHasPurchased: true, viewerHasPurchasedForAllOrganizations: true})

      expect(container).toBeEmptyDOMElement()
    })
  })

  describe('When the app is a Copilot app', () => {
    describe('When the marketplace_free_install flag is enabled', () => {
      test('Renders the dialog button if the user belongs to at least one organization', () => {
        // single free plan with org
        renderComponent({
          freeInstall: true,
          copilotApp: true,
          planInfoOverrides: {
            plans: [mockPlan({name: 'Free', isPaid: false, hasFreeTrial: false})],
          },
        })

        expect(screen.getByTestId('dialog-button')).toBeInTheDocument()
      })

      test('Renders the dialog button if there are multiple plans', () => {
        renderComponent({
          freeInstall: true,
          copilotApp: true,
          anyOrgsPurchased: false,
          planInfoOverrides: {
            plans: [mockPlan({name: 'Free', isPaid: false}), mockPlan({name: 'Free, also', isPaid: false})],
            organizations: [],
          },
        })

        expect(screen.getByTestId('dialog-button')).toBeInTheDocument()
      })

      test('Renders the dialog button if there is one paid plan', () => {
        renderComponent({
          freeInstall: true,
          copilotApp: true,
          anyOrgsPurchased: false,
          planInfoOverrides: {
            plans: [mockPlan({name: 'Paid', isPaid: true})],
            organizations: [],
          },
        })

        expect(screen.getByTestId('dialog-button')).toBeInTheDocument()
      })

      test('Clicking dialog button opens the dialog', async () => {
        const {user} = renderComponent({
          freeInstall: true,
          copilotApp: true,
          anyOrgsPurchased: false,
        })

        expect(screen.queryByText('Configure your installation')).not.toBeInTheDocument()
        await user.click(screen.getByTestId('dialog-button'))
        expect(screen.getByText('Configure your installation')).toBeInTheDocument()
      })

      test('Renders direct install button if no organizations, no paid plans, and only one plan option', () => {
        renderComponent({
          freeInstall: true,
          copilotApp: true,
          anyOrgsPurchased: false,
          planInfoOverrides: {
            plans: [mockPlan({name: 'Free', isPaid: false})],
            organizations: [],
          },
        })

        expect(screen.getByTestId('direct-install-button')).toBeInTheDocument()
      })
    })

    describe('When the marketplace_free_install flag is disabled', () => {
      test('Renders the scroll button', () => {
        renderComponent({freeInstall: false, copilotApp: true})

        expect(screen.getByTestId('setup-button')).toHaveAttribute('href', '#pricing-and-setup')
        expect(screen.getByTestId('setup-button')).toHaveTextContent('Set up a free trial')
      })
    })
  })

  describe('When the app is not a Copilot app', () => {
    describe('When the marketplace_free_install flag is enabled', () => {
      test('Renders the scroll button', () => {
        renderComponent({freeInstall: true})

        expect(screen.getByTestId('setup-button')).toHaveAttribute('href', '#pricing-and-setup')
        expect(screen.getByTestId('setup-button')).toHaveTextContent('Set up a free trial')
      })
    })
  })

  describe('When the viewer has purchased the app for themselves but not all organizations', () => {
    test('Renders the call to action', () => {
      const {container} = renderComponent({viewerHasPurchased: true, viewerHasPurchasedForAllOrganizations: false})

      expect(container).not.toBeEmptyDOMElement()
    })
  })

  describe('When the viewer has not purchased the app for themselves but has for all orgs', () => {
    test('Renders the link call to action', () => {
      renderComponent({
        anyOrgsPurchased: true,
        viewerHasPurchasedForAllOrganizations: true,
        viewerHasPurchased: false,
      })

      expect(screen.getByRole('link', {name: 'Add'})).toBeInTheDocument()
    })
  })

  describe('When the viewer has not purchased the app for themselves or any orgs', () => {
    test('Renders the link call to action', () => {
      renderComponent({
        anyOrgsPurchased: false,
        viewerHasPurchased: false,
        viewerHasPurchasedForAllOrganizations: false,
      })

      expect(screen.getByRole('link', {name: 'Set up a free trial'})).toBeInTheDocument()
    })
  })

  describe('When the marketplace_purchase_reconciliation flag is enabled', () => {
    describe('When the viewer has purchased the app for themselves and all orgs but has not installed it', () => {
      test('Renders the link call to action', () => {
        renderComponent({
          purchaseReconciliation: true,
          viewerHasPurchased: true,
          viewerHasPurchasedForAllOrganizations: true,
          anyOrgsPurchased: true,
          planInfoOverrides: {installedForViewer: false},
        })

        expect(screen.getByRole('link', {name: 'Add'})).toBeInTheDocument()
      })
    })
  })

  describe('When the marketplace_purchase_reconciliation flag is disabled', () => {
    describe('When the viewer has purchased the app for themselves and all orgs but has not installed it', () => {
      test('Does not render the call to action', () => {
        const {container} = renderComponent({
          viewerHasPurchased: true,
          viewerHasPurchasedForAllOrganizations: true,
          anyOrgsPurchased: true,
          planInfoOverrides: {installedForViewer: false},
        })

        expect(container).toBeEmptyDOMElement()
      })
    })
  })
})
