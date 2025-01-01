import {useCallback} from 'react'
import {verifiedFetch} from '@github-ui/verified-fetch'

export function useConfirmCopilotPlanChange(
  newPlan: string,
  orgId: number,
  basePath: string,
  onSuccess: () => void,
  onError: () => void,
) {
  return useCallback(async (): Promise<void> => {
    const formData = new FormData()
    formData.append('enablement', newPlan)
    formData.append('organization_id', orgId.toString())

    try {
      const response = await verifiedFetch(`${basePath}/settings/update_copilot_individual_org_enablement`, {
        method: 'PUT',
        body: formData,
      })
      if (response.ok) {
        onSuccess()
      } else {
        onError()
      }
    } catch {
      onError()
    }
  }, [basePath, newPlan, orgId, onSuccess, onError])
}
