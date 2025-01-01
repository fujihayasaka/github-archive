import {verifiedFetchJSON} from '@github-ui/verified-fetch'
import {organizationSettingsModelsBillingPath} from '@github-ui/paths'
import {useMutation} from '@github-ui/react-query'
import type {UpdateModelsBillingPayload} from '../types'

export function useUpdateOrganizationBilling({orgDisplayLogin}: {orgDisplayLogin: string}) {
  const path = organizationSettingsModelsBillingPath({org: orgDisplayLogin})
  return useMutation({
    mutationKey: ['set-github-models-organization-billing', orgDisplayLogin],
    mutationFn: async ({method, body}: UpdateModelsBillingPayload) => {
      const result = await verifiedFetchJSON(path, {method, body})
      if (result.ok) {
        const json = await result.json()
        return json
      }
      throw new Error(`${result.status} on ${result.url}, unexpected status or payload`)
    },
  })
}

/**
 * Returns the request configuration to turn off the organization configuration setting for GitHub Models.
 */
export function disableModelsBillingPayload(): UpdateModelsBillingPayload {
  return {method: 'POST', body: {enable: '0'}}
}

/**
 * Returns the request configuration to turn on the organization configuration setting for GitHub Models.
 */
export function enableModelsBillingPayload(): UpdateModelsBillingPayload {
  return {method: 'POST', body: {enable: '1'}}
}
