import {useMutation, useQueryClient, useQuery} from '@github-ui/react-query'
import {
  CUSTOM_COPILOTS_QUERY_KEY,
  customCopilotQueryKey,
  deleteCustomCopilot,
  fetchCustomCopilot,
  fetchCustomCopilots,
  fetchVisibilitySettings,
} from '../utils/fetch'
import type {
  CustomCopilotId,
  CustomCopilot,
  CustomCopilotPayload,
} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {useChatManager} from '@github-ui/copilot-chat/CopilotChatManagerContext'
import {useEffect} from 'react'
import {useChatStateValue} from '@github-ui/copilot-chat/CopilotChatContext'

export class CustomCopilotNotFoundError extends Error {
  constructor(message = 'Custom Copilot not found') {
    super(message)
    this.name = 'CustomCopilotNotFoundError'
  }
}

export class CustomCopilotSSOError extends Error {
  protectedOrganizations: string[]
  constructor(protectedOrganizations: string[], message = 'Custom Copilot SSO error') {
    super(message)
    this.protectedOrganizations = protectedOrganizations
    this.name = 'CustomCopilotSSOError'
  }
}

export function useDeleteCustomCopilot() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: async (item: CustomCopilotId) => {
      const result = await deleteCustomCopilot(item)
      // Ensure result is not an error type before returning
      if (!result.ok) {
        throw new Error(String(result.error))
      }
      // Only return the payload or a safe object
      return {status: result.status, ok: true, payload: result.payload}
    },
    onSuccess: async () => {
      await queryClient.invalidateQueries({queryKey: CUSTOM_COPILOTS_QUERY_KEY})
    },
  })
}

/**
 * A hook to manage the custom copilots in the chat manager.
 * Run only for side effects. Eventually we'll replace this with the underlying
 * `useManagedFetchCustomCopilots` hook.
 * It fetches the custom copilots and updates the chat manager state.
 * @param enabled - Whether to enable the fetching of custom copilots.
 */
export function useManagedFetchCustomCopilots(enabled: boolean) {
  const manager = useChatManager()
  const {data} = useFetchCustomCopilots(enabled)
  useEffect(() => {
    if (data) {
      manager.dispatch({type: 'SET_CUSTOM_COPILOTS', customCopilots: data})
    }
  }, [data, manager])
}
/**
 * The default hook for fetching custom copilots from the server.
 */
export function useFetchCustomCopilots(enabled: boolean) {
  return useQuery({
    queryKey: CUSTOM_COPILOTS_QUERY_KEY,
    queryFn: fetchCustomCopilots,
    enabled,
    staleTime: 5 * 60 * 1000, // 5 minutes
  })
}

function hasCustomCopilotData(payload: CustomCopilotPayload): payload is CustomCopilot {
  return (payload as CustomCopilot).id !== undefined
}

export function useFetchCustomCopilot(customCopilotId: CustomCopilotId | null) {
  return useQuery({
    queryKey: customCopilotQueryKey(customCopilotId),
    queryFn: async () => {
      const response = await fetchCustomCopilot(customCopilotId)
      if (!response.ok) {
        if (response.status === 404) {
          throw new CustomCopilotNotFoundError()
        }
        throw new Error(response.error)
      }
      if (!hasCustomCopilotData(response.payload)) {
        throw new CustomCopilotSSOError(response.payload.protectedOrganizations)
      }
      return response.payload
    },
    enabled: !!customCopilotId,
  })
}

// We split up the customCopilotId because the linter wants each parameter used in the query key,
// but directly passing the whole object in seems to key on object identity and lead to lots of
// redundant API calls.
export function useFetchVisibilitySettings(customCopilotOwner: string, customCopilotNumber: number) {
  return useQuery({
    queryKey: ['visibility-settings', customCopilotOwner, customCopilotNumber],
    queryFn: async () => {
      return fetchVisibilitySettings({owner: customCopilotOwner, id: customCopilotNumber})
    },
    enabled: customCopilotOwner !== '' && customCopilotNumber !== -1,
    staleTime: 5 * 60 * 1000, // 5 minutes
  })
}

/**
 * Custom copilots are enabled for:
 * 1. users with the :copilot_custom_copilots feature flag, which some will be individually opted into
 * 2. The following types of users with the :copilot_custom_copilots_feature_preview feature flag:
 *    a. users with Copilot Individual (CI) licenses, for whom preview features are always enabled
 *    b. CB and CE users whose orgs have opted into preview features
 *    c. Copilot Free users, signified by `has_limited_access` on their plan
 * This values is serialized down from the copilot_chat_helper and put into the chat state.
 */
export function useCustomCopilotsEnabled() {
  return useChatStateValue('customCopilotsEnabled')
}
