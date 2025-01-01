import {graphql, useFragment, usePreloadedQuery, type PreloadedQuery} from 'react-relay'
import {ListItemLeadingVisual} from '@github-ui/list-view/ListItemLeadingVisual'

import {TEST_IDS} from '../constants/test-ids'
import {getIssueStateIcon, getPullRequestStateIcon} from '../constants/stateIcon'
import type {
  IssuePullRequestStateIcon$data,
  IssuePullRequestStateIcon$key,
  PullRequestState,
} from './__generated__/IssuePullRequestStateIcon.graphql'
import type {IssueRowSecondaryQuery} from './__generated__/IssueRowSecondaryQuery.graphql'
import {Suspense, useMemo} from 'react'
import {IssuesIndexSecondaryGraphqlQuery} from './IssueRow'
import type {PullRequestRowSecondary$key} from './__generated__/PullRequestRowSecondary.graphql'
import {PullRequestRowSecondaryFragment} from './PullRequestRow'
import type {IssuePullRequestStateIconSecondary$key} from './__generated__/IssuePullRequestStateIconSecondary.graphql'
import {ICONS_VALUES} from '../constants/values'

export const IssuePullRequestStateIconSecondaryFragment = graphql`
  fragment IssuePullRequestStateIconSecondary on PullRequest {
    isInMergeQueue
  }
`

const stateIconFragment = graphql`
  fragment IssuePullRequestStateIcon on IssueOrPullRequest
  @argumentDefinitions(includeGitData: {type: "Boolean", defaultValue: true}) {
    __typename
    ... on Issue {
      state
      stateReason(enableDuplicate: true)
    }
    ... on PullRequest {
      isDraft
      isInMergeQueue @include(if: $includeGitData)
      pullRequestState: state
    }
  }
`

type IssuePullRequestStateIconProps = {
  id?: string
  dataKey: IssuePullRequestStateIcon$key
  metadataRef?: PreloadedQuery<IssueRowSecondaryQuery> | null
}

export function IssuePullRequestStateIcon({id, dataKey, metadataRef}: IssuePullRequestStateIconProps) {
  const data = useFragment(stateIconFragment, dataKey)

  if (data.__typename === 'PullRequest') {
    return data.isInMergeQueue === undefined ? (
      <LazyIssuePullRequestStateIcon id={id} data={data} metadataRef={metadataRef} />
    ) : (
      <IssuePullRequestStateIconInternal data={data} isInMergeQueue={data.isInMergeQueue} />
    )
  }

  return <IssuePullRequestStateIconInternal data={data} isInMergeQueue={false} />
}

function IssuePullRequestStateIconInternal({
  data,
  isInMergeQueue,
}: {
  data: IssuePullRequestStateIcon$data
  isInMergeQueue: boolean
}) {
  const defaultState = useMemo(() => getIssueStateIcon(null), [])
  let {icon, color, description} = defaultState

  if (data.__typename === 'PullRequest') {
    const state = getPullRequestEntityState(data.isDraft, isInMergeQueue, data.pullRequestState)
    const stateData = getPullRequestStateIcon(state)
    icon = stateData.icon
    color = stateData.color
    description = stateData.description
  }

  if (data.__typename === 'Issue') {
    const stateOrReason =
      data.state === 'CLOSED' && (data.stateReason === 'NOT_PLANNED' || data.stateReason === 'DUPLICATE')
        ? data.stateReason
        : data.state

    const state = getIssueStateIcon(stateOrReason)
    icon = state.icon
    color = state.color
    description = state.description
  }

  return (
    <ListItemLeadingVisual
      icon={icon}
      color={color}
      description={description}
      data-testid={TEST_IDS.listRowStateIcon}
    />
  )
}

function LazyIssuePullRequestStateIcon({
  data,
  metadataRef,
  id,
}: {
  id?: string
  data: IssuePullRequestStateIcon$data
  metadataRef?: PreloadedQuery<IssueRowSecondaryQuery> | null
}) {
  // No real need to check for __typename here, but the linter isnt able to detect that
  if (data.__typename !== 'PullRequest' || !metadataRef) {
    return <IssuePullRequestStateIconInternal data={data} isInMergeQueue={false} />
  }

  return (
    <Suspense fallback={<IssuePullRequestStateIconInternal data={data} isInMergeQueue={false} />}>
      <LazyIssuePullRequestStateIconFetched id={id} data={data} metadataRef={metadataRef} />
    </Suspense>
  )
}

function LazyIssuePullRequestStateIconFetched({
  id,
  data,
  metadataRef,
}: {
  id?: string
  data: IssuePullRequestStateIcon$data
  metadataRef: PreloadedQuery<IssueRowSecondaryQuery>
}) {
  const {nodes} = usePreloadedQuery<IssueRowSecondaryQuery>(IssuesIndexSecondaryGraphqlQuery, metadataRef)
  const prNode = nodes?.find(node => node?.id === id)

  return <LazyIssuePullRequestStateIconInternal data={data} secondaryDataKey={prNode} />
}

function LazyIssuePullRequestStateIconInternal({
  data,
  secondaryDataKey,
}: {
  data: IssuePullRequestStateIcon$data
  secondaryDataKey?: PullRequestRowSecondary$key | null
}) {
  const secondaryData = useFragment(PullRequestRowSecondaryFragment, secondaryDataKey)
  const isInMergeQueueData = useFragment<IssuePullRequestStateIconSecondary$key>(
    IssuePullRequestStateIconSecondaryFragment,
    secondaryData,
  )

  return <IssuePullRequestStateIconInternal data={data} isInMergeQueue={!!isInMergeQueueData?.isInMergeQueue} />
}

type PullRequestIcons = keyof typeof ICONS_VALUES.pullRequestIcons
type StateIcons = Extract<PullRequestIcons, PullRequestState>

function isStateInIcons(state: PullRequestState): state is StateIcons {
  return state in ICONS_VALUES.pullRequestIcons
}

export function getPullRequestEntityState(
  isDraft: boolean,
  isInMergeQueue: boolean,
  state: PullRequestState,
): PullRequestIcons {
  if (isInMergeQueue) {
    return 'IN_MERGE_QUEUE'
  }

  if (state === 'OPEN' && isDraft) {
    return 'DRAFT'
  }

  if (isStateInIcons(state)) {
    return state
  }

  throw new Error(`Invalid pull request state: ${state}`)
}
