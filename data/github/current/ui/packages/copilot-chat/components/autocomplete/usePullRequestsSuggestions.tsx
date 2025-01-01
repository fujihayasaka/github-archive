import type {Suggestions} from '@github-ui/inline-autocomplete/types'
import {useQuery} from '@github-ui/react-query'
import {useMemo} from 'react'

import {useChatManager} from '../../utils/CopilotChatManagerContext'
import {ReferenceMention} from '../../utils/reference-mention'
import {PullRequestSuggestion} from './PullRequestSuggestion'
import {useDebouncedFilterQuery} from './use-debounced-filter-query'

export interface PullRequestsQuery {
  category: 'pulls'
  repository: string
  filter: string
}

export function usePullRequestsSuggestions(query: PullRequestsQuery | null) {
  const {service} = useChatManager()

  const debouncedQuery = useDebouncedFilterQuery(query)
  const isDebouncing = query !== debouncedQuery

  const pullRequestsQuery = useQuery({
    enabled: debouncedQuery !== null,
    queryKey: ['copilot-autocomplete-pulls', debouncedQuery?.repository, debouncedQuery?.filter],
    queryFn: async () => service.fetchAutocompletePullRequests(debouncedQuery!.repository, debouncedQuery!.filter),
    placeholderData: prev => prev,
  })

  const suggestions = useMemo<Suggestions | null>(() => {
    if (!debouncedQuery) return null

    if (pullRequestsQuery.isLoading) return 'loading'

    return (
      pullRequestsQuery.data?.map(pull => ({
        value: ReferenceMention.stringify({
          type: 'pull-request',
          repo: debouncedQuery.repository,
          id: pull.number.toString(),
        }),
        key: pull.number.toString(),
        render: props => (
          <PullRequestSuggestion
            {...props}
            pullRequest={pull}
            stale={pullRequestsQuery.isPlaceholderData || isDebouncing}
          />
        ),
      })) ?? null
    )
  }, [
    pullRequestsQuery.data,
    pullRequestsQuery.isLoading,
    pullRequestsQuery.isPlaceholderData,
    debouncedQuery,
    isDebouncing,
  ])

  return {suggestions, stale: pullRequestsQuery.isPlaceholderData}
}
