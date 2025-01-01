/* eslint eslint-comments/no-use: off */
/* eslint-disable filenames/match-regex */

import {clientSideRelayFetchQueryRetained} from '@github-ui/relay-environment'
import {useDebounce} from '@github-ui/use-debounce'
import {useState, useCallback, useEffect, useMemo} from 'react'
import {graphql, useFragment, useRelayEnvironment} from 'react-relay'

import {VALUES} from '../constants/values'
import {getIssueSearchQueries} from '../shared'
import type {IssuePickerItem} from '../components/IssuePicker'
import type {useIssueFilteringQuery, useIssueFilteringQuery$data} from './__generated__/useIssueFilteringQuery.graphql'
import type {useIssueFilteringFragment$key} from './__generated__/useIssueFilteringFragment.graphql'

export const useIssueFilteringQueryGraphQLQuery = graphql`
  query useIssueFilteringQuery(
    $commenters: String!
    $mentions: String!
    $assignee: String!
    $author: String!
    $other: String!
    $first: Int = 10
    $resource: URI!
    $queryIsUrl: Boolean!
  ) {
    ...useIssueFilteringFragment
  }
`

const UseIssueFilteringGraphQLFragment = graphql`
  fragment useIssueFilteringFragment on Query {
    commenters: search(type: ISSUE, first: $first, query: $commenters) {
      nodes {
        ...IssuePickerIssue @relay(mask: false)
      }
    }
    mentions: search(type: ISSUE, first: $first, query: $mentions) {
      nodes {
        ...IssuePickerIssue @relay(mask: false)
      }
    }
    assignee: search(type: ISSUE, first: $first, query: $assignee) {
      nodes {
        ...IssuePickerIssue @relay(mask: false)
      }
    }
    author: search(type: ISSUE, first: $first, query: $author) {
      nodes {
        ...IssuePickerIssue @relay(mask: false)
      }
    }
    other: search(type: ISSUE, first: $first, query: $other) {
      nodes {
        ...IssuePickerIssue @relay(mask: false)
      }
    }
    # Do not return resource unless it is an Issue
    resource: resource(url: $resource) @include(if: $queryIsUrl) {
      ...IssuePickerIssue @relay(mask: false)
    }
  }
`

// Handles debouncing queries to fetch issues based on the current filter
export const useIssueFiltering = (
  filter: string,
  owner: string = '',
  repositoryNameWithOwner?: string,
  hiddenIssueIds?: string[],
): {
  isLoading: boolean
  isError: boolean
  items: Map<string, IssuePickerItem>
} => {
  const environment = useRelayEnvironment()

  const [isLoading, setIsLoading] = useState(true)
  const [isError, setIsError] = useState(false)
  const [data, setData] = useState<useIssueFilteringQuery$data | null>(null)

  const fetchSearchData = useCallback(
    (nextFilter: string) => {
      setIsLoading(true)
      clientSideRelayFetchQueryRetained<useIssueFilteringQuery>({
        environment,
        query: useIssueFilteringQueryGraphQLQuery,
        variables: getIssueSearchQueries(owner, nextFilter, repositoryNameWithOwner),
      }).subscribe({
        next: (innerData: useIssueFilteringQuery$data) => {
          setData(innerData ?? null)
          setIsLoading(false)
          setIsError(false)
        },
        error: () => {
          setIsError(true)
          setIsLoading(false)
        },
      })
    },
    [environment, owner, repositoryNameWithOwner],
  )

  const debounceFetchSearchData = useDebounce(
    (nextValue: string) => fetchSearchData(nextValue),
    VALUES.pickerDebounceTime,
  )

  useEffect(() => {
    debounceFetchSearchData(filter)
  }, [debounceFetchSearchData, filter])

  const issues = useFragment(UseIssueFilteringGraphQLFragment, data as useIssueFilteringFragment$key | null)

  const items: Map<string, IssuePickerItem> = useMemo(() => {
    if (!issues) {
      return new Map()
    } else {
      // When resource is returned, we only want to show that issue as the user's intent is to
      // select a specific issue otherwise, we show all the issues from the search queries
      if (issues.resource?.__typename === 'Issue') {
        return new Map([[issues.resource?.id, issues.resource]])
      }

      // Order the unique issues from each of the queries. Changing the order of this spread
      // will change the relative priority of each individual search query.
      const searchResultNodes = [
        ...(issues.commenters?.nodes || []),
        ...(issues.mentions?.nodes || []),
        ...(issues.assignee?.nodes || []),
        ...(issues.author?.nodes || []),
        ...(issues.other?.nodes || []),
      ]

      type searchResultNode = (typeof searchResultNodes)[0]

      const issueNodes = searchResultNodes.filter((node: searchResultNode): node is IssuePickerItem => {
        return node?.__typename === 'Issue'
      })

      const issuesMap = new Map<string, IssuePickerItem>()
      for (const issue of issueNodes) {
        if (hiddenIssueIds?.some(id => id === issue.id)) {
          continue
        }

        issuesMap.set(issue.id, issue)
      }

      return issuesMap
    }
  }, [hiddenIssueIds, issues])

  return {isLoading, isError, items}
}
