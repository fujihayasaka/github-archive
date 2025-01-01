import {useQuery, useQueryClient} from '@github-ui/react-query'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'
import {useCallback} from 'react'

import {type CopilotChatEntitlementQuotas, CopilotLicenseType} from './copilot-chat-types'

export type CopilotChatEntitlementResult = {
  licenseType: CopilotLicenseType
  quotas?: CopilotChatEntitlementQuotas
}

export function useCopilotChatEntitlement(
  initialLicenseType: CopilotLicenseType,
  initialQuotas?: CopilotChatEntitlementQuotas,
): [entitlement: CopilotChatEntitlement, reloadQuota: () => void] {
  const client = useQueryClient()

  const invalidateEntitlement = useCallback(
    () => client.invalidateQueries({queryKey: ['copilot-chat', 'entitlement']}),
    [client],
  )

  const {data} = useQuery<CopilotChatEntitlementResult>({
    queryKey: ['copilot-chat', 'entitlement'],
    queryFn: async () => {
      const response = await verifiedFetchJSON('/github-copilot/chat/entitlement')

      if (!response.ok) {
        throw new Error(`Failed to retrieve Copilot chat entitlement (${response.status} on ${response.url})`)
      }

      return (await response.json()) as CopilotChatEntitlementResult
    },
    enabled: initialLicenseType === CopilotLicenseType.LicensedLimited,
    placeholderData: {
      licenseType: initialLicenseType,
      quotas: initialQuotas,
    },
    staleTime: 1000 * 60 * 5, // 5 minutes
  })

  const license = data?.licenseType ?? initialLicenseType

  // only licensed limited users have quotas
  const reloadQuota = useCallback(() => {
    if (license === CopilotLicenseType.LicensedLimited) {
      void invalidateEntitlement()
    }
  }, [invalidateEntitlement, license])

  return [new CopilotChatEntitlement(license, data?.quotas), reloadQuota]
}

export class CopilotChatEntitlement {
  licenseType: CopilotLicenseType
  quotas?: CopilotChatEntitlementQuotas

  constructor(licenseType: CopilotLicenseType, quotas?: CopilotChatEntitlementQuotas) {
    this.licenseType = licenseType
    this.quotas = quotas
  }

  isLicensed(): boolean {
    return this.licenseType && this.licenseType !== CopilotLicenseType.Unlicensed
  }

  chatQuotaRemaining(): number {
    return this.quotas?.remaining.chat ?? 0
  }
}
