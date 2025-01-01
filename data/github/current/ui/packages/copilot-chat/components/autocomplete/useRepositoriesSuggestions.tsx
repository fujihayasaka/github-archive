import type {Suggestion, Suggestions} from '@github-ui/inline-autocomplete/types'
import {ActionList} from '@primer/react'
import {useMemo} from 'react'

import {useRepositoryItems} from '../../hooks/use-repository-items'
import type {TopicItem} from '../../utils/copilot-chat-types'
import {useChatState} from '../../utils/CopilotChatContext'
import {ReferenceMention} from '../../utils/reference-mention'
import {RepositorySuggestion} from './RepositorySuggestion'
import {SSOPromptSuggestion} from './SSOOrgSuggestion'
import {useDebouncedFilterQuery} from './use-debounced-filter-query'
import {ssoUrl} from './useSSOOrgsSuggestions'

export interface RepositoriesQuery {
  category: 'repositories'
  nextCategory?: 'issues' | 'pulls' | 'discussions' | 'files'
  filter: string
}

/**
 * Sorts repos in the set of selected repo IDs to the top of the list.
 */
const sortSelectedToTop = (selectedRepoIds: Set<number | string>) => (a: TopicItem, b: TopicItem) => {
  if (selectedRepoIds.has(a.databaseId) && !selectedRepoIds.has(b.databaseId)) return -1
  if (selectedRepoIds.has(b.databaseId) && !selectedRepoIds.has(a.databaseId)) return 1
  return 0
}

export function useRepositoriesSuggestions(query: RepositoriesQuery | null) {
  const {currentReferences} = useChatState()

  const debouncedQuery = useDebouncedFilterQuery(query)
  const isDebouncing = query !== debouncedQuery

  const {repositories, loading} = useRepositoryItems(debouncedQuery?.filter ?? '', debouncedQuery !== null)

  const selectedRepoIds = useMemo(
    () => new Set(currentReferences.filter(r => r.type === 'repository').map(r => r.id)),
    [currentReferences],
  )

  const {ssoOrganizations} = useChatState()

  const suggestions = useMemo<Suggestions | null>(() => {
    if (!debouncedQuery) return null

    if (loading === 'initial') return 'loading'

    const isMultistep = debouncedQuery.nextCategory !== undefined

    const results =
      repositories
        .toSorted(sortSelectedToTop(selectedRepoIds))
        .slice(0, 5)
        .map<Suggestion>(repo => ({
          value: isMultistep ? null : ReferenceMention.stringify({type: 'repository', repo: repo.nwo}),
          key: repo.nwo,
          render: props => (
            <RepositorySuggestion
              repository={repo}
              isMultistep={isMultistep}
              stale={!!loading || isDebouncing}
              {...props}
            />
          ),
        })) ?? []

    if (ssoOrganizations.length > 0)
      results.push({
        value: null,
        key: ssoOrganizations.length === 1 ? `open-link:${ssoUrl(ssoOrganizations[0]!)}` : 'sso-orgs',
        render: props => (
          <>
            <ActionList.Divider />
            <SSOPromptSuggestion orgs={ssoOrganizations} {...props} />
          </>
        ),
      })

    return results
  }, [repositories, loading, debouncedQuery, selectedRepoIds, ssoOrganizations, isDebouncing])

  return {suggestions, stale: loading === true}
}
