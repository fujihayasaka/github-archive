import {useChatState} from '@github-ui/copilot-chat/CopilotChatContext'
import {useChatManager} from '@github-ui/copilot-chat/CopilotChatManagerContext'
import type {CustomCopilot, CustomCopilotId} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {findCustomCopilot, getCopilotSpacePath} from '@github-ui/copilot-chat/utils/custom-copilots-helpers'
import {customCopilotQueryKey} from '@github-ui/custom-copilots/utils/fetch'
import {useMutation, useQueryClient} from '@github-ui/react-query'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'

export type Input = {starred: boolean}

export const useStarCopilotSpace = (id: CustomCopilotId) => {
  const manager = useChatManager()
  const {customCopilots} = useChatState()
  const queryClient = useQueryClient()

  const {mutateAsync: starCopilotSpace, ...rest} = useMutation({
    onSuccess: async () => {
      if (id) {
        await queryClient.invalidateQueries({queryKey: customCopilotQueryKey(id)})
      }
    },
    mutationFn: async (input: Input) => {
      const copilotSpace = findCustomCopilot(customCopilots, id) as CustomCopilot | undefined
      if (!copilotSpace) return

      const url = `${getCopilotSpacePath(id)}/stars`
      const method = input.starred ? 'POST' : 'DELETE'

      const response = await verifiedFetchJSON(url, {
        method,
      })

      if (!response.ok) {
        return
      }

      // since this is the only field that changed
      // we can just do a front end update instead of
      // having to return a whole object.
      copilotSpace.starred = input.starred

      manager.dispatch({
        type: 'SET_CUSTOM_COPILOT',
        customCopilot: copilotSpace,
      })

      return copilotSpace
    },
  })

  return {
    starCopilotSpace,
    ...rest,
  }
}
