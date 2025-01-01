import type {CopilotChatMessage} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {Button} from '@primer/react'
import {useEffect, useMemo} from 'react'

import {
  type File,
  getEditedFiles,
  getRevisionNumber,
  makeItemFromThreadScopedFileReference,
} from './ContentPreview/content-preview-types'
import {useContentPreview} from './ContentPreview/ContentPreviewContext'
import styles from './TimelineEditEntry.module.css'

/**
 * Displays the little notice in the message list that a file has been edited.
 */
export function TimelineEditEntry({item, onUndo}: {item: File; onUndo?: () => void}) {
  const {openPreviewPane, openItem, versionedItems} = useContentPreview()
  const revision = getRevisionNumber(item.id, versionedItems)
  const name = revision === null ? item.name : `${item.name} - (v${revision})`

  return (
    <div>
      <span>You’ve edited </span>
      <Button
        className={styles.fileButton}
        onClick={() => {
          openItem(item.id)
          openPreviewPane()
        }}
        variant="link"
      >
        {name}
      </Button>
      {onUndo && (
        <>
          <span> - </span>
          <Button className={styles.undoButton} onClick={onUndo} variant="link">
            Undo
          </Button>
        </>
      )}
    </div>
  )
}

/**
 * Displays the timeline entries for the given message.
 */
export function TimelineEditEntriesForMessage({
  message,
  messageIndex,
}: {
  message: CopilotChatMessage
  messageIndex: number
}) {
  const {updateItem} = useContentPreview()

  const items = useMemo(() => {
    const references = message.references?.filter(r => r.type === 'thread-scoped-file')
    return (references ?? []).map(reference =>
      makeItemFromThreadScopedFileReference(reference, message.id, messageIndex, message.createdAt),
    )
  }, [message.createdAt, message.id, message.references, messageIndex])

  useEffect(() => {
    // register items with ContentPreviewContext so they have revisions
    for (const item of items) {
      updateItem(item)
    }
  }, [items, updateItem])

  return (
    <div className={styles.container}>
      {items.map(item => (
        <TimelineEditEntry key={item.name} item={item} />
      ))}
    </div>
  )
}

/**
 * Displays pending timeline edit entries that have not yet been attached to a message and sent.
 */
export function TimelineEditEntriesForCurrentEdits() {
  const {items, removeItems} = useContentPreview()
  const files = getEditedFiles(items)
  return (
    <div className={styles.container}>
      {files.map(file => (
        <TimelineEditEntry key={file.name} item={file} onUndo={() => removeItems([file.id])} />
      ))}
    </div>
  )
}
