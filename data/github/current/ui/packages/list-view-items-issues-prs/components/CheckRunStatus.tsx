import {ChecksStatusBadge} from '@github-ui/commit-checks-status'
import type {VariantType} from '@github-ui/list-view/ListViewVariantContext'
import {Box} from '@primer/react'
import {Suspense} from 'react'
import {type PreloadedQuery, usePreloadedQuery, useFragment, graphql} from 'react-relay'
import type {IssueRowSecondaryQuery} from './__generated__/IssueRowSecondaryQuery.graphql'
import type {PullRequestItemHeadCommit$key} from './__generated__/PullRequestItemHeadCommit.graphql'
import {IssuesIndexSecondaryGraphqlQuery} from './IssueRow'
import {PullRequestItemHeadCommitFragment} from './PullRequestItem'
import type {CheckRunStatus$data, CheckRunStatus$key} from './__generated__/CheckRunStatus.graphql'
import type {
  CheckRunStatusFromPullRequest$data,
  CheckRunStatusFromPullRequest$key,
} from './__generated__/CheckRunStatusFromPullRequest.graphql'
import {useFeatureFlags} from '@github-ui/react-core/use-feature-flag'

export const CheckRunStatusFragment = graphql`
  fragment CheckRunStatus on Commit {
    statusCheckRollup {
      state
      contexts {
        checkRunCount
        checkRunCountsByState {
          count
          state
        }
      }
    }
  }
`

export const CheckRunStatusFromPullRequestFragment = graphql`
  fragment CheckRunStatusFromPullRequest on PullRequest {
    statusCheckRollup {
      state
      contexts {
        checkRunCount
        checkRunCountsByState {
          count
          state
        }
      }
    }
  }
`
export function CheckRunStatus({
  statusCheckRollup,
  variant,
}: {
  statusCheckRollup:
    | NonNullable<CheckRunStatus$data['statusCheckRollup']>
    | NonNullable<CheckRunStatusFromPullRequest$data['statusCheckRollup']>
  variant?: VariantType
}) {
  if (!statusCheckRollup) return null
  const checkRunTotalCount = statusCheckRollup.contexts?.checkRunCount
  const checkRunSuccessCount = statusCheckRollup.contexts?.checkRunCountsByState?.find(
    runCountByState => runCountByState.state === 'SUCCESS',
  )?.count
  const checkRunText = `${checkRunSuccessCount}/${checkRunTotalCount}`
  const statusRollup = statusCheckRollup.state.toLowerCase() || ''
  return (
    <Box as="span" sx={{display: 'inline-flex', alignItems: 'center', whiteSpace: 'nowrap', gap: 1, ml: 1}}>
      {' '}
      &middot; <ChecksStatusBadge disablePopover statusRollup={statusRollup} />
      <span>{variant === 'default' && checkRunText}</span>
    </Box>
  )
}

export function LazyCheckRunStatus({
  id,
  primaryQueryRef,
  secondaryQueryRef,
  variant,
}: {
  id: string
  primaryQueryRef?: CheckRunStatusFromPullRequest$key
  secondaryQueryRef?: PreloadedQuery<IssueRowSecondaryQuery> | null
  variant: VariantType
}) {
  if (!secondaryQueryRef && !primaryQueryRef) return null

  if (primaryQueryRef) {
    return <LazyCheckRunStatusFromPRInternal dataKey={primaryQueryRef} variant={variant} />
  }

  if (!secondaryQueryRef) return null

  return (
    <Suspense fallback={null}>
      <LazyCheckRunStatusFetched id={id} secondaryQueryRef={secondaryQueryRef} variant={variant} />
    </Suspense>
  )
}

function LazyCheckRunStatusFetched({
  id,
  secondaryQueryRef,
  variant,
}: {
  id: string
  secondaryQueryRef: PreloadedQuery<IssueRowSecondaryQuery>
  variant: VariantType
}) {
  const {nodes} = usePreloadedQuery<IssueRowSecondaryQuery>(IssuesIndexSecondaryGraphqlQuery, secondaryQueryRef)
  const prNode = nodes?.find(node => node?.id === id)
  const {pull_request_single_subscription} = useFeatureFlags()

  if (!prNode) return null

  return pull_request_single_subscription ? (
    <LazyCheckRunStatusFromPRInternal dataKey={prNode} variant={variant} />
  ) : (
    <LazyCheckRunStatusInternal secondaryDataKey={prNode} variant={variant} />
  )
}

function LazyCheckRunStatusInternal({
  secondaryDataKey,
  variant,
}: {
  secondaryDataKey: PullRequestItemHeadCommit$key
  variant: VariantType
}) {
  const data = useFragment(PullRequestItemHeadCommitFragment, secondaryDataKey)
  const statusCheckRollupData = useFragment<CheckRunStatus$key>(CheckRunStatusFragment, data.headCommit?.commit)

  if (!statusCheckRollupData?.statusCheckRollup) return null

  return <CheckRunStatus statusCheckRollup={statusCheckRollupData.statusCheckRollup} variant={variant} />
}

function LazyCheckRunStatusFromPRInternal({
  dataKey,
  variant,
}: {
  dataKey: CheckRunStatusFromPullRequest$key
  variant: VariantType
}) {
  const data = useFragment(CheckRunStatusFromPullRequestFragment, dataKey)

  if (!data?.statusCheckRollup) return null

  return <CheckRunStatus statusCheckRollup={data.statusCheckRollup} variant={variant} />
}
