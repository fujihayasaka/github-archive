import type {Suggestions} from '@github-ui/inline-autocomplete/types'
import {useQuery} from '@github-ui/react-query'
import {useMemo} from 'react'

import {useChatManager} from '../../utils/CopilotChatManagerContext'
import {ReferenceMention} from '../../utils/reference-mention'
import {IssueSuggestion} from './IssueSuggestion'
import {useDebouncedFilterQuery} from './use-debounced-filter-query'

export interface IssuesQuery {
  category: 'issues'
  repository: string
  filter: string
}

export function useIssuesSuggestions(query: IssuesQuery | null) {
  const {service} = useChatManager()

  const debouncedQuery = useDebouncedFilterQuery(query)
  const isDebouncing = query !== debouncedQuery

  const issuesQuery = useQuery({
    enabled: debouncedQuery !== null,
    queryKey: ['copilot-autocomplete-issues', debouncedQuery?.repository, debouncedQuery?.filter],
    queryFn: async () => service.fetchAutocompleteIssues(debouncedQuery!.repository, debouncedQuery!.filter),
    placeholderData: prev => prev,
  })

  const suggestions = useMemo<Suggestions | null>(() => {
    if (!debouncedQuery) return null

    if (issuesQuery.isLoading) return 'loading'

    return (
      issuesQuery.data?.map(issue => ({
        value: ReferenceMention.stringify({
          type: 'issue',
          repo: debouncedQuery.repository,
          id: issue.number.toString(),
        }),
        key: issue.number.toString(),
        render: props => (
          <IssueSuggestion {...props} issue={issue} stale={issuesQuery.isPlaceholderData || isDebouncing} />
        ),
      })) ?? null
    )
  }, [debouncedQuery, issuesQuery.isLoading, issuesQuery.data, issuesQuery.isPlaceholderData, isDebouncing])

  return {suggestions, stale: issuesQuery.isPlaceholderData}
}
