import {GitHubAvatar} from '@github-ui/github-avatar'
import PreloadedQueryBoundary from '@github-ui/relay-preloaded-query-boundary'
import {LoadingSkeleton} from '@github-ui/skeleton/LoadingSkeleton'
import {ActionList, ActionMenu, Box, Label, RelativeTime, Text} from '@primer/react'
import {Suspense, useEffect, useState} from 'react'
import {graphql, type PreloadedQuery, useFragment, usePreloadedQuery, useQueryLoader} from 'react-relay'

import type {MarkdownEditHistoryViewer_comment$key} from './__generated__/MarkdownEditHistoryViewer_comment.graphql'
import type {MarkdownEditHistoryViewerQuery} from './__generated__/MarkdownEditHistoryViewerQuery.graphql'
import {CouldNotFindFallbackError} from './components/CouldNotFindFallbackError'
import {EditHistoryDialog} from './components/EditHistoryDialog'
import {LABELS} from './constants/labels'
import styles from './MarkdownEditHistoryViewer.module.css'

type MarkdownEditHistoryViewerProps = {
  editHistory?: MarkdownEditHistoryViewer_comment$key
}

export const MarkdownEditHistoryViewerGraphql = graphql`
  query MarkdownEditHistoryViewerQuery($id: ID!) {
    node(id: $id) {
      ... on Comment {
        includesCreatedEdit
        userContentEdits(first: 100) {
          totalCount
          edges {
            node {
              id
              editedAt
              deletedAt
              editor {
                avatarUrl
                login
              }
            }
          }
        }
      }
    }
  }
`

export function MarkdownEditHistoryViewer({editHistory}: MarkdownEditHistoryViewerProps) {
  const data = useFragment(
    graphql`
      fragment MarkdownEditHistoryViewer_comment on Comment {
        id
        viewerCanReadUserContentEdits
        lastEditedAt
      }
    `,
    editHistory,
  )

  const [isEditHistoryDialogOpen, setIsEditHistoryDialogOpen] = useState(false)
  const [selectedId, setSelectedId] = useState('')

  if (!data || !data.viewerCanReadUserContentEdits || !data.lastEditedAt) {
    return null
  }

  return (
    <Box sx={{display: 'flex'}}>
      <ActionMenu>
        <ActionMenu.Button
          sx={{color: 'fg.muted'}}
          variant="invisible"
          size="small"
          aria-label={LABELS.editHistory.ariaLabel}
        >
          {LABELS.editHistory.openEditsButton}
        </ActionMenu.Button>
        <ActionMenu.Overlay width="auto">
          <EditHistoryActionMenuContent
            setIsEditHistoryDialogOpen={setIsEditHistoryDialogOpen}
            setSelectedId={setSelectedId}
            editHistoryId={data.id}
            lastEditedAt={data.lastEditedAt}
          />
        </ActionMenu.Overlay>
      </ActionMenu>
      {isEditHistoryDialogOpen && (
        <EditHistoryDialog onClose={() => setIsEditHistoryDialogOpen(false)} userContentEditId={selectedId} />
      )}
    </Box>
  )
}

type EditHistoryActionMenuContentProps = {
  editHistoryId: string
  lastEditedAt: string
} & SharedProps

const EditHistoryActionMenuContent = ({editHistoryId, lastEditedAt, ...props}: EditHistoryActionMenuContentProps) => {
  const [queryRef, loadEditHistory] = useQueryLoader<MarkdownEditHistoryViewerQuery>(MarkdownEditHistoryViewerGraphql)

  useEffect(() => {
    loadEditHistory({id: editHistoryId}, {fetchPolicy: 'network-only'})
    // Added `lastEditedAt` here to force an update if a new edit comes in
  }, [editHistoryId, loadEditHistory, lastEditedAt])

  if (!queryRef) return <EditHistoryLoading />

  return (
    <Suspense fallback={<EditHistoryLoading />}>
      <PreloadedQueryBoundary
        onRetry={() => loadEditHistory({id: editHistoryId}, {fetchPolicy: 'network-only'})}
        fallback={retry => <CouldNotFindFallbackError retry={retry} />}
      >
        <EditHistoryActionMenuContentInternal queryRef={queryRef} {...props} />
      </PreloadedQueryBoundary>
    </Suspense>
  )
}

type EditHistoryActionMenuContentInternalProps = {
  queryRef: PreloadedQuery<MarkdownEditHistoryViewerQuery>
} & SharedProps

type SharedProps = {
  setIsEditHistoryDialogOpen: (isOpen: boolean) => void
  setSelectedId: (id: string) => void
}

const EditHistoryActionMenuContentInternal = ({
  setIsEditHistoryDialogOpen,
  setSelectedId,
  queryRef,
}: EditHistoryActionMenuContentInternalProps) => {
  const data = usePreloadedQuery<MarkdownEditHistoryViewerQuery>(MarkdownEditHistoryViewerGraphql, queryRef)

  if (!data.node?.userContentEdits) return <EditHistoryLoading />
  const totalCount = data.node.userContentEdits.totalCount

  return (
    <ActionList sx={{maxHeight: 'clamp(200px, 30vh, 320px)', overflow: 'auto', width: 'max-content'}}>
      <ActionList.Group>
        <ActionList.GroupHeading>{`Edited ${totalCount - 1} time${totalCount > 2 ? 's' : ''}`}</ActionList.GroupHeading>
        {data.node.userContentEdits.edges?.map((edge, index) => {
          const edit = edge?.node
          if (!edit?.editor) {
            return null
          }

          const isCreation = data.node?.includesCreatedEdit && index === totalCount - 1

          return (
            <ActionList.Item
              key={edit.id}
              onSelect={() => {
                setSelectedId(edit.id)
                setIsEditHistoryDialogOpen(true)
              }}
            >
              <ActionList.LeadingVisual>
                <GitHubAvatar
                  src={edit.editor.avatarUrl}
                  size={16}
                  alt={`@${edit.editor.login}`}
                  sx={{boxShadow: '0 0 0 2px var(--bgColor-muted, var(--color-canvas-subtle))'}}
                />
              </ActionList.LeadingVisual>
              <Text sx={{fontWeight: 'normal'}}>{edit.editor.login}</Text>
              <ActionList.Description truncate className={styles.ActionList_Description}>
                {isCreation && <div title="">{LABELS.editHistory.created}</div>}
                <RelativeTime date={new Date(edit.editedAt)} />
              </ActionList.Description>
              {(index === 0 || edit.deletedAt) && (
                <ActionList.TrailingVisual>
                  <Label>{index === 0 ? LABELS.editHistory.mostRecent : LABELS.editHistory.deleted}</Label>
                </ActionList.TrailingVisual>
              )}
            </ActionList.Item>
          )
        })}
      </ActionList.Group>
    </ActionList>
  )
}

function EditHistoryLoading() {
  return (
    <Box sx={{m: 2, display: 'flex', flexDirection: 'column', gap: 2, minWidth: '256px'}}>
      <LoadingSkeleton variant="rounded" height="md" width="100%" />
      <LoadingSkeleton variant="rounded" height="md" width="100%" />
      <LoadingSkeleton variant="rounded" height="md" width="100%" />
      <LoadingSkeleton variant="rounded" height="md" width="100%" />
    </Box>
  )
}
