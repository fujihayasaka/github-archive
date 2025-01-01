import {ResponseError} from '@github-ui/react-core/future/response-error'
import {useQueriesConfig} from '@github-ui/react-core/future/use-route-query'
import {getQueryClient} from '@github-ui/react-core/query-client'
import {useMutation} from '@github-ui/react-query'
import {reactFetchJSON} from '@github-ui/verified-fetch'

import {useCurrentOrg} from '../../contexts/CurrentOrgContext'
import {customModelsIndexRoute} from './custom-models-index-route'

export interface UpdateCustomModelPayload {
  modelId: number
  copilotChatEnabled: boolean
}

export function useUpdateCustomModel() {
  const {
    queryConfig: {queryKey},
  } = useQueriesConfig(customModelsIndexRoute, 'mainQuery')

  const org = useCurrentOrg()

  return useMutation<void, ResponseError, UpdateCustomModelPayload>({
    async mutationFn(variables) {
      const res = await reactFetchJSON(`/organizations/${org}/settings/custom-models/${variables.modelId}`, {
        method: 'PUT',
        body: {copilot_chat_enabled: variables.copilotChatEnabled},
      })
      if (!res.ok) throw new ResponseError('Failed to toggle copilot model enablement', res)
    },
    onSuccess() {
      /*
      TODO: I can see us make use of optimistic updates (onMutate) here in the future
      but for now we just invalidate the queries to refetch the data
      and ensure the UI is in sync with the server.
      Why? We're be refetching everything on a enable toggle.
      */
      return getQueryClient().invalidateQueries({queryKey})
    },
  })
}
