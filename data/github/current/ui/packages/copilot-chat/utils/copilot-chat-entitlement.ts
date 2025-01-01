import {useQuery, useQueryClient} from '@github-ui/react-query'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'
import {useCallback} from 'react'

import {type CopilotChatEntitlementQuotas, CopilotLicenseType, CopilotPlan} from './copilot-chat-types'
import {copilotFeatureFlags} from './copilot-feature-flags'

export type CopilotChatEntitlementResult = {
  licenseType: CopilotLicenseType
  plan?: CopilotPlan
  quotas?: CopilotChatEntitlementQuotas
}

export function useCopilotChatEntitlement(
  initialLicenseType: CopilotLicenseType,
  initialPlan?: CopilotPlan,
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
    enabled:
      initialLicenseType === CopilotLicenseType.LicensedLimited || copilotFeatureFlags.premiumRequestQuotasEnabled,
    placeholderData: {
      licenseType: initialLicenseType,
      plan: initialPlan,
      quotas: initialQuotas,
    },
    staleTime: 1000 * 60 * 1, // 1 minute
  })

  const license = data?.licenseType ?? initialLicenseType
  const plan = data?.plan ?? initialPlan

  const reloadQuota = useCallback(() => {
    if (license === CopilotLicenseType.LicensedLimited || copilotFeatureFlags.premiumRequestQuotasEnabled) {
      void invalidateEntitlement()
    }
  }, [invalidateEntitlement, license])

  return [new CopilotChatEntitlement(license, plan, data?.quotas), reloadQuota]
}

export class CopilotChatEntitlement {
  licenseType: CopilotLicenseType
  plan?: CopilotPlan
  quotas?: CopilotChatEntitlementQuotas

  constructor(licenseType: CopilotLicenseType, plan?: CopilotPlan, quotas?: CopilotChatEntitlementQuotas) {
    this.licenseType = licenseType
    this.plan = plan
    this.quotas = quotas
  }

  isLicensed(): boolean {
    return this.licenseType && this.licenseType !== CopilotLicenseType.Unlicensed
  }

  canPurchaseAdditionalQuota(): boolean {
    return (
      this.licenseType !== CopilotLicenseType.LicensedLimited &&
      copilotFeatureFlags.premiumRequestQuotasEnabled &&
      (this.plan === CopilotPlan.IndividualPro ||
        this.plan === CopilotPlan.IndividualProPlus ||
        this.plan === CopilotPlan.Business ||
        this.plan === CopilotPlan.Enterprise)
    )
  }

  canUpgradePlan(): boolean {
    return (
      this.licenseType === CopilotLicenseType.LicensedLimited ||
      (copilotFeatureFlags.premiumRequestQuotasEnabled &&
        (this.plan === CopilotPlan.IndividualPro || this.plan === CopilotPlan.Business))
    )
  }

  chatQuotaRemaining(): number {
    return copilotFeatureFlags.premiumRequestQuotasEnabled
      ? this.quotas?.remaining.chatPercentage ?? 0
      : this.quotas?.remaining.chat ?? 0
  }

  premiumInteractionsQuotaRemaining(): number {
    return this.quotas?.remaining.premiumInteractionsPercentage ?? 0
  }
}
