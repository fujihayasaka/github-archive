import {debounce} from '@github/mini-throttle'
import {announce} from '@github-ui/aria-live'

import {DragAndDropResources} from './strings'
import {type DragAndDropItem, DragAndDropMoveOptions} from './types'

const emptyAnnouncement = () => ''

/**
 * Announces a message to screen readers at a slowed-down rate. This is useful when you want to announce
 * drag and drop movements to screen readers but you don't want to overwhelm the user with too many announcements
 * in rapid succession. Do not use this function if interactions that trigger announcements do not happen rapidly.
 */
export const debounceAnnouncement = debounce((announcement: string) => {
  announce(announcement, {assertive: true})
}, 100)

/*
 * When passed into dnd-kit's DNDContext default announcements will be turned off.
 * This is useful and should only be used when you want to provide your own announcements.
 */
export const defaultAnnouncementsOff = {
  onDragStart: emptyAnnouncement,
  onDragOver: emptyAnnouncement,
  onDragMove: emptyAnnouncement,
  onDragEnd: emptyAnnouncement,
  onDragCancel: emptyAnnouncement,
}

export function successfulMoveDialogAnnouncement({
  newIndex,
  items,
  title,
  ...rest
}: {
  newIndex: number
  currentIndex: number
  items: DragAndDropItem[]
  title: string
  moveAction: DragAndDropMoveOptions
}) {
  const itemBeforeTitle = items[newIndex - 1]?.title
  const itemAfterTitle = items[newIndex + 1]?.title

  const message = getMoveDialogMessage({
    equalMessage: DragAndDropResources.successfulNoMove(title),
    firstPositionMessage: DragAndDropResources.successfulFirstMove(title),
    lastPositionMessage: DragAndDropResources.successfulLastMove(title),
    betweenBeforeMessage: DragAndDropResources.successfulMove(title, itemBeforeTitle, items[newIndex]?.title),
    betweenAfterMessage: DragAndDropResources.successfulMove(title, items[newIndex]?.title, itemAfterTitle),
    newIndex,
    items,
    ...rest,
  })

  announce(message, {assertive: true})
}

export function getMoveDialogMessage({
  equalMessage,
  firstPositionMessage,
  lastPositionMessage,
  betweenBeforeMessage,
  betweenAfterMessage,
  newIndex,
  currentIndex,
  items,
  moveAction,
}: {
  equalMessage: string
  firstPositionMessage: string
  lastPositionMessage: string
  betweenBeforeMessage: string
  betweenAfterMessage: string
  newIndex: number
  currentIndex: number
  items: DragAndDropItem[]
  moveAction: DragAndDropMoveOptions
}) {
  if (newIndex === currentIndex) {
    return equalMessage
  } else if (newIndex === 0 && moveAction !== DragAndDropMoveOptions.AFTER) {
    return firstPositionMessage
  } else if (newIndex === items.length - 1 && moveAction !== DragAndDropMoveOptions.BEFORE) {
    return lastPositionMessage
  } else {
    switch (moveAction) {
      case DragAndDropMoveOptions.BEFORE:
        return betweenBeforeMessage
      case DragAndDropMoveOptions.AFTER:
        return betweenAfterMessage
      case DragAndDropMoveOptions.ROW:
        if (newIndex < currentIndex) {
          return betweenBeforeMessage
        } else {
          return betweenAfterMessage
        }
    }
  }
}

export function successfulMoveAnnouncement({
  newIndex,
  currentIndex,
  items,
  title,
}: {
  newIndex: number
  currentIndex: number
  items: DragAndDropItem[]
  title: string
}) {
  const itemIds = items.map(item => item.id)
  if (newIndex === currentIndex) {
    announce(DragAndDropResources.successfulNoMove(title), {assertive: true})
  } else if (newIndex === 0) {
    announce(DragAndDropResources.successfulFirstMove(title), {assertive: true})
  } else if (newIndex === items.length - 1) {
    announce(DragAndDropResources.successfulLastMove(title), {assertive: true})
  } else {
    const isBefore = newIndex <= currentIndex
    const itemA = isBefore ? itemIds[newIndex - 1] : itemIds[newIndex + 1]
    const itemB = itemIds[newIndex]
    const itemATitle = items.find(item => item.id === itemA)?.title ?? ''
    const itemBTitle = items.find(item => item.id === itemB)?.title ?? ''

    announce(DragAndDropResources.successfulMove(title, itemATitle, itemBTitle), {assertive: true})
  }
}
