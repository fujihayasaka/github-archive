import {ProgressCircle} from '@github-ui/progress-circle'
import {Link, Token} from '@primer/react'
import {Tooltip} from '@primer/react/next'
import {useFragment, usePreloadedQuery, type PreloadedQuery} from 'react-relay'
import {graphql} from 'relay-runtime'
import type {IssueRowSecondaryQuery} from './__generated__/IssueRowSecondaryQuery.graphql'
import {IssuesIndexSecondaryGraphqlQuery} from './IssueRow'
import {Suspense} from 'react'
import type {IssueItemSubIssuesSummary$key} from './__generated__/IssueItemSubIssuesSummary.graphql'
import styles from './IssueItemSubIssuesSummary.module.css'
import {ListItemTrailingBadge} from '@github-ui/list-view/ListItemTrailingBadge'

type Props = {
  metadataRef?: PreloadedQuery<IssueRowSecondaryQuery> | null
  issueId: string
  link: string
}

const subIssuesFragment = graphql`
  fragment IssueItemSubIssuesSummary on Issue {
    subIssuesSummary {
      completed
      percentCompleted
      total
    }
  }
`

export function IssueItemSubIssuesSummary({metadataRef, issueId, link}: Props) {
  if (!metadataRef) return null

  return (
    <Suspense fallback={null}>
      <SubIssuesSummaryFetched issueId={issueId} metadataRef={metadataRef} link={link} />
    </Suspense>
  )
}

type FetchedProps = {
  metadataRef: PreloadedQuery<IssueRowSecondaryQuery>
  issueId: string
  link: string
}

function SubIssuesSummaryFetched({metadataRef, issueId, link}: FetchedProps) {
  const {nodes} = usePreloadedQuery<IssueRowSecondaryQuery>(IssuesIndexSecondaryGraphqlQuery, metadataRef)
  const issueNode = nodes?.find(node => node?.id === issueId)

  if (!issueNode) return null

  return <SubIssuesSummaryInternal summaryKey={issueNode} link={link} />
}

type InternalProps = {
  summaryKey?: IssueItemSubIssuesSummary$key
  link: string
}

function SubIssuesSummaryInternal({summaryKey, link}: InternalProps) {
  const data = useFragment(subIssuesFragment, summaryKey)
  if (!data?.subIssuesSummary) return null

  const {total, completed, percentCompleted} = data.subIssuesSummary
  if (total === 0) return null

  return (
    <ListItemTrailingBadge title="sub-issues summary">
      <Tooltip text={`${percentCompleted}% completed`} type="description">
        <Link href={link} onKeyDown={e => e.stopPropagation()}>
          <Token
            className={styles.token}
            leadingVisual={() => (
              <ProgressCircle percentCompleted={percentCompleted} size={14} svgClassName={styles.progressCircle} />
            )}
            text={<span>{`${completed} / ${total}`}</span>}
          />
        </Link>
      </Tooltip>
    </ListItemTrailingBadge>
  )
}
