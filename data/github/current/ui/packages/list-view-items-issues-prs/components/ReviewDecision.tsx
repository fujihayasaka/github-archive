import type {VariantType} from '@github-ui/list-view/ListViewVariantContext'
import {CheckCircleFillIcon, NoEntryFillIcon, XCircleFillIcon} from '@primer/octicons-react'
import {Box, Text} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'

import type {PullRequestReviewDecision} from './__generated__/IssuePullRequestDescription.graphql'
import {graphql, useFragment, usePreloadedQuery, type PreloadedQuery} from 'react-relay'
import type {IssueRowSecondaryQuery} from './__generated__/IssueRowSecondaryQuery.graphql'
import {Suspense} from 'react'
import {IssuesIndexSecondaryGraphqlQuery} from './IssueRow'
import type {PullRequestRowSecondary$key} from './__generated__/PullRequestRowSecondary.graphql'
import {PullRequestRowSecondaryFragment} from './PullRequestRow'
import type {ReviewDecision$key} from './__generated__/ReviewDecision.graphql'

export const ReviewDecisionFragment = graphql`
  fragment ReviewDecision on PullRequest {
    reviewDecision
  }
`

export function ReviewDecision({
  decision,
  variant = 'default',
}: {
  decision: PullRequestReviewDecision
  variant?: VariantType
}) {
  const reviewDecision = getStyledDecision(decision)
  if (!reviewDecision) return null

  return variant === 'default' ? (
    <Box sx={{whiteSpace: 'nowrap', display: 'inline-flex', alignItems: 'center', gap: 1, ml: 1}}>
      {' '}
      &middot;
      <Box as="span" sx={{display: 'inline-flex', alignItems: 'center', gap: 1}}>
        {reviewDecision}
      </Box>
    </Box>
  ) : (
    <Box sx={{whiteSpace: 'nowrap', display: 'inline-flex', alignItems: 'center', gap: 1, ml: 1}}>
      <span>&middot;</span>
      {reviewDecision}
    </Box>
  )
}

function getStyledDecision(decision: string) {
  const textStyle = {color: 'fg.muted', fontWeight: 'normal', fontSize: 0}
  switch (decision) {
    case 'APPROVED':
      return (
        <>
          <Octicon icon={CheckCircleFillIcon} size={12} sx={{color: 'success.fg'}} />{' '}
          <Text sx={textStyle}>Approved</Text>
        </>
      )
    case 'CHANGES_REQUESTED':
      return (
        <>
          <Octicon icon={XCircleFillIcon} size={12} sx={{color: 'danger.fg'}} />{' '}
          <Text sx={textStyle}>Changes requested</Text>
        </>
      )
    case 'REVIEW_REQUIRED':
      return (
        <>
          <Octicon icon={NoEntryFillIcon} size={12} sx={{color: 'attention.fg'}} />{' '}
          <Text sx={textStyle}>Review required</Text>
        </>
      )
    default:
      return null
  }
}

export function LazyReviewDecision({
  id,
  secondaryQueryRef,
  variant,
}: {
  id: string
  secondaryQueryRef?: PreloadedQuery<IssueRowSecondaryQuery> | null
  variant: VariantType
}) {
  if (!secondaryQueryRef) return null

  return (
    <Suspense fallback={null}>
      <LazyReviewDecisionFetched id={id} secondaryQueryRef={secondaryQueryRef} variant={variant} />
    </Suspense>
  )
}

function LazyReviewDecisionFetched({
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

  if (!prNode) return null

  return <LazyReviewDecisionInternal secondaryDataKey={prNode} variant={variant} />
}

function LazyReviewDecisionInternal({
  secondaryDataKey,
  variant,
}: {
  secondaryDataKey: PullRequestRowSecondary$key
  variant: VariantType
}) {
  const data = useFragment(PullRequestRowSecondaryFragment, secondaryDataKey)
  const reviewData = useFragment<ReviewDecision$key>(ReviewDecisionFragment, data)
  if (!reviewData?.reviewDecision) return null

  return <ReviewDecision decision={reviewData.reviewDecision} variant={variant} />
}
