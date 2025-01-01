import type {CopilotAuthTokenProvider} from '@github-ui/copilot-auth-token'
import {makeCAPIRequest} from '@github-ui/copilot-chat/utils/copilot-chat-helpers'
import {CopilotChatMessageStreamer} from '@github-ui/copilot-chat/utils/copilot-chat-message-streamer'
import type {Repository} from '@github-ui/current-repository'
import {useQuery} from '@github-ui/react-query'

import {useLocalStorageWithExpiry} from '../../workspace-editor/hooks/use-local-storage-with-expiry'
import {workspaceEditorIntegrationId} from '../../workspace-editor/utilities/copilot-chat'
import {
  type AgentResponse,
  buildCommentsPayload,
  buildFilePayload,
  type CommentClassification,
  generatedFixKey,
  handleStreamingMessage,
  validateAndExtractCommentClassification,
} from '../../workspace-editor/utilities/generate-fix-helpers'
import type {BlobPayload, FocusedGenerativeTaskData} from '../../workspace-editor/utilities/workspace-editor-types'

export function useClassifyComments({
  apiURL,
  authTokenProvider,
  generateFixTask,
  repo,
  blobData,
  commentsVersion,
  suggestionRequestId,
  sourceId,
}: {
  apiURL: string
  authTokenProvider: CopilotAuthTokenProvider
  generateFixTask?: FocusedGenerativeTaskData
  repo: Repository
  blobData: BlobPayload | undefined
  commentsVersion: string
  suggestionRequestId: string
  sourceId: string
}) {
  // TODO: Temporary work around to replace using pull request numbers
  const [cachedCommentClassification, setCachedCommentClassification] = useLocalStorageWithExpiry<
    CommentClassification | undefined
  >(generatedFixKey(repo.ownerLogin, repo.name, sourceId, 'comment-classification'), undefined)

  const shouldAutoRefetch =
    cachedCommentClassification &&
    !cachedCommentClassification?.actionable &&
    cachedCommentClassification?.commentsVersion !== commentsVersion
  const shouldUpdateClassification = !cachedCommentClassification || shouldAutoRefetch

  const {
    data: commentClassification,
    refetch,
    isFetching,
    isError,
  } = useQuery({
    queryKey: ['classify-comments', apiURL, generateFixTask, blobData, repo, commentsVersion, suggestionRequestId],
    queryFn: async () => {
      if (!generateFixTask) throw new Error('No generateFixTask loaded to work with')
      if (!blobData) throw new Error('No blob data loaded to work with')
      const token = await authTokenProvider.getAuthToken()
      const comments = buildCommentsPayload(generateFixTask)
      const file = buildFilePayload(blobData, repo)
      const integrationId = workspaceEditorIntegrationId()
      const metadata = {
        type: 'github.suggestion-metadata',
        data: {
          type: 'suggestion-metadata',
          suggestion_request_id: suggestionRequestId,
          comment_version: commentsVersion,
        },
      }

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
        path: '/agents/github-comment-classifier',
        streamingResponse: true,
      })
      if (!result.ok) throw Error(result.status.toString())
      const reader = result.body?.getReader()

      if (!reader) throw Error('No reader found in response body')
      const streamer = new CopilotChatMessageStreamer<AgentResponse>(reader)
      const message = await handleStreamingMessage(streamer)
      const classification = validateAndExtractCommentClassification(message)
      classification.commentsVersion = commentsVersion || ''
      return classification
    },
    enabled: generateFixTask && !!blobData && shouldUpdateClassification,
    retry: false,
    refetchOnWindowFocus: false,
    refetchOnMount: false,
    refetchOnReconnect: false,
    refetchInterval: false,
    meta: {
      action: 'get-comment-classification',
    },
  })

  if (commentClassification && shouldUpdateClassification) {
    setCachedCommentClassification(commentClassification)
  }

  const refetchCommentClassification = () => {
    setCachedCommentClassification(undefined)
    refetch()
  }

  return {
    commentClassification: cachedCommentClassification,
    refetch: refetchCommentClassification,
    isFetching,
    isError,
  }
}
