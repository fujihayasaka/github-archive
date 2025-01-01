import {clientSideRelayFetchQueryRetained} from '@github-ui/relay-environment'
import {IS_SERVER} from '@github-ui/ssr-utils'
import {useState, useEffect} from 'react'
import {useRelayEnvironment, useFragment} from 'react-relay'
import {graphql} from 'relay-runtime'
import type {
  IssueViewerSecondaryIssueData$data,
  IssueViewerSecondaryIssueData$key,
} from './__generated__/IssueViewerSecondaryIssueData.graphql'

import {IssueViewerSecondaryIssueDataFragment} from './IssueViewer'
import type {
  IssueViewerSecondaryViewQuery,
  IssueViewerSecondaryViewQuery$data,
} from './__generated__/IssueViewerSecondaryViewQuery.graphql'
import type {IssueViewerSecondaryViewQueryData$key} from './__generated__/IssueViewerSecondaryViewQueryData.graphql'
import type {
  IssueViewerSecondaryViewQueryRepoData$data,
  IssueViewerSecondaryViewQueryRepoData$key,
} from './__generated__/IssueViewerSecondaryViewQueryRepoData.graphql'
import {isFeatureEnabled} from '@github-ui/feature-flags'

type UseSecondaryQueryProps = {
  owner: string
  repo: string
  number: number
  markAsRead?: boolean
}

// When variables are added to this query, places that add the preload header for ISSUE_VIEWER_SECONDARY_VIEW_QUERY
// also need to be updated accordingly to ensure the queries match.
export const IssueViewerSecondaryGraphqlQuery = graphql`
  query IssueViewerSecondaryViewQuery(
    $repo: String!
    $owner: String!
    $number: Int!
    $markAsRead: Boolean = false
    $useNewTimeline: Boolean = false
    $customisedNotificationsEnabled: Boolean = true
  ) {
    repository(name: $repo, owner: $owner) {
      ...IssueViewerSecondaryViewQueryData
        @arguments(
          number: $number
          markAsRead: $markAsRead
          useNewTimeline: $useNewTimeline
          customisedNotificationsEnabled: $customisedNotificationsEnabled
        )
    }
  }
`

// This defines all of the data fetched in the secondary query
// We separate it into fragments based on the type of the data's parent (currently Issue and Repository)
export const IssueViewerSecondaryData = graphql`
  fragment IssueViewerSecondaryViewQueryData on Repository
  @argumentDefinitions(
    number: {type: "Int!"}
    markAsRead: {type: "Boolean", defaultValue: true}
    useNewTimeline: {type: "Boolean", defaultValue: false}
    customisedNotificationsEnabled: {type: "Boolean", defaultValue: true}
  ) {
    issue(number: $number, markAsRead: $markAsRead) {
      ...IssueViewerSecondaryIssueData
        @arguments(useNewTimeline: $useNewTimeline, customisedNotificationsEnabled: $customisedNotificationsEnabled)
    }
    ...IssueViewerSecondaryViewQueryRepoData
  }
`

export function useSecondaryQuery({
  owner,
  repo,
  number,
  markAsRead = true,
}: UseSecondaryQueryProps): [
  IssueViewerSecondaryIssueData$data | null | undefined,
  IssueViewerSecondaryViewQueryRepoData$data | null | undefined,
] {
  const environment = useRelayEnvironment()
  const [secondaryQueryData, setSecondaryQueryData] = useState<IssueViewerSecondaryViewQueryData$key | null>(null)
  const issues_react_new_timeline = isFeatureEnabled('issues_react_new_timeline')
  const customisedNotificationsEnabled = isFeatureEnabled('ISSUES_REACT_CUSTOMISE_NOTIFICATIONS_UI')

  useEffect(() => {
    if (!IS_SERVER) {
      clientSideRelayFetchQueryRetained<IssueViewerSecondaryViewQuery>({
        environment,
        query: IssueViewerSecondaryGraphqlQuery,
        variables: {
          owner,
          repo,
          number,
          markAsRead,
          useNewTimeline: issues_react_new_timeline,
          customisedNotificationsEnabled,
        },
      }).subscribe({
        next: (data: IssueViewerSecondaryViewQuery$data) => {
          setSecondaryQueryData(data.repository ?? null)
        },
      })
    }
  }, [customisedNotificationsEnabled, environment, issues_react_new_timeline, markAsRead, number, owner, repo])

  const secondaryData = useFragment(IssueViewerSecondaryData, secondaryQueryData)

  const secondaryIssueKey: IssueViewerSecondaryIssueData$key | undefined | null = secondaryData?.issue
  const secondaryRepoKey: IssueViewerSecondaryViewQueryRepoData$key | undefined | null = secondaryData

  const secondaryIssueData = useFragment(IssueViewerSecondaryIssueDataFragment, secondaryIssueKey)
  const secondaryRepoData = useFragment(
    graphql`
      fragment IssueViewerSecondaryViewQueryRepoData on Repository {
        # eslint-disable-next-line relay/must-colocate-fragment-spreads
        ...LazyContributorFooter
      }
    `,
    secondaryRepoKey,
  )

  return [secondaryIssueData, secondaryRepoData]
}
