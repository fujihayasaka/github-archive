import '@testing-library/jest-dom'

import {CopilotLicenseType, CopilotPlan} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {BannerType} from '@github-ui/workspace-editor/utilities/workspace-editor-types'
import {renderHook} from '@testing-library/react'

import {Service, Status} from '../../contexts/WorkbenchStoreContext'
import {EntitledService} from '../../utilities/workbench-store-reducer'
import {useBannerState} from '../use-banner-state'

// Mock all dependencies
jest.mock('@github-ui/feature-flags')
jest.mock('@github-ui/react-core/use-route-payload')
jest.mock('../../contexts/WorkbenchStoreContext')
jest.mock('../use-concurrent-sparks')
jest.mock('../use-optional-server-events')
jest.mock('../use-spark-idle')

const mockIsFeatureEnabled = jest.requireMock('@github-ui/feature-flags').isFeatureEnabled as jest.Mock
const mockUseRoutePayload = jest.requireMock('@github-ui/react-core/use-route-payload').useRoutePayload as jest.Mock
const mockUseWorkbenchStore = jest.requireMock('../../contexts/WorkbenchStoreContext').useWorkbenchStore as jest.Mock
const mockUseConcurrentSparks = jest.requireMock('../use-concurrent-sparks').useConcurrentSparks as jest.Mock
const mockUseServerEvents = jest.requireMock('../use-optional-server-events').useOptionalServerEvents as jest.Mock
const mockUseSparkIdle = jest.requireMock('../use-spark-idle').useSparkIdle as jest.Mock

describe('useBannerState', () => {
  const defaultWorkbenchStore = {
    entitlement: {
      [EntitledService.COPILOT]: {
        plan: CopilotPlan.IndividualFree,
        licenseType: CopilotLicenseType.LicensedLimited,
        quotas: {
          remaining: {
            chat: 10,
            premiumInteractions: 0,
            chatPercentage: 100,
            premiumInteractionsPercentage: 0,
            computeHoursPercentage: 100,
          },
        },
      },
      [EntitledService.CODESPACE_SESSIONS]: {
        allowed: true,
      },
      [EntitledService.CODESPACE_COMPUTE]: {
        allowed: true,
        quotas: {
          remaining: {
            computeHoursPercentage: 100,
          },
        },
      },
    },
    status: {
      [Service.CODESPACE]: Status.CONNECTED,
    },
  }

  const defaultRoutePayload = {
    workbench: {
      runtimePermanentName: 'test-runtime',
    },
  }

  beforeEach(() => {
    jest.clearAllMocks()

    // Default mocks
    mockIsFeatureEnabled.mockImplementation((flag: string) => flag === 'copilot_workbench_user_limits')
    mockUseRoutePayload.mockReturnValue(defaultRoutePayload)
    mockUseWorkbenchStore.mockReturnValue(defaultWorkbenchStore)
    mockUseConcurrentSparks.mockReturnValue({activeSparks: []})
    mockUseServerEvents.mockReturnValue({errors: []})
    mockUseSparkIdle.mockReturnValue(false)
  })

  describe('when feature flag is disabled', () => {
    it('returns null', () => {
      mockIsFeatureEnabled.mockReturnValue(false)

      const {result} = renderHook(() => useBannerState())

      expect(result.current).toBeNull()
    })
  })

  describe('when workbench is undefined', () => {
    it('handles undefined workbench gracefully', () => {
      mockUseRoutePayload.mockReturnValue({workbench: undefined})

      const {result} = renderHook(() => useBannerState())

      expect(result.current).toBeNull()
    })
  })

  describe('rate limiting', () => {
    it('returns SPARK_INFRA_LIMIT when rate limited', () => {
      mockUseServerEvents.mockReturnValue({
        errors: [{statusCode: 429}],
      })

      const {result} = renderHook(() => useBannerState())

      expect(result.current).toBe(BannerType.SPARK_INFRA_LIMIT)
    })
  })

  describe('quota limits', () => {
    it('returns COPILOT_CHAT_QUOTA when chat quota exceeded for licensed limited users', () => {
      mockUseWorkbenchStore.mockReturnValue({
        ...defaultWorkbenchStore,
        entitlement: {
          ...defaultWorkbenchStore.entitlement,
          [EntitledService.COPILOT]: {
            plan: CopilotPlan.IndividualFree,
            licenseType: CopilotLicenseType.LicensedLimited,
            quotas: {
              remaining: {
                chat: 0,
                chatPercentage: 0,
                premiumInteractions: 0,
                premiumInteractionsPercentage: 0,
                computeHoursPercentage: 100,
              },
            },
          },
        },
      })

      const {result} = renderHook(() => useBannerState())

      expect(result.current).toBe(BannerType.COPILOT_CHAT_QUOTA)
    })

    it('returns COPILOT_CHAT_QUOTA when premium interactions quota exceeded for paid users', () => {
      mockUseWorkbenchStore.mockReturnValue({
        ...defaultWorkbenchStore,
        entitlement: {
          ...defaultWorkbenchStore.entitlement,
          [EntitledService.COPILOT]: {
            plan: CopilotPlan.IndividualPro,
            licenseType: CopilotLicenseType.LicensedLimited,
            quotas: {
              remaining: {
                chat: 10,
                chatPercentage: 100,
                premiumInteractions: 0,
                premiumInteractionsPercentage: 0,
                computeHoursPercentage: 100,
              },
            },
          },
        },
      })

      const {result} = renderHook(() => useBannerState())

      expect(result.current).toBe(BannerType.COPILOT_CHAT_QUOTA)
    })

    it('returns COPILOT_CHAT_QUOTA when chat quota approaching for licensed limited users', () => {
      mockUseWorkbenchStore.mockReturnValue({
        ...defaultWorkbenchStore,
        entitlement: {
          ...defaultWorkbenchStore.entitlement,
          [EntitledService.COPILOT]: {
            plan: CopilotPlan.IndividualFree,
            licenseType: CopilotLicenseType.LicensedLimited,
            quotas: {
              remaining: {
                chat: 5,
                chatPercentage: 40,
                premiumInteractions: 0,
                premiumInteractionsPercentage: 0,
                computeHoursPercentage: 100,
              },
            },
          },
        },
      })

      const {result} = renderHook(() => useBannerState())

      expect(result.current).toBe(BannerType.COPILOT_CHAT_QUOTA)
    })

    it('returns COPILOT_CHAT_QUOTA when premium interactions quota approaching for paid users', () => {
      mockUseWorkbenchStore.mockReturnValue({
        ...defaultWorkbenchStore,
        entitlement: {
          ...defaultWorkbenchStore.entitlement,
          [EntitledService.COPILOT]: {
            plan: CopilotPlan.Business,
            licenseType: CopilotLicenseType.LicensedFull,
            quotas: {
              remaining: {
                chat: 10,
                chatPercentage: 100,
                premiumInteractions: 2,
                premiumInteractionsPercentage: 15,
                computeHoursPercentage: 100,
              },
            },
          },
        },
      })

      const {result} = renderHook(() => useBannerState())

      expect(result.current).toBe(BannerType.COPILOT_CHAT_QUOTA)
    })

    it('returns COPILOT_CHAT_QUOTA when overage limit reached', () => {
      mockUseServerEvents.mockReturnValue({
        errors: [{statusCode: 402}],
      })

      const {result} = renderHook(() => useBannerState())

      expect(result.current).toBe(BannerType.COPILOT_CHAT_QUOTA)
    })
  })

  describe('concurrent sparks', () => {
    it('returns MULTIPLE_SPARKS when concurrent sparks not allowed and current spark is not active', () => {
      mockUseWorkbenchStore.mockReturnValue({
        ...defaultWorkbenchStore,
        entitlement: {
          ...defaultWorkbenchStore.entitlement,
          [EntitledService.CODESPACE_SESSIONS]: {
            allowed: false,
          },
        },
      })
      mockUseConcurrentSparks.mockReturnValue({
        activeSparks: [{runtimePermanentName: 'other-runtime'}],
      })

      const {result} = renderHook(() => useBannerState())

      expect(result.current).toBe(BannerType.MULTIPLE_SPARKS)
    })

    it('does not return MULTIPLE_SPARKS when current spark is active', () => {
      mockUseWorkbenchStore.mockReturnValue({
        ...defaultWorkbenchStore,
        entitlement: {
          ...defaultWorkbenchStore.entitlement,
          [EntitledService.CODESPACE_SESSIONS]: {
            allowed: false,
          },
        },
      })
      mockUseConcurrentSparks.mockReturnValue({
        activeSparks: [{runtimePermanentName: 'test-runtime'}],
      })

      const {result} = renderHook(() => useBannerState())

      expect(result.current).toBeNull()
    })
  })

  describe('compute limits', () => {
    it('returns COMPUTE_LIMIT when compute quota exhausted', () => {
      mockUseWorkbenchStore.mockReturnValue({
        ...defaultWorkbenchStore,
        entitlement: {
          ...defaultWorkbenchStore.entitlement,
          [EntitledService.CODESPACE_COMPUTE]: {
            allowed: true,
            quotas: {
              remaining: {
                computeHoursPercentage: 0,
              },
            },
          },
        },
      })

      const {result} = renderHook(() => useBannerState())

      expect(result.current).toBe(BannerType.COMPUTE_LIMIT)
    })

    it('does not return COMPUTE_LIMIT when unlimited compute feature is enabled', () => {
      mockIsFeatureEnabled.mockImplementation(
        (flag: string) => flag === 'copilot_workbench_user_limits' || flag === 'spark_unlimited_dev_compute',
      )
      mockUseWorkbenchStore.mockReturnValue({
        ...defaultWorkbenchStore,
        entitlement: {
          ...defaultWorkbenchStore.entitlement,
          [EntitledService.CODESPACE_COMPUTE]: {
            allowed: true,
            quotas: {
              remaining: {
                computeHoursPercentage: 0,
              },
            },
          },
        },
      })

      const {result} = renderHook(() => useBannerState())

      expect(result.current).toBeNull()
    })
  })

  describe('idle state', () => {
    it('returns IDLE_SPARK when spark is idle and codespace status is idle', () => {
      mockUseSparkIdle.mockReturnValue(true)
      mockUseWorkbenchStore.mockReturnValue({
        ...defaultWorkbenchStore,
        status: {
          [Service.CODESPACE]: Status.IDLE,
        },
      })

      const {result} = renderHook(() => useBannerState())

      expect(result.current).toBe(BannerType.IDLE_SPARK)
    })

    it('does not return IDLE_SPARK when spark is idle but codespace is not idle', () => {
      mockUseSparkIdle.mockReturnValue(true)
      mockUseWorkbenchStore.mockReturnValue({
        ...defaultWorkbenchStore,
        status: {
          [Service.CODESPACE]: Status.CONNECTED,
        },
      })

      const {result} = renderHook(() => useBannerState())

      expect(result.current).toBeNull()
    })
  })

  describe('priority order', () => {
    it('returns rate limiting banner over quota banners', () => {
      mockUseServerEvents.mockReturnValue({
        errors: [{statusCode: 429}],
      })
      mockUseWorkbenchStore.mockReturnValue({
        ...defaultWorkbenchStore,
        entitlement: {
          ...defaultWorkbenchStore.entitlement,
          [EntitledService.COPILOT]: {
            plan: CopilotPlan.IndividualFree,
            licenseType: CopilotLicenseType.LicensedLimited,
            quotas: {
              remaining: {
                chat: 0,
                chatPercentage: 0,
                premiumInteractions: 0,
                premiumInteractionsPercentage: 0,
                computeHoursPercentage: 100,
              },
            },
          },
        },
      })

      const {result} = renderHook(() => useBannerState())

      expect(result.current).toBe(BannerType.SPARK_INFRA_LIMIT)
    })
  })

  describe('no banner scenarios', () => {
    it('returns null when no banner conditions are met', () => {
      const {result} = renderHook(() => useBannerState())

      expect(result.current).toBeNull()
    })
  })
})
