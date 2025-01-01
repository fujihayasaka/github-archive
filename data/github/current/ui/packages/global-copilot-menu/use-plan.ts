import {useQuery} from '@github-ui/react-query'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'
import type {CopilotChatEntitlementResult} from '@github-ui/copilot-chat/utils/copilot-chat-entitlement'
import {CopilotLicenseType} from '@github-ui/copilot-chat/utils/copilot-chat-types'

export const usePlan = () => {
  const {data} = useQuery<CopilotChatEntitlementResult>({
    queryKey: ['copilot-chat', 'entitlement'],
    queryFn: async () => {
      const response = await verifiedFetchJSON('/github-copilot/chat/entitlement')

      if (!response.ok) {
        throw new Error(`Failed to retrieve Copilot chat entitlement (${response.status} on ${response.url})`)
      }

      return (await response.json()) as CopilotChatEntitlementResult
    },
    placeholderData: {
      licenseType: CopilotLicenseType.Unlicensed,
    },
    staleTime: 1000 * 60 * 5, // 5 minutes
  })
  const plan = data?.plan

  return plan
}
