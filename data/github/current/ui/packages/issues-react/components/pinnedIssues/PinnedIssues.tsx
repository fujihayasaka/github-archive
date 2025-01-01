import {DragAndDrop, type OnDropArgs} from '@github-ui/drag-and-drop'
import {useContainerBreakpoint} from '@github-ui/use-container-breakpoint'
// eslint-disable-next-line no-restricted-imports
import {useToastContext} from '@github-ui/toast/ToastContext'

import {useCallback, useEffect, useRef, useState} from 'react'
import {graphql} from 'relay-runtime'
import {useFragment, useRelayEnvironment} from 'react-relay'

import {PinnedIssue} from './PinnedIssue'
import {commitPrioritizePinnedIssuesMutation} from '../../mutations/prioritize-pinned-issues-mutation'
import {ERRORS} from '../../constants/errors'
import type {PinnedIssues$data, PinnedIssues$key} from './__generated__/PinnedIssues.graphql'

import styles from './PinnedIssues.module.css'

type PinnedIssuesProps = {
  repository: PinnedIssues$key
}

export function PinnedIssues({repository}: PinnedIssuesProps) {
  const data = useFragment(
    graphql`
      fragment PinnedIssues on Repository {
        id
        pinnedIssues(first: 3) {
          nodes {
            id
            issue {
              id
              title
              ...PinnedIssueIssue
            }
          }
          totalCount
        }
        viewerCanPinIssues
      }
    `,
    repository,
  )

  const getPinnedIssues = useCallback((pinnedIssuesData: PinnedIssues$data['pinnedIssues']) => {
    return (pinnedIssuesData?.nodes || [])
      .flatMap(item => {
        if (!item?.issue) return []
        return item
      })
      .map(item => {
        return {
          title: item.issue.title,
          id: item.issue.id,
          data: item,
        }
      })
  }, [])

  const [items, setItems] = useState(() => getPinnedIssues(data.pinnedIssues))

  useEffect(() => {
    if (data.pinnedIssues) {
      setItems(() => getPinnedIssues(data.pinnedIssues))
    }
  }, [data.pinnedIssues, getPinnedIssues])

  const environment = useRelayEnvironment()
  const {addToast} = useToastContext()

  const onDrop = useCallback(
    ({dragMetadata, dropMetadata, isBefore}: OnDropArgs<string>) => {
      if (dragMetadata.id === dropMetadata?.id) return

      const dragItem = items.find(item => item.id === dragMetadata.id)
      if (!dragItem) return

      const orderedIssues = items.reduce(
        (newItems, item) => {
          if (dragItem.id === item.id) return newItems

          if (item.id !== dropMetadata?.id) {
            newItems.push(item)
          } else if (isBefore) {
            newItems.push(dragItem, item)
          } else {
            newItems.push(item, dragItem)
          }

          return newItems
        },
        [] as typeof items,
      )

      setItems(orderedIssues)
      const orderedIssueIds = orderedIssues.map(item => item.id)

      commitPrioritizePinnedIssuesMutation({
        environment,
        input: {repositoryId: data.id, issueIds: orderedIssueIds},
        onCompleted: () => {},
        onError: () => {
          setItems(items)
          // eslint-disable-next-line @github-ui/dotcom-primer/toast-migration
          addToast({
            type: 'error',
            message: ERRORS.couldNotReorderPinnedIssues,
          })
        },
      })
    },
    [addToast, data.id, environment, items],
  )

  const scrollContainerRef = useRef<HTMLDivElement | null>(null)

  const breakpoint = useContainerBreakpoint(scrollContainerRef.current)
  if ((data.pinnedIssues?.totalCount || 0) < 1) return null

  const onlySinglePinnedIssue = items.length === 1

  return (
    <div ref={scrollContainerRef}>
      <DragAndDrop
        items={items}
        onDrop={onDrop}
        className={styles.area}
        direction={breakpoint(['vertical', 'vertical', 'horizontal'])}
        aria-label="Drag and drop pinned issues list."
        renderOverlay={(item, index) => (
          <DragAndDrop.Item
            index={index}
            id={item.id}
            key={item.id}
            title={item.title}
            hideSortableItemTrigger={!data.viewerCanPinIssues}
            className={styles.container}
            style={{
              display: data.viewerCanPinIssues ? 'grid' : undefined,
              alignItems: 'start',
              gridTemplateColumns: onlySinglePinnedIssue ? '0px 1fr' : '24px 1fr',
              gap: 2,
            }}
            isDragOverlay
          >
            <PinnedIssue issue={item.data.issue} />
          </DragAndDrop.Item>
        )}
      >
        {items.map((item, index) => (
          <DragAndDrop.Item
            index={index}
            id={item.id}
            key={item.id}
            title={item.title}
            hideSortableItemTrigger={!data.viewerCanPinIssues}
            className={styles.container}
            style={{
              display: data.viewerCanPinIssues ? 'grid' : undefined,
              alignItems: 'start',
              gridTemplateColumns: onlySinglePinnedIssue ? '0px 1fr' : '24px 1fr',
              gap: 2,
            }}
          >
            <PinnedIssue issue={item.data.issue} />
          </DragAndDrop.Item>
        ))}
      </DragAndDrop>
    </div>
  )
}
