// eslint-disable-next-line @github-ui/github-monorepo/filename-convention
import {isFeatureEnabled} from '@github-ui/feature-flags'
import {withBaseProvidersWrapper} from '@github-ui/react-core/test-utils'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'
import {renderHook, waitFor} from '@testing-library/react'

import {useCopilotChatEntitlement} from '../copilot-chat-entitlement'
import {CopilotLicenseType} from '../copilot-chat-types'

jest.mock('@github-ui/verified-fetch')
const mockVerifiedFetchJSON = verifiedFetchJSON as jest.Mock

jest.mock('@github-ui/feature-flags', () => {
  const actualFeatureFlags = jest.requireActual('@github-ui/feature-flags')
  {
    return {
      ...actualFeatureFlags,
      isFeatureEnabled: jest.fn(),
    }
  }
})

function isFeatureEnabledMockValue(value: boolean) {
  ;(isFeatureEnabled as jest.Mock).mockImplementation(() => value)
}

describe('copilot-chat-entitlement', () => {
  describe('#useCopilotChatEntitlement', () => {
    afterEach(() => {
      jest.resetAllMocks()
    })

    it('returns a valid entitlement when unlicensed', async () => {
      mockVerifiedFetchJSON.mockResolvedValue({
        ok: true,
        json: () => ({
          licenseType: CopilotLicenseType.Unlicensed,
        }),
      })

      const {result} = renderHook(() => useCopilotChatEntitlement(CopilotLicenseType.Unlicensed), {
        wrapper: withBaseProvidersWrapper(),
      })
      await waitFor(() => {
        expect(result.current[0].isLicensed()).toEqual(false)
      })

      const entitlement = result.current[0]
      expect(entitlement.chatQuotaRemaining()).toEqual(0)
    })

    it('returns a valid entitlement when API returns cached data', async () => {
      isFeatureEnabledMockValue(true)
      mockVerifiedFetchJSON.mockResolvedValue({
        ok: true,
        json: () => ({
          licenseType: CopilotLicenseType.LicensedFull,
        }),
      })

      const {result} = renderHook(() => useCopilotChatEntitlement(CopilotLicenseType.LicensedFull), {
        wrapper: withBaseProvidersWrapper(),
      })

      await waitFor(() => {
        expect(result.current[0].isLicensed()).toEqual(true)
      })
      expect(result.current[0].licenseType).toEqual(CopilotLicenseType.LicensedFull)

      mockVerifiedFetchJSON.mockResolvedValue({
        ok: false,
      })

      const {result: secondResult} = renderHook(() => useCopilotChatEntitlement(CopilotLicenseType.LicensedFull), {
        wrapper: withBaseProvidersWrapper(),
      })

      await waitFor(() => {
        expect(secondResult.current[0].isLicensed()).toEqual(true)
      })
      expect(result.current[0].licenseType).toEqual(CopilotLicenseType.LicensedFull)
    })

    it('returns a valid entitlement when fully licensed', async () => {
      isFeatureEnabledMockValue(true)
      mockVerifiedFetchJSON.mockResolvedValue({
        ok: true,
        json: () => ({
          licenseType: CopilotLicenseType.LicensedFull,
        }),
      })

      const {result} = renderHook(() => useCopilotChatEntitlement(CopilotLicenseType.LicensedFull), {
        wrapper: withBaseProvidersWrapper(),
      })
      await waitFor(() => {
        expect(result.current[0].isLicensed()).toEqual(true)
      })
    })
  })
})
