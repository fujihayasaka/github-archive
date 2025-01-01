import type React from 'react'
import {createContext, useContext, useMemo} from 'react'

import {useCopilotChatEntitlement} from '../../utils/copilot-chat-entitlement'
import {type CopilotChatEntitlementQuotas, CopilotLicenseType} from '../../utils/copilot-chat-types'

interface EntitlementContextType {
  licenseType: CopilotLicenseType | null
  chatQuotaRemaining: number
  resetDate: string
  isLicensedLimited: boolean
  chatQuotaExceeded: boolean
  reloadQuota: () => void
}

interface EntitlementProviderProps {
  children: React.ReactNode
  initialLicenseType: CopilotLicenseType
  initialQuotas?: CopilotChatEntitlementQuotas
}

const EntitlementContext = createContext<EntitlementContextType | undefined>(undefined)

export function EntitlementProvider({children, initialLicenseType, initialQuotas}: EntitlementProviderProps) {
  const [entitlement, reloadQuota] = useCopilotChatEntitlement(initialLicenseType, initialQuotas)
  const licenseType = entitlement.licenseType

  const chatQuotaRemaining = entitlement.chatQuotaRemaining() ?? Infinity

  const resetDate = entitlement.quotas?.resetDate
    ? new Date(entitlement.quotas.resetDate).toLocaleDateString('en-US', {
        year: 'numeric',
        month: 'long',
        day: 'numeric',
      })
    : ''

  const isLicensedLimited = licenseType === CopilotLicenseType.LicensedLimited

  const chatQuotaExceeded = isLicensedLimited && chatQuotaRemaining <= 0

  const value = useMemo(
    () => ({
      licenseType,
      chatQuotaRemaining,
      resetDate,
      isLicensedLimited,
      chatQuotaExceeded,
      reloadQuota,
    }),
    [licenseType, chatQuotaRemaining, resetDate, isLicensedLimited, chatQuotaExceeded, reloadQuota],
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
