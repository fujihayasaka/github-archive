import {CopilotLicenseType, CopilotPlan} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {render, setupUserEvent} from '@github-ui/react-core/test-utils'
import {EntitledService} from '@github-ui/workbench/utilities/workbench-store-reducer'
import {screen} from '@testing-library/react'

import {getChatQuotaApproaching, setChatQuotaApproaching} from '../../../workbench/utilities/copilot-chat'
import {WorkbenchBanner} from '../WorkbenchBanner'

jest.mock('../../../workbench/utilities/copilot-chat', () => ({
  getChatQuotaApproaching: jest.fn(() => null),
  setChatQuotaApproaching: jest.fn(),
  removeChatQuotaApproaching: jest.fn(),
}))

const mockUseWorkbenchStore = jest.fn().mockReturnValue({
  readOnly: false,
  status: {},
  entitlement: {
    [EntitledService.COPILOT]: {
      licenseType: CopilotLicenseType.LicensedLimited,
      plan: CopilotPlan.IndividualFree,
      quotas: {
        limits: {
          chat: 0,
          premiumInteractions: 0,
        },
        remaining: {
          chat: 0,
          chatPercentage: 0,
          premiumInteractions: 0,
          premiumInteractionsPercentage: 0,
        },
        resetDate: '',
        overagesEnabled: false,
      },
    },
  },
})

jest.mock('../../../workbench/contexts/WorkbenchStoreContext', () => ({
  useWorkbenchStore: () => mockUseWorkbenchStore(),
}))

jest.mock('@github-ui/hydro-analytics', () => ({
  sendEvent: jest.fn(),
}))

jest.mock('@github-ui/copilot-chat/utils/copilot-feature-flags', () => ({
  copilotFeatureFlags: {workbenchUserLimits: true},
}))

const userEvent = setupUserEvent()

describe('WorkbenchBanner', () => {
  const mockGetChatQuotaApproaching = getChatQuotaApproaching as jest.Mock
  const mockSetChatQuotaApproaching = setChatQuotaApproaching as jest.Mock

  beforeEach(() => {
    jest.clearAllMocks()
    mockGetChatQuotaApproaching.mockReturnValue(null)
  })

  describe('Copilot Free plan', () => {
    test('renders correctly for Free plan, quota approaching', () => {
      mockUseWorkbenchStore.mockReturnValue({
        readOnly: false,
        status: {},
        entitlement: {
          [EntitledService.COPILOT]: {
            licenseType: CopilotLicenseType.LicensedLimited,
            plan: CopilotPlan.IndividualFree,
            quotas: {
              limits: {
                chat: 100,
                premiumInteractions: 50,
              },
              remaining: {
                chat: 50,
                chatPercentage: 50,
                premiumInteractions: 0,
                premiumInteractionsPercentage: 0,
              },
              resetDate: '2025-05-15',
              overagesEnabled: false,
            },
          },
        },
      })
      mockGetChatQuotaApproaching.mockReturnValue(true)

      render(<WorkbenchBanner />)

      // Assert
      const banner = screen.getByRole('region', {name: /information/i})
      expect(banner).toBeInTheDocument()

      // Check banner content
      expect(screen.getByText(/You have used 50% of your/)).toBeInTheDocument()
      expect(screen.getByRole('link', {name: /premium requests/i})).toBeInTheDocument()
      expect(screen.getByText(/this month./)).toBeInTheDocument()

      // Check banner variant
      expect(banner).toHaveAttribute('data-variant', 'info')

      // Check primary action (Upgrade)
      const upgradeButton = screen.getAllByRole('link', {name: 'Upgrade'})
      expect(upgradeButton[0]).toBeInTheDocument()
      expect(upgradeButton[0]).toHaveAttribute(
        'href',
        'https://github.com/features/copilot/plans?cft=copilot_li.features_copilot',
      )

      // Check dismiss button (should be present as dismissible is true for this state)
      expect(screen.getByRole('button', {name: /dismiss/i})).toBeInTheDocument()
    })

    test('renders correctly for Free plan, quota exceeded', () => {
      mockUseWorkbenchStore.mockReturnValue({
        readOnly: false,
        status: {},
        entitlement: {
          [EntitledService.COPILOT]: {
            licenseType: CopilotLicenseType.LicensedLimited,
            plan: CopilotPlan.IndividualFree,
            quotas: {
              limits: {
                chat: 100,
                premiumInteractions: 50,
              },
              remaining: {
                chat: 0,
                chatPercentage: 0,
                premiumInteractions: 0,
                premiumInteractionsPercentage: 0,
              },
              resetDate: '2025-05-15',
              overagesEnabled: false,
            },
          },
        },
      })
      mockGetChatQuotaApproaching.mockReturnValue(true)

      render(<WorkbenchBanner />)

      // Assert
      const banner = screen.getByRole('region', {name: /recommendation/i})
      expect(banner).toBeInTheDocument()

      // Check banner content
      expect(screen.getByText(/You have reached your free plan limit/)).toBeInTheDocument()
      expect(screen.getByText(/Limit resets on May 15, 2025./)).toBeInTheDocument()

      // Check banner variant
      expect(banner).toHaveAttribute('data-variant', 'upsell')

      // Check primary action (Upgrade)
      const upgradeButton = screen.getAllByRole('link', {name: 'Upgrade'})
      expect(upgradeButton[0]).toBeInTheDocument()
      expect(upgradeButton[0]).toHaveAttribute(
        'href',
        'https://github.com/features/copilot/plans?cft=copilot_li.features_copilot',
      )

      // Check dismiss button (should not be present)
      expect(screen.queryByRole('button', {name: /dismiss/i})).not.toBeInTheDocument()
    })
  })

  describe('Copilot Pro plan', () => {
    test('renders correctly for Pro plan, quota approaching, no overages', () => {
      mockUseWorkbenchStore.mockReturnValue({
        readOnly: false,
        status: {},
        entitlement: {
          [EntitledService.COPILOT]: {
            licenseType: CopilotLicenseType.LicensedLimited,
            plan: CopilotPlan.IndividualPro,
            quotas: {
              limits: {
                chat: 100,
                premiumInteractions: 50,
              },
              remaining: {
                chat: 100,
                chatPercentage: 100,
                premiumInteractions: 1,
                premiumInteractionsPercentage: 1,
              },
              resetDate: '2025-05-15',
              overagesEnabled: false,
            },
          },
        },
      })
      mockGetChatQuotaApproaching.mockReturnValue(true)

      render(<WorkbenchBanner />)

      // Assert
      const banner = screen.getByRole('region', {name: /information/i})
      expect(banner).toBeInTheDocument()

      // Check banner content
      expect(screen.getByText(/You have used 80% of your/)).toBeInTheDocument()
      expect(screen.getByRole('link', {name: /premium requests/i})).toBeInTheDocument()
      expect(screen.getByText(/this month./)).toBeInTheDocument()

      // Check banner variant
      expect(banner).toHaveAttribute('data-variant', 'info')

      // Check primary action (Upgrade)
      const upgradeButton = screen.getAllByRole('link', {name: 'Upgrade'})
      expect(upgradeButton[0]).toBeInTheDocument()
      expect(upgradeButton[0]).toHaveAttribute(
        'href',
        'https://github.com/features/copilot/plans?cft=copilot_li.features_copilot',
      )

      // Check dismiss button (should be present)
      expect(screen.getByRole('button', {name: /dismiss/i})).toBeInTheDocument()
    })

    test('renders correctly for Pro plan, quota exceeded, no overages', () => {
      mockUseWorkbenchStore.mockReturnValue({
        readOnly: false,
        status: {},
        entitlement: {
          [EntitledService.COPILOT]: {
            licenseType: CopilotLicenseType.LicensedLimited,
            plan: CopilotPlan.IndividualPro,
            quotas: {
              limits: {
                chat: 100,
                premiumInteractions: 50,
              },
              remaining: {
                chat: 0,
                chatPercentage: 0,
                premiumInteractions: 0,
                premiumInteractionsPercentage: 0,
              },
              resetDate: '2025-05-15',
              overagesEnabled: false,
            },
          },
        },
      })

      mockGetChatQuotaApproaching.mockReturnValue(true)

      render(<WorkbenchBanner />)

      // Assert
      const banner = screen.getByRole('region', {name: /recommendation/i})
      expect(banner).toBeInTheDocument()

      // Check banner content
      expect(screen.getByText(/You have reached your monthly limit/)).toBeInTheDocument()
      expect(screen.getByRole('link', {name: /premium requests/i})).toBeInTheDocument()
      expect(screen.getByText(/Limit resets on May 15, 2025./)).toBeInTheDocument()

      // Check banner variant
      expect(banner).toHaveAttribute('data-variant', 'upsell')

      // Check primary action (Upgrade)
      const upgradeButton = screen.getAllByRole('link', {name: 'Upgrade'})
      expect(upgradeButton[0]).toBeInTheDocument()
      expect(upgradeButton[0]).toHaveAttribute(
        'href',
        'https://github.com/features/copilot/plans?cft=copilot_li.features_copilot',
      )

      // Check secondary action (Enable additional requests)
      const enableRequestsButton = screen.getAllByRole('link', {name: 'Enable additional requests'})
      expect(enableRequestsButton[0]).toBeInTheDocument()
      expect(enableRequestsButton[0]).toHaveAttribute('href', 'https://github.com/settings/billing/budgets/new')

      // Check dismiss button (should not be present)
      expect(screen.queryByRole('button', {name: /dismiss/i})).not.toBeInTheDocument()
    })

    test('renders correctly for Pro plan, quota exceeded, with overages', () => {
      mockUseWorkbenchStore.mockReturnValue({
        readOnly: false,
        status: {},
        entitlement: {
          [EntitledService.COPILOT]: {
            licenseType: CopilotLicenseType.LicensedLimited,
            plan: CopilotPlan.IndividualPro,
            quotas: {
              limits: {
                chat: 100,
                premiumInteractions: 50,
              },
              remaining: {
                chat: 0,
                chatPercentage: 0,
                premiumInteractions: 0,
                premiumInteractionsPercentage: 0,
              },
              resetDate: '2025-05-15',
              overagesEnabled: true,
            },
          },
        },
      })
      mockGetChatQuotaApproaching.mockReturnValue(true)

      render(<WorkbenchBanner />)

      // Assert
      const banner = screen.getByRole('region', {name: /information/i})
      expect(banner).toBeInTheDocument()

      // Check banner content
      expect(screen.getByText(/You have used all/)).toBeInTheDocument()
      expect(screen.getByRole('link', {name: /premium requests/i})).toBeInTheDocument()
      expect(screen.getByText(/this month./)).toBeInTheDocument()

      // Check banner variant
      expect(banner).toHaveAttribute('data-variant', 'info')

      // Check primary action (Upgrade)
      const upgradeButton = screen.getAllByRole('link', {name: 'Manage billing'})
      expect(upgradeButton[0]).toBeInTheDocument()
      expect(upgradeButton[0]).toHaveAttribute('href', 'https://github.com/settings/billing/budgets/new')

      // Check dismiss button (should be present)
      expect(screen.getByRole('button', {name: /dismiss/i})).toBeInTheDocument()
    })
  })

  describe('Copilot Pro+ plan', () => {
    test('renders correctly for Pro+ plan, quota approaching, no overages', () => {
      mockUseWorkbenchStore.mockReturnValue({
        readOnly: false,
        status: {},
        entitlement: {
          [EntitledService.COPILOT]: {
            licenseType: CopilotLicenseType.LicensedFull,
            plan: CopilotPlan.IndividualProPlus,
            quotas: {
              limits: {
                chat: 100,
                premiumInteractions: 50,
              },
              remaining: {
                chat: 100,
                chatPercentage: 1,
                premiumInteractions: 1,
                premiumInteractionsPercentage: 1,
              },
              resetDate: '2025-05-15',
              overagesEnabled: false,
            },
          },
        },
      })

      mockGetChatQuotaApproaching.mockReturnValue(true)

      render(<WorkbenchBanner />)

      // Assert
      const banner = screen.getByRole('region', {name: /information/i})
      expect(banner).toBeInTheDocument()

      // Check banner content
      expect(screen.getByText(/You have used 80% of your/)).toBeInTheDocument()
      expect(screen.getByRole('link', {name: /premium requests/i})).toBeInTheDocument()
      expect(screen.getByText(/this month./)).toBeInTheDocument()

      // Check banner variant
      expect(banner).toHaveAttribute('data-variant', 'info')

      // Check primary action (Enable additional requests)
      const enableRequestsButton = screen.getAllByRole('link', {name: 'Enable additional requests'})
      expect(enableRequestsButton[0]).toBeInTheDocument()
      expect(enableRequestsButton[0]).toHaveAttribute('href', 'https://github.com/settings/billing/budgets/new')

      // Check dismiss button (should be present)
      expect(screen.getByRole('button', {name: /dismiss/i})).toBeInTheDocument()
    })

    test('renders correctly for Pro+ plan, quota exceeded, no overages', () => {
      mockUseWorkbenchStore.mockReturnValue({
        readOnly: false,
        status: {},
        entitlement: {
          [EntitledService.COPILOT]: {
            licenseType: CopilotLicenseType.LicensedFull,
            plan: CopilotPlan.IndividualProPlus,
            quotas: {
              limits: {
                chat: 100,
                premiumInteractions: 50,
              },
              remaining: {
                chat: 0,
                chatPercentage: 0,
                premiumInteractions: 0,
                premiumInteractionsPercentage: 0,
              },
              resetDate: '2025-05-15',
              overagesEnabled: false,
            },
          },
        },
      })

      mockGetChatQuotaApproaching.mockReturnValue(true)

      render(<WorkbenchBanner />)

      // Assert
      const banner = screen.getByRole('region', {name: /recommendation/i})
      expect(banner).toBeInTheDocument()

      // Check banner content
      expect(screen.getByText(/You have reached your monthly limit/)).toBeInTheDocument()
      expect(screen.getByRole('link', {name: /premium requests/i})).toBeInTheDocument()
      expect(screen.getByText(/Limit resets on May 15, 2025./)).toBeInTheDocument()

      // Check banner variant
      expect(banner).toHaveAttribute('data-variant', 'upsell')

      // Check primary action (Enable additional requests)
      const enableRequestsButton = screen.getAllByRole('link', {name: 'Enable additional requests'})
      expect(enableRequestsButton[0]).toBeInTheDocument()
      expect(enableRequestsButton[0]).toHaveAttribute('href', 'https://github.com/settings/billing/budgets/new')

      // Check dismiss button (should not be present)
      expect(screen.queryByRole('button', {name: /dismiss/i})).not.toBeInTheDocument()
    })

    test('renders correctly for Pro+ plan, quota exceeded, with overages', () => {
      mockUseWorkbenchStore.mockReturnValue({
        readOnly: false,
        status: {},
        entitlement: {
          [EntitledService.COPILOT]: {
            licenseType: CopilotLicenseType.LicensedFull,
            plan: CopilotPlan.IndividualProPlus,
            quotas: {
              limits: {
                chat: 100,
                premiumInteractions: 50,
              },
              remaining: {
                chat: 0,
                chatPercentage: 0,
                premiumInteractions: 0,
                premiumInteractionsPercentage: 0,
              },
              resetDate: '2025-05-15',
              overagesEnabled: true,
            },
          },
        },
      })

      mockGetChatQuotaApproaching.mockReturnValue(true)

      render(<WorkbenchBanner />)

      // Assert
      const banner = screen.getByRole('region', {name: /information/i})
      expect(banner).toBeInTheDocument()

      // Check banner content
      expect(screen.getByText(/You have used all/)).toBeInTheDocument()
      expect(screen.getByRole('link', {name: /premium requests/i})).toBeInTheDocument()
      expect(screen.getByText(/this month./)).toBeInTheDocument()

      // Check banner variant
      expect(banner).toHaveAttribute('data-variant', 'info')

      // Check primary action (Upgrade)
      const upgradeButton = screen.getAllByRole('link', {name: 'Manage billing'})
      expect(upgradeButton[0]).toBeInTheDocument()
      expect(upgradeButton[0]).toHaveAttribute('href', 'https://github.com/settings/billing/budgets/new')

      // Check dismiss button (should be present)
      expect(screen.getByRole('button', {name: /dismiss/i})).toBeInTheDocument()
    })
  })

  describe('Copilot Business plan', () => {
    test('renders correctly for Business plan admin user, quota exceeded, no overages', () => {
      mockUseWorkbenchStore.mockReturnValue({
        readOnly: false,
        status: {},
        entitlement: {
          [EntitledService.COPILOT]: {
            licenseType: CopilotLicenseType.LicensedFull,
            plan: CopilotPlan.Business,
            quotas: {
              limits: {
                chat: 100,
                premiumInteractions: 50,
              },
              remaining: {
                chat: 0,
                chatPercentage: 0,
                premiumInteractions: 0,
                premiumInteractionsPercentage: 0,
              },
              resetDate: '2025-05-15',
              overagesEnabled: false,
            },
          },
          [EntitledService.USER_STATUS]: {
            admin: true,
            type: 'Organization',
            billingUrl: 'https://github.com/organizations/test-org/settings/billing',
          },
        },
      })

      render(<WorkbenchBanner />)

      // Assert
      const banner = screen.getByRole('region', {name: /recommendation/i})
      expect(banner).toBeInTheDocument()

      // Check banner content
      expect(screen.getByText(/You have reached your monthly limit for/)).toBeInTheDocument()
      expect(screen.getByRole('link', {name: /premium requests/i})).toBeInTheDocument()

      // Check primary action uses organization billing URL
      const upgradeButton = screen.getAllByRole('link', {name: 'Upgrade'})
      expect(upgradeButton[0]).toBeInTheDocument()
      expect(upgradeButton[0]).toHaveAttribute('href', 'https://github.com/organizations/test-org/settings/billing')

      // Check secondary action uses organization billing URL
      const enableRequestsButton = screen.getAllByRole('link', {name: 'Enable additional requests'})
      expect(enableRequestsButton[0]).toBeInTheDocument()
      expect(enableRequestsButton[0]).toHaveAttribute(
        'href',
        'https://github.com/organizations/test-org/settings/billing',
      )
    })

    test('renders correctly for Business plan non-admin user, quota exceeded, no overages', () => {
      mockUseWorkbenchStore.mockReturnValue({
        readOnly: false,
        status: {},
        entitlement: {
          [EntitledService.COPILOT]: {
            licenseType: CopilotLicenseType.LicensedFull,
            plan: CopilotPlan.Business,
            quotas: {
              limits: {
                chat: 100,
                premiumInteractions: 50,
              },
              remaining: {
                chat: 0,
                chatPercentage: 0,
                premiumInteractions: 0,
                premiumInteractionsPercentage: 0,
              },
              resetDate: '2025-05-15',
              overagesEnabled: false,
            },
          },
          [EntitledService.USER_STATUS]: {
            admin: false,
            type: 'Organization',
            billingUrl: 'https://github.com/organizations/test-org/settings/billing',
          },
        },
      })

      render(<WorkbenchBanner />)

      // Assert
      const banner = screen.getByRole('region', {name: /recommendation/i})
      expect(banner).toBeInTheDocument()

      // Check banner content
      expect(screen.getByText(/You have reached your monthly limit for/)).toBeInTheDocument()
      expect(screen.getByRole('link', {name: /premium requests/i})).toBeInTheDocument()

      // Check that no action buttons are present for non-admin organization users
      expect(screen.queryByRole('link', {name: 'Upgrade'})).not.toBeInTheDocument()
      expect(screen.queryByRole('link', {name: 'Enable additional requests'})).not.toBeInTheDocument()
    })

    test('does not render for Business plan, quota exceeded, with overages', () => {
      mockUseWorkbenchStore.mockReturnValue({
        readOnly: false,
        status: {},
        entitlement: {
          [EntitledService.COPILOT]: {
            licenseType: CopilotLicenseType.LicensedFull,
            plan: CopilotPlan.Business,
            quotas: {
              limits: {
                chat: 100,
                premiumInteractions: 50,
              },
              remaining: {
                chat: 0,
                chatPercentage: 0,
                premiumInteractions: 0,
                premiumInteractionsPercentage: 0,
              },
              resetDate: '2025-05-15',
              overagesEnabled: true,
            },
          },
        },
      })

      render(<WorkbenchBanner />)

      // Assert: Banner should not be in the document
      expect(screen.queryByRole('status')).not.toBeInTheDocument()
    })

    test('renders correctly for Business plan admin user, quota approaching, no overages', () => {
      mockUseWorkbenchStore.mockReturnValue({
        readOnly: false,
        status: {},
        entitlement: {
          [EntitledService.COPILOT]: {
            licenseType: CopilotLicenseType.LicensedFull,
            plan: CopilotPlan.Business,
            quotas: {
              limits: {
                chat: 100,
                premiumInteractions: 50,
              },
              remaining: {
                chat: 1,
                chatPercentage: 1,
                premiumInteractions: 1,
                premiumInteractionsPercentage: 1,
              },
              resetDate: '2025-05-15',
              overagesEnabled: false,
            },
          },
          [EntitledService.USER_STATUS]: {
            admin: true,
            type: 'Organization',
            billingUrl: 'https://github.com/organizations/test-org/settings/billing',
          },
        },
      })

      render(<WorkbenchBanner />)

      // Assert
      const banner = screen.getByRole('region', {name: /information/i})
      expect(banner).toBeInTheDocument()

      // Check primary action uses organization billing URL
      const upgradeButton = screen.getAllByRole('link', {name: 'Upgrade'})
      expect(upgradeButton[0]).toBeInTheDocument()
      expect(upgradeButton[0]).toHaveAttribute('href', 'https://github.com/organizations/test-org/settings/billing')

      // Check secondary action uses organization billing URL
      const enableRequestsButton = screen.getAllByRole('link', {name: 'Enable additional requests'})
      expect(enableRequestsButton[0]).toBeInTheDocument()
      expect(enableRequestsButton[0]).toHaveAttribute(
        'href',
        'https://github.com/organizations/test-org/settings/billing',
      )
    })

    test('renders correctly for Business plan non-admin user, quota approaching, no overages', () => {
      mockUseWorkbenchStore.mockReturnValue({
        readOnly: false,
        status: {},
        entitlement: {
          [EntitledService.COPILOT]: {
            licenseType: CopilotLicenseType.LicensedFull,
            plan: CopilotPlan.Business,
            quotas: {
              limits: {
                chat: 100,
                premiumInteractions: 50,
              },
              remaining: {
                chat: 1,
                chatPercentage: 1,
                premiumInteractions: 1,
                premiumInteractionsPercentage: 1,
              },
              resetDate: '2025-05-15',
              overagesEnabled: false,
            },
          },
          [EntitledService.USER_STATUS]: {
            admin: false,
            type: 'Organization',
            billingUrl: 'https://github.com/organizations/test-org/settings/billing',
          },
        },
      })

      render(<WorkbenchBanner />)

      // Assert
      const banner = screen.getByRole('region', {name: /information/i})
      expect(banner).toBeInTheDocument()

      // Check that no action buttons are present for non-admin organization users
      expect(screen.queryByRole('link', {name: 'Upgrade'})).not.toBeInTheDocument()
      expect(screen.queryByRole('link', {name: 'Enable additional requests'})).not.toBeInTheDocument()
    })
  })

  describe('Copilot Enterprise plan', () => {
    test('renders correctly for Enterprise plan admin user, quota exceeded, no overages', () => {
      mockUseWorkbenchStore.mockReturnValue({
        readOnly: false,
        status: {},
        entitlement: {
          [EntitledService.COPILOT]: {
            licenseType: CopilotLicenseType.LicensedFull,
            plan: CopilotPlan.Enterprise,
            quotas: {
              limits: {
                chat: 100,
                premiumInteractions: 50,
              },
              remaining: {
                chat: 0,
                chatPercentage: 0,
                premiumInteractions: 0,
                premiumInteractionsPercentage: 0,
              },
              resetDate: '2025-05-15',
              overagesEnabled: false,
            },
          },
          [EntitledService.USER_STATUS]: {
            admin: true,
            type: 'Organization',
            billingUrl: 'https://github.com/organizations/test-org/settings/billing',
          },
        },
      })

      render(<WorkbenchBanner />)

      // Assert
      const banner = screen.getByRole('region', {name: /recommendation/i})
      expect(banner).toBeInTheDocument()

      // Check banner content
      expect(screen.getByText(/You have reached your monthly limit for/)).toBeInTheDocument()
      expect(screen.getByRole('link', {name: /premium requests/i})).toBeInTheDocument()

      // Check primary action uses organization billing URL
      const enableRequestsButton = screen.getAllByRole('link', {name: 'Enable additional requests'})
      expect(enableRequestsButton[0]).toBeInTheDocument()
      expect(enableRequestsButton[0]).toHaveAttribute(
        'href',
        'https://github.com/organizations/test-org/settings/billing',
      )
    })

    test('renders correctly for Enterprise plan non-admin user, quota exceeded, no overages', () => {
      mockUseWorkbenchStore.mockReturnValue({
        readOnly: false,
        status: {},
        entitlement: {
          [EntitledService.COPILOT]: {
            licenseType: CopilotLicenseType.LicensedFull,
            plan: CopilotPlan.Enterprise,
            quotas: {
              limits: {
                chat: 100,
                premiumInteractions: 50,
              },
              remaining: {
                chat: 0,
                chatPercentage: 0,
                premiumInteractions: 0,
                premiumInteractionsPercentage: 0,
              },
              resetDate: '2025-05-15',
              overagesEnabled: false,
            },
          },
          [EntitledService.USER_STATUS]: {
            admin: false,
            type: 'Organization',
            billingUrl: 'https://github.com/organizations/test-org/settings/billing',
          },
        },
      })

      render(<WorkbenchBanner />)

      // Assert
      const banner = screen.getByRole('region', {name: /recommendation/i})
      expect(banner).toBeInTheDocument()

      // Check banner content
      expect(screen.getByText(/You have reached your monthly limit for/)).toBeInTheDocument()
      expect(screen.getByRole('link', {name: /premium requests/i})).toBeInTheDocument()

      // Check that no action buttons are present for non-admin organization users
      expect(screen.queryByRole('link', {name: 'Enable additional requests'})).not.toBeInTheDocument()
    })

    test('renders correctly for Enterprise plan admin user, quota approaching, no overages', () => {
      mockUseWorkbenchStore.mockReturnValue({
        readOnly: false,
        status: {},
        entitlement: {
          [EntitledService.COPILOT]: {
            licenseType: CopilotLicenseType.LicensedFull,
            plan: CopilotPlan.Enterprise,
            quotas: {
              limits: {
                chat: 100,
                premiumInteractions: 50,
              },
              remaining: {
                chat: 1,
                chatPercentage: 1,
                premiumInteractions: 1,
                premiumInteractionsPercentage: 1,
              },
              resetDate: '2025-05-15',
              overagesEnabled: false,
            },
          },
          [EntitledService.USER_STATUS]: {
            admin: true,
            type: 'Organization',
            billingUrl: 'https://github.com/organizations/test-org/settings/billing',
          },
        },
      })

      render(<WorkbenchBanner />)

      // Assert
      const banner = screen.getByRole('region', {name: /information/i})
      expect(banner).toBeInTheDocument()

      // Check primary action uses organization billing URL
      const enableRequestsButton = screen.getAllByRole('link', {name: 'Enable additional requests'})
      expect(enableRequestsButton[0]).toBeInTheDocument()
      expect(enableRequestsButton[0]).toHaveAttribute(
        'href',
        'https://github.com/organizations/test-org/settings/billing',
      )
    })

    test('renders correctly for Enterprise plan non-admin user, quota approaching, no overages', () => {
      mockUseWorkbenchStore.mockReturnValue({
        readOnly: false,
        status: {},
        entitlement: {
          [EntitledService.COPILOT]: {
            licenseType: CopilotLicenseType.LicensedFull,
            plan: CopilotPlan.Enterprise,
            quotas: {
              limits: {
                chat: 100,
                premiumInteractions: 50,
              },
              remaining: {
                chat: 1,
                chatPercentage: 1,
                premiumInteractions: 1,
                premiumInteractionsPercentage: 1,
              },
              resetDate: '2025-05-15',
              overagesEnabled: false,
            },
          },
          [EntitledService.USER_STATUS]: {
            admin: false,
            type: 'Organization',
            billingUrl: 'https://github.com/organizations/test-org/settings/billing',
          },
        },
      })

      render(<WorkbenchBanner />)

      // Assert
      const banner = screen.getByRole('region', {name: /information/i})
      expect(banner).toBeInTheDocument()

      // Check that no action buttons are present for non-admin organization users
      expect(screen.getByText(/Ask your admin/)).toBeInTheDocument()
      expect(screen.queryByRole('link', {name: 'Enable additional requests'})).not.toBeInTheDocument()
    })
  })

  describe('Does not render when plans have quotas', () => {
    test('does not render for Copilot Free plan', () => {
      mockUseWorkbenchStore.mockReturnValue({
        readOnly: false,
        status: {},
        entitlement: {
          [EntitledService.COPILOT]: {
            licenseType: CopilotLicenseType.LicensedLimited,
            plan: CopilotPlan.IndividualFree,
            quotas: {
              limits: {
                chat: 100,
                premiumInteractions: 50,
              },
              remaining: {
                chat: 100,
                chatPercentage: 100,
                premiumInteractions: 0,
                premiumInteractionsPercentage: 0,
              },
              resetDate: '2025-05-15',
              overagesEnabled: false,
            },
          },
        },
      })

      render(<WorkbenchBanner />)

      expect(screen.queryByRole('region')).not.toBeInTheDocument()
    })

    test('does not render for Copilot Pro plan', () => {
      mockUseWorkbenchStore.mockReturnValue({
        readOnly: false,
        status: {},
        entitlement: {
          [EntitledService.COPILOT]: {
            licenseType: CopilotLicenseType.LicensedFull,
            plan: CopilotPlan.IndividualPro,
            quotas: {
              limits: {
                chat: 100,
                premiumInteractions: 50,
              },
              remaining: {
                chat: 100,
                chatPercentage: 100,
                premiumInteractions: 100,
                premiumInteractionsPercentage: 100,
              },
              resetDate: '2025-05-15',
              overagesEnabled: false,
            },
          },
        },
      })

      render(<WorkbenchBanner />)

      expect(screen.queryByRole('region')).not.toBeInTheDocument()
    })

    test('does not render for Copilot Pro+ plan', () => {
      mockUseWorkbenchStore.mockReturnValue({
        readOnly: false,
        status: {},
        entitlement: {
          [EntitledService.COPILOT]: {
            licenseType: CopilotLicenseType.LicensedFull,
            plan: CopilotPlan.IndividualProPlus,
            quotas: {
              limits: {
                chat: 100,
                premiumInteractions: 50,
              },
              remaining: {
                chat: 100,
                chatPercentage: 100,
                premiumInteractions: 100,
                premiumInteractionsPercentage: 100,
              },
              resetDate: '2025-05-15',
              overagesEnabled: false,
            },
          },
        },
      })

      render(<WorkbenchBanner />)

      expect(screen.queryByRole('region')).not.toBeInTheDocument()
    })

    test('does not render for Copilot Business plan', () => {
      mockUseWorkbenchStore.mockReturnValue({
        readOnly: false,
        status: {},
        entitlement: {
          [EntitledService.COPILOT]: {
            licenseType: CopilotLicenseType.LicensedLimited,
            plan: CopilotPlan.Business,
            quotas: {
              limits: {
                chat: 100,
                premiumInteractions: 50,
              },
              remaining: {
                chat: 100,
                chatPercentage: 100,
                premiumInteractions: 100,
                premiumInteractionsPercentage: 100,
              },
              resetDate: '2025-05-15',
              overagesEnabled: false,
            },
          },
        },
      })

      render(<WorkbenchBanner />)

      expect(screen.queryByRole('region')).not.toBeInTheDocument()
    })

    test('does not render for Copilot Enterprise plan', () => {
      mockUseWorkbenchStore.mockReturnValue({
        readOnly: false,
        status: {},
        entitlement: {
          [EntitledService.COPILOT]: {
            licenseType: CopilotLicenseType.LicensedLimited,
            plan: CopilotPlan.Enterprise,
            quotas: {
              limits: {
                chat: 100,
                premiumInteractions: 50,
              },
              remaining: {
                chat: 100,
                chatPercentage: 100,
                premiumInteractions: 100,
                premiumInteractionsPercentage: 100,
              },
              resetDate: '2025-05-15',
              overagesEnabled: false,
            },
          },
        },
      })

      render(<WorkbenchBanner />)

      expect(screen.queryByRole('region')).not.toBeInTheDocument()
    })
  })

  describe('Dismiss button', () => {
    test('dismisses banner when dismiss button is clicked', async () => {
      // Set up a dismissible state (quota approaching)
      mockUseWorkbenchStore.mockReturnValue({
        readOnly: false,
        status: {},
        entitlement: {
          [EntitledService.COPILOT]: {
            licenseType: CopilotLicenseType.LicensedLimited,
            plan: CopilotPlan.IndividualFree,
            quotas: {
              limits: {
                chat: 100,
                premiumInteractions: 50,
              },
              remaining: {
                chat: 10,
                chatPercentage: 10,
                premiumInteractions: 10,
                premiumInteractionsPercentage: 10,
              },
              resetDate: '2025-05-15',
              overagesEnabled: false,
            },
          },
        },
      })
      mockGetChatQuotaApproaching.mockReturnValue(true)

      render(<WorkbenchBanner />)

      // Assert banner is initially visible
      const banner = screen.getByRole('region', {name: /information/i})
      expect(banner).toBeInTheDocument()
      const dismissButton = screen.getByRole('button', {name: /dismiss/i})
      expect(dismissButton).toBeInTheDocument()

      // Click the dismiss button
      await userEvent.click(dismissButton)

      // Banner should no longer be visible
      expect(screen.queryByRole('region', {name: /information/i})).not.toBeInTheDocument()

      // setChatQuotaApproaching should have been called with false
      expect(mockSetChatQuotaApproaching).toHaveBeenCalledTimes(1)
      expect(mockSetChatQuotaApproaching).toHaveBeenCalledWith(false)
    })
  })
})
