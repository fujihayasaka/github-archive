import type {CopilotAuthTokenProvider} from '@github-ui/copilot-auth-token'
import {makeCAPIRequest} from '@github-ui/copilot-chat/utils/copilot-chat-helpers'
import {CopilotChatMessageStreamer} from '@github-ui/copilot-chat/utils/copilot-chat-message-streamer'
import type {Repository} from '@github-ui/current-repository'
import {useQuery} from '@tanstack/react-query'

import {workspaceEditorIntegrationId} from '../utilities/copilot-chat'
import {
  type AgentResponse,
  buildCommentsPayload,
  buildFilePayload,
  type CommentClassification,
  type GeneratedFix,
  generatedFixKey,
  handleStreamingMessage,
  validateAndExtractGeneratedFix,
} from '../utilities/generate-fix-helpers'
import type {BlobPayload, FocusedGenerativeTaskData, PullRequestData} from '../utilities/workspace-editor-types'
import {useLocalStorageWithExpiry} from './use-local-storage-with-expiry'

export function useGenerateFixQuery({
  apiURL,
  authTokenProvider,
  generateFixTask,
  repo,
  pullRequest,
  blobData,
  commentsVersion,
  suggestionRequestId,
  sourceId,
  commentClassification,
}: {
  apiURL: string
  authTokenProvider: CopilotAuthTokenProvider
  generateFixTask?: FocusedGenerativeTaskData
  repo: Repository
  pullRequest: PullRequestData
  blobData: BlobPayload | undefined
  commentsVersion: string
  suggestionRequestId: string
  sourceId: string
  commentClassification: CommentClassification | undefined
}) {
  const [cachedGeneratedFix, setCachedGeneratedFix] = useLocalStorageWithExpiry<GeneratedFix | undefined>(
    generatedFixKey(repo.ownerLogin, repo.name, pullRequest.number, sourceId, 'generated-fix'),
    undefined,
  )

  const {
    data: generatedFix,
    isFetching,
    refetch,
    isError,
  } = useQuery({
    queryKey: [
      'generate-fix',
      apiURL,
      generateFixTask,
      blobData,
      !!commentClassification?.actionable,
      repo,
      commentsVersion,
      suggestionRequestId,
    ],
    queryFn: async () => {
      if (!generateFixTask) throw new Error('No generateFixTask loaded to work with')
      if (!blobData) throw new Error('No blob data loaded to work with')
      const token = await authTokenProvider.getAuthToken()
      const comments = buildCommentsPayload(generateFixTask)
      const file = buildFilePayload(blobData, repo)
      const metadata = {
        type: 'github.suggestion-metadata',
        data: {
          type: 'suggestion-metadata',
          suggestion_request_id: suggestionRequestId,
          comment_version: commentsVersion,
        },
      }

      const integrationId = workspaceEditorIntegrationId()
      const result = await makeCAPIRequest({
        authToken: token,
        basePath: apiURL,
        body: {
          messages: [
            {
              role: 'user',
              content: '',
              copilot_references: [...comments, file, metadata],
            },
          ],
        },
        integrationId,
        method: 'POST',
        path: '/agents/github-code-reviser',
        streamingResponse: true,
      })
      if (!result.ok) throw Error(result.status.toString())
      const reader = result.body?.getReader()

      if (!reader) throw Error('No reader found in response body')
      const streamer = new CopilotChatMessageStreamer<AgentResponse>(reader)
      const message = await handleStreamingMessage(streamer)
      const fix = validateAndExtractGeneratedFix(message)
      fix.commentsVersion = commentsVersion
      return fix
    },
    enabled: generateFixTask && !!blobData && !!commentClassification?.actionable && !cachedGeneratedFix,
    retry: false,
    meta: {
      action: 'get-generated-fix',
    },
  })

  if (!cachedGeneratedFix && generatedFix) {
    setCachedGeneratedFix(generatedFix)
  }

  const refetchGeneratedFix = () => {
    setCachedGeneratedFix(undefined)
    refetch()
  }

  return {
    generatedFix: cachedGeneratedFix,
    refetch: refetchGeneratedFix,
    isFetching,
    isError,
  }
}
