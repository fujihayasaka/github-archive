import {useChatState} from '@github-ui/copilot-chat/CopilotChatContext'
import {useChatManager} from '@github-ui/copilot-chat/CopilotChatManagerContext'
import {referenceID} from '@github-ui/copilot-chat/utils/copilot-chat-helpers'
import type {CopilotChatReference} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {copilotFeatureFlags} from '@github-ui/copilot-chat/utils/copilot-feature-flags'
import safeStorage from '@github-ui/safe-storage'
import isEqual from 'lodash-es/isEqual'
import {useEffect, useRef} from 'react'

import {
  type ContentPreviewContext,
  type ItemsMap,
  makeReferenceFromVersionedItem,
  makeVersionedItemFromReference,
  type PreviewableContent,
  type PreviewableContentIdentifier,
  type VersionedPreviewableContent,
} from './content-preview-types'

const editedItemReferenceTypes: Array<CopilotChatReference['type']> = ['thread-scoped-file', 'draft-issue']

const isEditedItem = (item: PreviewableContent): item is VersionedPreviewableContent =>
  !!(item as {isUserEdited: boolean | undefined}).isUserEdited

const mapsEqual = (a: Map<unknown, unknown>, b: Map<unknown, unknown>) => {
  return a.size === b.size && Array.from(a).every(([k, v]) => isEqual(b.get(k), v))
}

const haveEditedItemReferencesChanged = (a: CopilotChatReference[], b: CopilotChatReference[]) => {
  const aContentsById = new Map(a.filter(r => editedItemReferenceTypes.includes(r.type)).map(r => [referenceID(r), r]))
  const bContentsById = new Map(b.filter(r => editedItemReferenceTypes.includes(r.type)).map(r => [referenceID(r), r]))
  return !mapsEqual(aContentsById, bContentsById)
}

const haveEditedItemsChanged = (a: ItemsMap, b: ItemsMap) => {
  const userEditedA = new Map(Array.from(a).filter(([, f]) => isEditedItem(f)))
  const userEditedB = new Map(Array.from(b).filter(([, f]) => isEditedItem(f)))
  return !mapsEqual(userEditedA, userEditedB)
}

/**
 * Keeps references in `CopilotChatState.currentReferences` synchronized with the user-edited
 * items in `ContentPreviewContext.items`. Either one might be updated independently, so this hook ensures the
 * two should always remain aligned.
 *
 * This logic is pretty messy, and doing it like this isn't really idiomatic React, but making this effect-based ensures
 * that we can never forget to update one state or the other across the dozens of callsites where we might make changes.
 *
 * Long-term, it would probably be better to resolve this somehow so that we only have one source of truth rather than
 * two. But that probably means rewriting all of `ContentPreviewContext`.
 */
export function useSyncEditedItemsWithCurrentReferences({items, removeItems, updateItem}: ContentPreviewContext) {
  const {currentReferences, messages, selectedThreadID} = useChatState()
  const manager = useChatManager()

  const previousItemsRef = useRef(items)
  const previousReferencesRef = useRef(currentReferences)
  const sessionStorage = safeStorage('sessionStorage')

  useEffect(() => {
    const itemsDidChange = haveEditedItemsChanged(previousItemsRef.current, items)
    previousItemsRef.current = items

    const referencesDidChange = haveEditedItemReferencesChanged(previousReferencesRef.current, currentReferences)
    previousReferencesRef.current = currentReferences

    // If both change at the same time (shouldn't happen) we will use ContentPreviewContext as the source of truth
    if (itemsDidChange) {
      // Update CopilotChatState.currentReferences to match ContentPreviewContext.items
      const itemReferences = Array.from(items.values())
        .filter(isEditedItem)
        .map(item => makeReferenceFromVersionedItem(item))
        .filter(item => item != null)

      const itemReferencesById = new Map(itemReferences.map(ref => [referenceID(ref), ref]))

      // Remove or update existing references
      const encounteredIds = new Set<string>()
      for (const currentReference of currentReferences) {
        if (editedItemReferenceTypes.includes(currentReference.type)) {
          const id = referenceID(currentReference)
          encounteredIds.add(id)

          const itemReference = itemReferencesById.get(id)

          if (!itemReference) {
            manager.removeReference(currentReference)
          } else if (haveEditedItemReferencesChanged([itemReference], [currentReference])) {
            manager.addReference(itemReference, 'content-preview')
          }
        }
      }

      // Add new references
      for (const [id, itemReference] of itemReferencesById)
        if (!encounteredIds.has(id)) manager.addReference(itemReference, 'content-preview')
    } else if (referencesDidChange) {
      // Update ContentPreviewContext.items to match CopilotChatState.currentReferences

      // Note this is essentially the exact same logic as the other case, but everything is reversed
      const referenceItems = currentReferences
        .map(ref => makeVersionedItemFromReference({ref, messageIndex: messages.length}))
        .filter(item => item != null)

      const referenceItemsById = new Map(referenceItems.map(item => [item.id, item]))

      // Remove or update existing items
      const encounteredIds = new Set<PreviewableContentIdentifier>()
      for (const [id, currentItem] of items) {
        if (isEditedItem(currentItem)) {
          encounteredIds.add(id)

          const referenceItem = referenceItemsById.get(id as (typeof currentItem)['id'])
          if (referenceItem != null) {
            const hasChanged = haveEditedItemsChanged(
              new Map([[referenceItem.id, referenceItem]]),
              new Map([[currentItem.id, currentItem]]),
            )
            if (hasChanged) updateItem(referenceItem)
          } else {
            removeItems([id])
            if (copilotFeatureFlags.copilotPersistEditedDraftIssues) {
              sessionStorage.removeItem(`edited-${selectedThreadID}-${id}`)
            }
          }
        }
      }

      // Add new items
      for (const [id, referenceItem] of referenceItemsById) if (!encounteredIds.has(id)) updateItem(referenceItem)
    }
  }, [items, manager, currentReferences, messages.length, removeItems, updateItem, sessionStorage, selectedThreadID])
}
