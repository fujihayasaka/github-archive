import {graphql, useFragment, useRelayEnvironment} from 'react-relay'
import {clsx} from 'clsx'
import {NestedListView} from '@github-ui/nested-list-view'
import {NestedListViewHeader} from '@github-ui/nested-list-view/NestedListViewHeader'
import {NestedListViewHeaderTitle} from '@github-ui/nested-list-view/NestedListViewHeaderTitle'
import {NestedListViewCompletionPill} from '@github-ui/nested-list-view/NestedListViewCompletionPill'
import {BetaLabel} from '@github-ui/lifecycle-labels/beta'
import {ObservableBox} from '@github-ui/use-sticky-header/ObservableBox'
import {useStickyHeader} from '@github-ui/use-sticky-header/useStickyHeader'

import {SubIssuesListItem} from './SubIssuesListItem'
import styles from './SubIssuesListView.module.css'
import type {SubIssuesListView$key} from './__generated__/SubIssuesListView.graphql'
import type {OnDropArgs} from '@github-ui/drag-and-drop'
import {reprioritizeSubIssueMutation} from '../mutations/reprioritize-sub-issue-mutation'
import {useCallback} from 'react'
// eslint-disable-next-line no-restricted-imports
import {useToastContext} from '@github-ui/toast/ToastContext'
import {useSubIssuesSummary} from '../utils/use-sub-issues-summary'
import type {SubIssueSidePanelItem} from '../types/sub-issue-types'
import {SubIssuesListLoadingSkeleton} from './SubIssuesListLoadingSkeleton'

const SubIssuesListViewGraphQLFragment = graphql`
  fragment SubIssuesListView on Issue {
    id
    repository {
      name
    }
    subIssues(first: 100) {
      nodes {
        id
        ...SubIssuesListItem
      }
    }
    ...useSubIssuesSummary @arguments(fetchSubIssues: true)
  }
`

type ReprioritizeSubIssueParams = {
  issueId: string
  dragIssueId: string
  dropIssueId: string
  isBefore: boolean
}

export function SubIssuesListView({
  onSubIssueClick,
  issueKey,
  readonly = false,
}: {
  /** Callback called when a sub-issue is clicked */
  onSubIssueClick?: (subIssueItem: SubIssueSidePanelItem) => void
  issueKey?: SubIssuesListView$key
  readonly?: boolean
}) {
  const data = useFragment(SubIssuesListViewGraphQLFragment, issueKey)
  const environment = useRelayEnvironment()
  const {addToast} = useToastContext()

  const reprioritizeSubIssue = useCallback(
    ({issueId, dragIssueId, dropIssueId, isBefore}: ReprioritizeSubIssueParams) => {
      reprioritizeSubIssueMutation({
        environment,
        input: {
          issueId,
          subIssueId: dragIssueId,
          [isBefore ? 'beforeId' : 'afterId']: dropIssueId,
        },
        onError: error => {
          // eslint-disable-next-line @github-ui/dotcom-primer/toast-migration
          addToast({
            type: 'error',
            message: error.message,
          })
        },
      })
    },
    [environment, addToast],
  )

  const progress = useSubIssuesSummary(data ?? undefined)
  const {isSticky, hasRoots, observe, unobserve} = useStickyHeader()

  if (!data) {
    return <SubIssuesListLoadingSkeleton />
  }

  return (
    <NestedListView
      isReadOnly={readonly}
      title="Sub-issues"
      singularUnits="Issue"
      pluralUnits="Issues"
      header={
        <NestedListViewHeader
          title={<NestedListViewHeaderTitle title="Sub-issues" scrollToOnCollapseOffset={isSticky ? -52 : undefined} />}
          className={clsx(styles.container, isSticky && hasRoots && styles.stickyHeader)}
          completionPill={<NestedListViewCompletionPill progress={progress} />}
        >
          <BetaLabel />
        </NestedListViewHeader>
      }
      isCollapsible
      dragAndDropProps={{
        onDrop: ({dragMetadata, dropMetadata, isBefore}: OnDropArgs<string>) => {
          if (dragMetadata.id === dropMetadata.id) {
            return
          }

          reprioritizeSubIssue({
            issueId: data.id,
            dragIssueId: dragMetadata.id,
            dropIssueId: dropMetadata.id,
            isBefore,
          })
        },
        renderOverlay: ({id}) => {
          const issueNode = data?.subIssues?.nodes?.find(issue => issue?.id === id)
          if (!issueNode) return <></>
          if (!data?.id) return <></>

          return (
            <NestedListView title={'overlay'} isReadOnly={readonly}>
              <SubIssuesListItem
                key={issueNode.id}
                issueKey={issueNode}
                parentRepoName={data?.repository?.name}
                parentIssueId={data?.id}
                onSubIssueClick={onSubIssueClick}
                dnd
                isDragOverlay
                readonly={readonly}
              />
            </NestedListView>
          )
        },
        items:
          data.subIssues?.nodes?.map(issueNode => {
            if (!issueNode || !issueNode?.id) return {id: '', title: '', node: null}
            return {
              id: issueNode.id,
              title: issueNode.id,
              node: issueNode,
            }
          }) || [],
      }}
    >
      <ObservableBox className={styles.observableBox} onObserve={observe} onUnobserve={unobserve} />
      {data.subIssues.nodes?.map(issueNode => {
        if (!issueNode) return null
        if (!data.id) return null
        return (
          <SubIssuesListItem
            key={issueNode.id}
            issueKey={issueNode}
            parentIssueId={data.id}
            parentRepoName={data?.repository?.name}
            onSubIssueClick={onSubIssueClick}
            dnd
            readonly={readonly}
          />
        )
      })}
    </NestedListView>
  )
}
