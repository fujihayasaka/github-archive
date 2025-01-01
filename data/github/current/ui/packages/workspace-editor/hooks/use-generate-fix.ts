import {CopilotAuthTokenProvider} from '@github-ui/copilot-auth-token'
import {useCurrentRepository} from '@github-ui/current-repository'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {useQuery} from '@github-ui/react-query'
import {parsePatch} from 'diff'
import {useCallback, useRef} from 'react'

import {useCurrentPullRequest} from '../contexts/CurrentPullRequestProvider'
import {useWorkspaceEditorAppContext} from '../contexts/WorkspaceEditorAppContext'
import type {FocusedGenerativeTaskData, WorkspaceEditorRoutePayload} from '../utilities/workspace-editor-types'
import {useClassifyComments} from './use-classify-comments'
import {useGenerateFixQuery} from './use-generate-fix-query'

export function useGenerateFix(
  generateFixTask: FocusedGenerativeTaskData,
  commentsVersion: string,
  suggestionRequestId: string,
) {
  const {
    copilot: {ssoOrganizations, apiURL},
  } = useRoutePayload<WorkspaceEditorRoutePayload>()
  const {pullRequest} = useCurrentPullRequest()
  const repo = useCurrentRepository()
  const {blobService} = useWorkspaceEditorAppContext()

  const authTokenProvider = useRef(new CopilotAuthTokenProvider(ssoOrganizations.map(org => org.id)))
  const {
    data: blobData,
    refetch: fetchBlobData,
    isError: isErrorBlobData,
  } = useQuery({
    queryKey: ['blob-data', repo.ownerLogin, generateFixTask, pullRequest.number, repo.name, pullRequest.headSHA],
    queryFn: async () => {
      const response = await blobService.getBlob(
        generateFixTask.comment.path,
        repo.ownerLogin,
        pullRequest.number,
        repo.name,
        pullRequest.headSHA,
      )
      if (!response.ok) throw new Error('Failed to fetch blob data')
      return response.payload
    },
    retry: false,
    meta: {
      action: 'get-blob-data',
    },
  })

  const {
    commentClassification,
    refetch: refetchCommentClassification,
    isFetching: isClassifyingComments,
    isError: isErrorClassifyComments,
  } = useClassifyComments({
    apiURL,
    authTokenProvider: authTokenProvider.current,
    generateFixTask,
    repo,
    pullRequest,
    blobData,
    commentsVersion,
    suggestionRequestId,
    sourceId: generateFixTask.sourceId.toString(),
  })

  const {
    generatedFix,
    refetch: regenerateFix,
    isFetching: isGeneratingFix,
    isError: isErrorGenerateFix,
  } = useGenerateFixQuery({
    apiURL,

    authTokenProvider: authTokenProvider.current,
    generateFixTask,
    repo,
    pullRequest,
    blobData,
    commentsVersion,
    suggestionRequestId,
    sourceId: generateFixTask.sourceId.toString(),
    commentClassification,
  })

  const loadBlobData = useCallback(async () => {
    const fileData = (await fetchBlobData()).data
    if (!fileData || !fileData.blobContents) throw new Error('No blob data found, could not generate fix')

    return fileData
  }, [fetchBlobData])

  // todo: handle multiple files in patch?
  const parsedDiff = generatedFix ? parsePatch(generatedFix.gitPatch)[0] : undefined

  const hasError = isErrorBlobData || isErrorClassifyComments || isErrorGenerateFix
  const retryRequests = () => {
    if (isErrorBlobData) fetchBlobData()
    if (isErrorClassifyComments) refetchCommentClassification()
    if (isErrorGenerateFix) regenerateFix()
  }

  const regenerateClassificationAndFix = () => {
    refetchCommentClassification()
    regenerateFix()
  }

  return {
    blobData,
    generatedFix,
    generateFix: regenerateClassificationAndFix,
    isGeneratingFix,
    loadBlobData,
    parsedDiff,
    commentClassification,
    isClassifyingComments,
    hasError,
    retryRequests,
  }
}
