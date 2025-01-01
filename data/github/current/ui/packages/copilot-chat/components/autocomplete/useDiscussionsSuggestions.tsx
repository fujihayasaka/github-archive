import type {Suggestions} from '@github-ui/inline-autocomplete/types'
import {useQuery} from '@github-ui/react-query'
import {useMemo} from 'react'

import {useChatManager} from '../../utils/CopilotChatManagerContext'
import {ReferenceMention} from '../../utils/reference-mention'
import {DiscussionSuggestion} from './DiscussionSuggestion'
import {useDebouncedFilterQuery} from './use-debounced-filter-query'

export interface DiscussionsQuery {
  category: 'discussions'
  filter: string
  repository: string
}

export function useDiscussionsSuggestions(query: DiscussionsQuery | null) {
  const {service} = useChatManager()

  const debouncedQuery = useDebouncedFilterQuery(query)
  const isDebouncing = query !== debouncedQuery

  const discussionsQuery = useQuery({
    enabled: debouncedQuery !== null,
    queryKey: ['copilot-autocomplete-discussions', debouncedQuery?.repository, debouncedQuery?.filter],
    queryFn: async () => service.fetchAutocompleteDiscussions(debouncedQuery!.repository, debouncedQuery!.filter),
    placeholderData: prev => prev,
  })

  const suggestions = useMemo<Suggestions | null>(() => {
    if (!debouncedQuery) return null

    if (discussionsQuery.isLoading) return 'loading'

    return (
      discussionsQuery.data?.map(discussion => ({
        value: ReferenceMention.stringify({
          type: 'discussion',
          repo: debouncedQuery.repository,
          id: discussion.number.toString(),
        }),
        key: discussion.number.toString(),
        render: props => (
          <DiscussionSuggestion
            {...props}
            discussion={discussion}
            stale={discussionsQuery.isPlaceholderData || isDebouncing}
          />
        ),
      })) ?? null
    )
  }, [
    discussionsQuery.data,
    discussionsQuery.isLoading,
    discussionsQuery.isPlaceholderData,
    debouncedQuery,
    isDebouncing,
  ])

  return {suggestions, stale: discussionsQuery.isPlaceholderData}
}
