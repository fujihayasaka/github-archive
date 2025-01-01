import {CopilotAuthTokenProvider} from '@github-ui/copilot-auth-token'
import {makeCAPIRequest} from '@github-ui/copilot-chat/utils/copilot-chat-helpers'
import {CopilotChatMessageStreamer} from '@github-ui/copilot-chat/utils/copilot-chat-message-streamer'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {useQuery} from '@github-ui/react-query'
import {useRef} from 'react'

import {workspaceEditorIntegrationId} from '../utilities/copilot-chat'
import {
  type AgentResponse,
  formatChangedFilesAsDiffs,
  handleStreamingMessage,
  validateAndExtractCommitMessage,
} from '../utilities/generate-commit-message-helpers'
import type {ChangedFile, WorkspaceEditorRoutePayload} from '../utilities/workspace-editor-types'

export function useGenerateCommitMessage({changedFiles}: {changedFiles: ChangedFile[]}) {
  const {
    copilot: {apiURL, ssoOrganizations},
    copilotAccessAllowed,
  } = useRoutePayload<WorkspaceEditorRoutePayload>()
  const integrationId = workspaceEditorIntegrationId()
  const authTokenProvider = useRef(new CopilotAuthTokenProvider(ssoOrganizations.map(org => org.id)))

  const {data: generatedCommitMessage, isLoading} = useQuery({
    // We don't want to cache on the selected files, because we don't want to re-generate
    // a commit message while a user toggles files. These changes happen "behind" the user,
    // and are an accessibility concern.
    // eslint-disable-next-line @tanstack/query/exhaustive-deps
    queryKey: ['generate-commit-message', apiURL, copilotAccessAllowed],
    // eslint-disable-next-line @tanstack/query/no-void-query-fn
    queryFn: async () => {
      if (!copilotAccessAllowed) return null
      const token = await authTokenProvider.current.getAuthToken()
      const result = await makeCAPIRequest({
        authToken: token,
        basePath: apiURL,
        body: {
          messages: [
            {
              role: 'user',
              content: '',
              copilot_references: formatChangedFilesAsDiffs(changedFiles),
            },
          ],
        },
        integrationId,
        method: 'POST',
        path: '/agents/github-commit-message-generation',
        streamingResponse: true,
      })

      if (!result.ok) {
        throw new Error('Failed to generate commit message')
      }

      const reader = result.body?.getReader()
      if (!reader) {
        throw new Error('No reader found in response body')
      }

      const streamer = new CopilotChatMessageStreamer<AgentResponse>(reader)
      const message = await handleStreamingMessage(streamer)
      return validateAndExtractCommitMessage(message)
    },
    meta: {action: 'get-generated-commit-message'},
  })

  return {generatedCommitMessage, isLoading}
}
