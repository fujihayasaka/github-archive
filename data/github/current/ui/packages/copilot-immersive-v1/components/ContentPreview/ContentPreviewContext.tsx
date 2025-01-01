import {useChatState, useChatStateLens} from '@github-ui/copilot-chat/CopilotChatContext'
import {copilotFeatureFlags} from '@github-ui/copilot-chat/utils/copilot-feature-flags'
import {usePreviousValue} from '@github-ui/use-previous-value'
import {getSessionStorageItemsForKeyPrefix} from '@github-ui/use-safe-storage/session-storage'
import {createContext, useCallback, useContext, useEffect, useMemo, useState} from 'react'

import {useBooleanState} from '../../hooks/use-boolean-state'
import {
  type ContentPreviewContext as ContentPreviewContextType,
  type DraftIssue,
  type ItemsMap,
  type PreviewableContent,
  type PreviewableContentIdentifier,
  stripVersionFromId,
} from './content-preview-types'
import {useSyncEditedItemsWithCurrentReferences} from './use-sync-items-with-current-references'

export type ContentPreviewContext = ContentPreviewContextType
export const ContentPreviewContext = createContext<ContentPreviewContext | undefined>(undefined)

const emptyItems: ItemsMap = new Map()
const emptyOpenItems: ContentPreviewContext['openItems'] = []

export function ContentPreviewProvider({children}: {children: React.ReactNode}) {
  const [items, setItems] = useState(emptyItems)
  const [openItems, setOpenItems] = useState(emptyOpenItems)
  const [openItemsBeforeSubthreadChange, setOpenItemsBeforeSubthreadChange] = useState(emptyOpenItems)
  const [selectedItem, setSelectedItem] = useState<PreviewableContentIdentifier | undefined>(undefined)
  const [previewPaneOpen, openPreviewPane, closePreviewPane] = useBooleanState(false)
  const [showLoadingState, enableLoadingState, disableLoadingState] = useBooleanState(false)

  const previousThreadId = usePreviousValue(useChatStateLens(s => s.selectedThreadID))
  const threadId = useChatStateLens(s => s.selectedThreadID)
  useEffect(() => {
    if (!previousThreadId || previousThreadId === threadId) return
    setItems(emptyItems)
    setOpenItems(emptyOpenItems)
    setSelectedItem(undefined)
    if (threadId === null) closePreviewPane()
  }, [closePreviewPane, threadId, previousThreadId])

  const openItem = useCallback((id: PreviewableContentIdentifier, selectItem: boolean = true) => {
    setOpenItems(prevVisibleItems => {
      // Item already visible, no-op
      if (prevVisibleItems.includes(id)) return prevVisibleItems

      // Only one version of an item can ever be open
      const unversionedId = stripVersionFromId(id)
      const replaceIndex = prevVisibleItems.findIndex(visibleItem => stripVersionFromId(visibleItem) === unversionedId)

      const newVisibleItems = [...prevVisibleItems]

      if (replaceIndex === -1) newVisibleItems.push(id)
      else newVisibleItems.splice(replaceIndex, 1, id)

      return newVisibleItems
    })

    setSelectedItem(prevSelectedItem =>
      // If we open a different version of the currently selected item, we must update the selected item or nothing will be selected
      selectItem || prevSelectedItem === undefined || stripVersionFromId(prevSelectedItem) === stripVersionFromId(id)
        ? id
        : prevSelectedItem,
    )
  }, [])

  const updateItem = useCallback((item: PreviewableContent) => {
    setItems(prevItems => {
      const newItems = new Map(prevItems)
      newItems.set(item.id, item)
      return newItems
    })
  }, [])

  const closeItem = useCallback(
    (id: PreviewableContentIdentifier) => {
      const index = openItems.indexOf(id)
      const newOpenItems = openItems.toSpliced(index, 1)
      if (selectedItem === id) setSelectedItem(newOpenItems[index - 1] ?? newOpenItems[0])
      setOpenItems(newOpenItems)
    },
    [openItems, selectedItem],
  )

  const closeAllItems = useCallback(() => {
    setOpenItems(emptyOpenItems)
    setSelectedItem(undefined)
  }, [])

  const versionedItems = useMemo(() => {
    const result = new Map<PreviewableContentIdentifier, PreviewableContentIdentifier[]>()

    // collect version sets
    for (const [versionedId, item] of items) {
      const unversionedId = stripVersionFromId(versionedId)
      const versions = result.get(unversionedId) ?? []
      versions.push(item.id)
      result.set(unversionedId, versions)
    }

    // sort each set
    for (const versions of result.values())
      versions.sort((idA, idB) => {
        const a = items.get(idA)!
        const b = items.get(idB)!
        return 'timestamp' in a && 'timestamp' in b ? a.timestamp.valueOf() - b.timestamp.valueOf() : 0
      })

    return result
  }, [items])

  const removeItems = useCallback(
    (ids?: PreviewableContentIdentifier[]) => {
      if (ids) {
        for (const id of ids) {
          setItems(prevItems => {
            const newItems = new Map(prevItems)
            // If the item was not found, return the previous items
            return newItems.delete(id) ? newItems : prevItems
          })

          // If this item is versioned and open, roll the user to the previous version. Otherwise, close the item
          if (openItems.includes(id)) {
            const unversionedId = stripVersionFromId(id)
            const versions = versionedItems.get(unversionedId)
            const versionIndex = versions?.indexOf(id) ?? -1
            const previousVersion = versions?.[versionIndex - 1]
            if (previousVersion) openItem(previousVersion, false)
            else closeItem(id)
          }
        }
      } else {
        setItems(emptyItems)
        setOpenItems(emptyOpenItems)
        setSelectedItem(undefined)
      }
    },
    [openItem, closeItem, versionedItems, openItems],
  )

  const value = useMemo(
    () => ({
      items,
      versionedItems,
      openItems: previewPaneOpen ? openItems : emptyOpenItems,
      openItemsBeforeSubthreadChange,
      previewPaneOpen,
      selectedItem,
      updateItem,
      setOpenItemsBeforeSubthreadChange,
      openItem,
      closeItem,
      openPreviewPane,
      closePreviewPane,
      removeItems,
      showLoadingState,
      enableLoadingState,
      disableLoadingState,
      closeAllItems,
    }),
    [
      items,
      versionedItems,
      previewPaneOpen,
      openItems,
      openItemsBeforeSubthreadChange,
      selectedItem,
      updateItem,
      openItem,
      closeItem,
      openPreviewPane,
      closePreviewPane,
      removeItems,
      showLoadingState,
      enableLoadingState,
      disableLoadingState,
      closeAllItems,
    ],
  )

  useEditedIssueWithSessionStorage(value)
  useSyncEditedItemsWithCurrentReferences(value)

  return <ContentPreviewContext.Provider value={value}>{children}</ContentPreviewContext.Provider>
}

const useEditedIssueWithSessionStorage = ({updateItem}: ContentPreviewContext) => {
  const {messagesLoading, selectedThreadID} = useChatState()
  const storageKeyPrefix = `edited-${selectedThreadID}`

  const editedIssues: DraftIssue[] = useMemo(() => {
    if (copilotFeatureFlags.copilotPersistEditedDraftIssues) {
      return getSessionStorageItemsForKeyPrefix(storageKeyPrefix) as DraftIssue[]
    } else {
      return []
    }
  }, [storageKeyPrefix])

  useEffect(() => {
    if (editedIssues && messagesLoading.state === 'loaded') {
      for (const editedIssue of editedIssues) {
        updateItem(editedIssue)
      }
    }
  }, [editedIssues, updateItem, messagesLoading.state])
}

export function useContentPreview() {
  const context = useContext(ContentPreviewContext)
  if (!context) {
    throw new Error('useContentPreview must be used within ContentPreviewContextProvider')
  }
  return context
}
