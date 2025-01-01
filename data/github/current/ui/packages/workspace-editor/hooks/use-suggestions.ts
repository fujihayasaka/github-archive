import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {useQuery} from '@github-ui/react-query'
import {reactFetchJSON} from '@github-ui/verified-fetch'

import {useCurrentPullRequest} from '../contexts/CurrentPullRequestProvider'
import {suggestionsUrl} from '../utilities/urls'
import type {SuggestionCommentData, WorkspaceEditorRoutePayload} from '../utilities/workspace-editor-types'

export function useSuggestions() {
  const payload = useRoutePayload<WorkspaceEditorRoutePayload>()
  const {repo} = payload
  const {pullRequest} = useCurrentPullRequest()

  const {
    isError,
    isLoading: isLoadingSuggestions,
    data: suggestionMap,
    refetch: refetchSuggestions,
    isFetched: areSuggestionsFetched,
  } = useQuery({
    queryKey: ['get-suggestions', repo.ownerLogin, repo.name, pullRequest.number, pullRequest.headSHA],
    queryFn: async () => {
      const response = await reactFetchJSON(
        suggestionsUrl({
          owner: repo.ownerLogin,
          repo: repo.name,
          pullNumber: pullRequest.number,
        }),
        {
          method: 'GET',
        },
      )

      const serverPrSha = response.headers.get('X-Head-Sha')
      if (serverPrSha && serverPrSha !== pullRequest.headSHA) {
        throw new Error('Server PR SHA does not match client PR SHA')
      }
      return (await response.json()) as SuggestionCommentData
    },
    meta: {action: 'get-suggestions'},
    retry: 10,
    retryDelay: attemptIndex => Math.min(200 * 2 ** attemptIndex, 30000),
  })

  return {
    isLoadingSuggestions,
    isError,
    suggestionMap,
    refetchSuggestions,
    areSuggestionsFetched,
  }
}
