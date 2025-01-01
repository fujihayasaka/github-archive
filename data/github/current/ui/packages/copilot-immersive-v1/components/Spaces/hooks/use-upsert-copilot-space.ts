import {useChatManager} from '@github-ui/copilot-chat/CopilotChatManagerContext'
import type {CustomCopilot} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import type {CustomCopilotResource} from '@github-ui/custom-copilots/types'
import {useMutation} from '@github-ui/react-query'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'

function resourceMetadataToRailsPayload(resource: CustomCopilotResource) {
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
    default:
      throw new Error(`Unsupported resource`)
  }
}

type Input = Partial<Omit<CustomCopilot, 'id'>>

export const useUpsertCopilotSpace = (id?: CustomCopilot['id']) => {
  const manager = useChatManager()

  const {mutateAsync: upsertCopilotSpace, ...rest} = useMutation({
    mutationFn: async (input: Input) => {
      const url = id ? `/custom_copilots/${id}` : '/custom_copilots'
      const method = id ? 'PUT' : 'POST'

      const response = await verifiedFetchJSON(url, {
        method,
        body: {
          // eslint-disable-next-line camelcase
          custom_copilot: {
            name: input.name,
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
          },
        },
      })

      const data = await response.json()

      if (!response.ok) {
        throw data.errorMessages
      }

      // we are updating manager cache with response because it includes all fields (e.g. resources)
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
