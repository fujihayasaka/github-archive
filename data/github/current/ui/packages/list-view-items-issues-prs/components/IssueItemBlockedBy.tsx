import {useFragment, usePreloadedQuery, type PreloadedQuery} from 'react-relay'
import {graphql} from 'relay-runtime'
import type {IssueItemBlockedBy$key} from './__generated__/IssueItemBlockedBy.graphql'
import {Token} from '@primer/react'
import {BlockedIcon} from '@primer/octicons-react'
import styles from './IssueItem.module.css'
import type {IssueRowSecondaryQuery} from './__generated__/IssueRowSecondaryQuery.graphql'
import {Suspense} from 'react'
import {IssuesIndexSecondaryGraphqlQuery} from './IssueRow'
import {testIdProps} from '@github-ui/test-id-props'

type Props = {
  metadataRef?: PreloadedQuery<IssueRowSecondaryQuery> | null
  issueId: string
}

const issueBlockedByFragment = graphql`
  fragment IssueItemBlockedBy on Issue {
    state
    issueDependenciesSummary {
      blockedBy
    }
  }
`

export function IssueItemBlockedBy({metadataRef, issueId}: Props) {
  if (!metadataRef) return null

  return (
    <Suspense fallback={null}>
      <IssueItemBlockedByFetched issueId={issueId} metadataRef={metadataRef} />
    </Suspense>
  )
}

type FetchedProps = {
  metadataRef: PreloadedQuery<IssueRowSecondaryQuery>
  issueId: string
}

export function IssueItemBlockedByFetched({metadataRef, issueId}: FetchedProps) {
  const {nodes} = usePreloadedQuery<IssueRowSecondaryQuery>(IssuesIndexSecondaryGraphqlQuery, metadataRef)
  const issueNode = nodes?.find(node => node?.id === issueId)

  if (!issueNode) return null

  return <IssueItemBlockedByInternal blockedByKey={issueNode} />
}

function IssueItemBlockedByInternal({blockedByKey}: {blockedByKey?: IssueItemBlockedBy$key}) {
  const data = useFragment(issueBlockedByFragment, blockedByKey)

  if (data?.state === 'CLOSED') return null

  if (!data?.issueDependenciesSummary) return null

  const {blockedBy} = data.issueDependenciesSummary

  if (blockedBy === 0) return null

  return (
    <Token
      text="Blocked"
      leadingVisual={() => <BlockedIcon className="fgColor-danger" size={14} />}
      className={styles.token}
      {...testIdProps('blocked-by-token')}
    />
  )
}
