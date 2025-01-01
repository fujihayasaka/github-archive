import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {reactFetchJSON} from '@github-ui/verified-fetch'
import {useQuery} from '@tanstack/react-query'

import {useCurrentPullRequest} from '../contexts/CurrentPullRequestProvider'
import {suggestionUrl} from '../utilities/urls'
import type {FocusedTaskData, WorkspaceEditorRoutePayload} from '../utilities/workspace-editor-types'

export function useSuggestion(focusedTaskId: number | null) {
  const {repo} = useRoutePayload<WorkspaceEditorRoutePayload>()
  const {pullRequest} = useCurrentPullRequest()

  const {data, isLoading, isError} = useQuery({
    queryKey: [repo.ownerLogin, repo.name, pullRequest.number, focusedTaskId, pullRequest.headSHA],
    queryFn: async () => {
      const response = await reactFetchJSON(
        suggestionUrl({
          owner: repo.ownerLogin,
          repo: repo.name,
          pullNumber: pullRequest.number,
          pullRequestReviewCommentId: focusedTaskId!.toString(),
        }),
        {
          method: 'GET',
        },
      )

      const serverPrSha = response.headers.get('X-Head-Sha')
      if (serverPrSha && serverPrSha !== pullRequest.headSHA) {
        throw new Error('Server PR SHA does not match client PR SHA')
      }
      const suggestion = (await response.json()) as FocusedTaskData

      return suggestion
    },
    enabled: !!focusedTaskId,
    retry: 10,
    retryDelay: attemptIndex => Math.min(200 * 2 ** attemptIndex, 30000),
  })

  return {
    suggestion: data,
    isLoading,
    isError,
  }
}
