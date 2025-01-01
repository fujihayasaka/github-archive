import {useMutation} from '@github-ui/react-query'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'

import type {Input} from './use-upsert-copilot-space'
import {resourceMetadataToRailsPayload} from './use-upsert-copilot-space'

// The key is the string 'id' used on the frontend. The number is a float representing the size percentage, e.g. 0.123
export type ResourceSizesResult = Record<string, number>

export const useGetCopilotSpaceResourceSizes = () => {
  const {mutateAsync: getCopilotSpaceResourceSizes, ...rest} = useMutation({
    mutationFn: async (input: Input): Promise<ResourceSizesResult> => {
      const body = {
        resources: input.resources?.map(r => ({
          // Need to use the frontend id here, not the databaseId. It is used to map size percentages back to the resource
          // on the frontend for resources that haven't been saved yet.
          id: r.id,
          // eslint-disable-next-line camelcase
          resource_type: r.type,
          metadata: resourceMetadataToRailsPayload(r),
        })),
      }

      const response = await verifiedFetchJSON('/copilot/spaces/resource_sizes', {
        method: 'POST',
        body,
      })

      const data = await response.json()
      if (!response.ok) {
        throw data.errorMessages
      }

      return data as ResourceSizesResult
    },
  })

  return {
    getCopilotSpaceResourceSizes,
    ...rest,
  }
}
