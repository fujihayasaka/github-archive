import type React from 'react'
import {createContext, useContext, useMemo} from 'react'

import {useCopilotChatEntitlement} from '../../utils/copilot-chat-entitlement'
import {type CopilotChatEntitlementQuotas, CopilotLicenseType, type CopilotPlan} from '../../utils/copilot-chat-types'
import {copilotFeatureFlags} from '../../utils/copilot-feature-flags'

interface EntitlementContextType {
  licenseType: CopilotLicenseType | null
  plan: CopilotPlan | null
  chatQuotaRemaining: number
  premiumChatQuotaRemaining: number
  resetDate: string
  isLicensedLimited: boolean
  chatQuotaExceeded: boolean
  premiumInteractionsQuotaExceeded: boolean
  reloadQuota: () => void
  canPurchaseAdditionalQuota: boolean
  canUpgradePlan: boolean
  overagesEnabled: boolean
}

interface EntitlementProviderProps {
  children: React.ReactNode
  initialLicenseType: CopilotLicenseType
  initialPlan?: CopilotPlan
  initialQuotas?: CopilotChatEntitlementQuotas
}

export const EntitlementContext = createContext<EntitlementContextType | undefined>(undefined)

export function EntitlementProvider({
  children,
  initialLicenseType,
  initialPlan,
  initialQuotas,
}: EntitlementProviderProps) {
  const [entitlement, reloadQuota] = useCopilotChatEntitlement(initialLicenseType, initialPlan, initialQuotas)
  const licenseType = entitlement.licenseType
  const plan = entitlement.plan ?? null

  const chatQuotaRemaining = entitlement.chatQuotaRemaining() ?? Infinity
  const premiumChatQuotaRemaining = entitlement.premiumInteractionsQuotaRemaining() ?? Infinity

  const resetDate = entitlement.quotas?.resetDate
    ? new Date(entitlement.quotas.resetDate).toLocaleDateString('en-US', {
        year: 'numeric',
        month: 'long',
        day: 'numeric',
      })
    : ''

  const isLicensedLimited = licenseType === CopilotLicenseType.LicensedLimited

  const canPurchaseAdditionalQuota = entitlement.canPurchaseAdditionalQuota()
  const canUpgradePlan = entitlement.canUpgradePlan()

  const chatQuotaExceeded = isLicensedLimited && chatQuotaRemaining <= 0
  const premiumInteractionsQuotaExceeded =
    copilotFeatureFlags.premiumRequestQuotasEnabled && premiumChatQuotaRemaining <= 0

  const overagesEnabled = entitlement.quotas?.overagesEnabled ?? false

  const value = useMemo(
    () => ({
      licenseType,
      chatQuotaRemaining,
      premiumChatQuotaRemaining,
      resetDate,
      isLicensedLimited,
      chatQuotaExceeded,
      premiumInteractionsQuotaExceeded,
      reloadQuota,
      plan,
      canPurchaseAdditionalQuota,
      canUpgradePlan,
      overagesEnabled,
    }),
    [
      licenseType,
      chatQuotaRemaining,
      premiumChatQuotaRemaining,
      resetDate,
      isLicensedLimited,
      chatQuotaExceeded,
      premiumInteractionsQuotaExceeded,
      reloadQuota,
      plan,
      canPurchaseAdditionalQuota,
      canUpgradePlan,
      overagesEnabled,
    ],
  )

  return <EntitlementContext.Provider value={value}>{children}</EntitlementContext.Provider>
}

export const useEntitlement = () => {
  const context = useContext(EntitlementContext)
  if (!context) {
    throw new Error('useEntitlement must be used within EntitlementProvider')
  }
  return context
}
