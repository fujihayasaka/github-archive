import {useChatManager} from '@github-ui/copilot-chat/CopilotChatManagerContext'
import type {CustomCopilot, CustomCopilotId} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {customCopilotApiPath} from '@github-ui/copilot-chat/utils/custom-copilots-helpers'
import type {CustomCopilotResource} from '@github-ui/custom-copilots/types'
import {CUSTOM_COPILOTS_QUERY_KEY, customCopilotQueryKey} from '@github-ui/custom-copilots/utils/fetch'
import {useMutation, useQueryClient} from '@github-ui/react-query'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'

export function resourceMetadataToRailsPayload(resource: CustomCopilotResource) {
  switch (resource.type) {
    case 'github_file':
      return {
        // eslint-disable-next-line camelcase
        repository_id: resource.repositoryId,
        // eslint-disable-next-line camelcase
        file_path: resource.filePath,
      }
    case 'free_text':
      return {
        text: resource.text,
        name: resource.name,
      }
    case 'github_issue':
    case 'github_pull_request':
      return {
        // eslint-disable-next-line camelcase
        repository_id: resource.repositoryId,
        number: resource.number,
      }
    case 'uploaded_text_file':
      return {
        name: resource.name,
        // eslint-disable-next-line camelcase
        copilot_chat_attachment_id: resource.copilotChatAttachmentId,
      }
    default:
      throw new Error(`Unsupported resource`)
  }
}

/**
 * The input type for the upsertCopilotSpace mutation.
 * We only allow a subset of fields to be updated from the client.
 */
export type Input = Partial<
  Pick<
    CustomCopilot,
    'name' | 'iconType' | 'iconColor' | 'description' | 'generalInstructions' | 'resources' | 'visibility'
  >
> & {ownerId?: number; ownerType?: string}

export const useUpsertCopilotSpace = (id?: CustomCopilotId) => {
  const manager = useChatManager()
  const queryClient = useQueryClient()

  const {mutateAsync: upsertCopilotSpace, ...rest} = useMutation({
    onSuccess: async () => {
      if (id) {
        await queryClient.invalidateQueries({queryKey: customCopilotQueryKey(id)})
      }
      return queryClient.invalidateQueries({queryKey: CUSTOM_COPILOTS_QUERY_KEY})
    },
    mutationFn: async (input: Input) => {
      const url = id ? customCopilotApiPath(id) : '/custom_copilots'
      const method = id ? 'PUT' : 'POST'

      const body = {
        // eslint-disable-next-line camelcase
        custom_copilot: {
          // eslint-disable-next-line camelcase
          owner_id: input.ownerId,
          // eslint-disable-next-line camelcase
          owner_type: input.ownerType,
          name: input.name,
          // eslint-disable-next-line camelcase
          icon_type: input.iconType,
          // eslint-disable-next-line camelcase
          icon_color: input.iconColor,
          description: input.description,
          // eslint-disable-next-line camelcase
          general_instructions: input.generalInstructions,
          // eslint-disable-next-line camelcase
          resources_attributes: input.resources?.map(r => ({
            id: r.databaseId,
            // eslint-disable-next-line camelcase
            resource_type: r.type,
            // The _destroy param is a special param used by Rails' accepts_nested_attributes_for. If set to true
            // the record will be deleted.
            _destroy: r.markedForDestroy,
            metadata: resourceMetadataToRailsPayload(r),
          })),
          visibility: input.visibility,
        },
      }

      const response = await verifiedFetchJSON(url, {
        method,
        body,
      })

      const data = await response.json()

      if (!response.ok) {
        throw data.errorMessages
      }

      // For now most call sites need to use the customCopilots state.
      // We'll continue to call this until we've removed them
      // we need to call manager to update the custom copilot in the chat
      manager.dispatch({
        type: 'SET_CUSTOM_COPILOT',
        customCopilot: data,
      })

      return data as CustomCopilot
    },
  })

  return {
    upsertCopilotSpace,
    ...rest,
  }
}
