import type {Suggestions} from '@github-ui/inline-autocomplete/types'

import {type AgentsQuery, useAgentsSuggestions} from './useAgentsSuggestions'
import {type CategoriesQuery, useCategoriesSuggestions} from './useCategoriesSuggestions'
import {type DiscussionsQuery, useDiscussionsSuggestions} from './useDiscussionsSuggestions'
import {type FilesQuery, useFilesSuggestions} from './useFileSuggestions'
import {type IssuesQuery, useIssuesSuggestions} from './useIssuesSuggestions'
import {type PullRequestsQuery, usePullRequestsSuggestions} from './usePullRequestsSuggestions'
import {type RepositoriesQuery, useRepositoriesSuggestions} from './useRepositoriesSuggestions'
import {type SSOOrgsQuery, useSSOOrgsSuggestions} from './useSSOOrgsSuggestions'

export type AutocompleteQuery =
  | AgentsQuery
  | RepositoriesQuery
  | IssuesQuery
  | CategoriesQuery
  | PullRequestsQuery
  | DiscussionsQuery
  | FilesQuery
  | SSOOrgsQuery

export function useAutocompleteSuggestions(query: AutocompleteQuery | null): {
  suggestions: Suggestions | null
  stale: boolean
} {
  // Unfortunately we have to check the category twice because we can't conditionally call hooks. So we enable/disable
  // each query based on the category and then check the category again to determine which query to return.

  const categories = useCategoriesSuggestions(query?.category === 'categories' ? query : null)

  const agents = useAgentsSuggestions(query?.category === 'agents' ? query : null)

  const repositories = useRepositoriesSuggestions(query?.category === 'repositories' ? query : null)

  const issues = useIssuesSuggestions(query?.category === 'issues' ? query : null)

  const pulls = usePullRequestsSuggestions(query?.category === 'pulls' ? query : null)

  const discussions = useDiscussionsSuggestions(query?.category === 'discussions' ? query : null)

  const files = useFilesSuggestions(query?.category === 'files' ? query : null)

  const ssoOrgs = useSSOOrgsSuggestions(query?.category === 'sso-orgs' ? query : null)

  switch (query?.category) {
    case undefined:
      return {suggestions: null, stale: false}
    case 'categories':
      return {suggestions: categories, stale: false}
    case 'repositories':
      return repositories
    case 'issues':
      return issues
    case 'agents':
      return {suggestions: agents, stale: false}
    case 'discussions':
      return discussions
    case 'pulls':
      return pulls
    case 'files':
      return files
    case 'sso-orgs':
      return {suggestions: ssoOrgs, stale: false}
  }
}
