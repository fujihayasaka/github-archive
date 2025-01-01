import {useChatStateLens, useChatStateValue} from '@github-ui/copilot-chat/CopilotChatContext'
import {usePlugin} from '@github-ui/copilot-chat/plugin/registry'
import {usePreviousValue} from '@github-ui/use-previous-value'
import {createContext, useCallback, useContext, useEffect, useMemo, useState} from 'react'

import {useBooleanState} from '../../hooks/use-boolean-state'
import {
  type ItemsMap,
  type PreviewableContent,
  type PreviewableContentIdentifier,
  stripVersionFromId,
  type VersionedItemsMap,
} from './content-preview-types'

export interface ContentPreviewContext {
  /** All items by ID, regardless of visibility. */
  items: ItemsMap
  /**
   * Given a base ID, get all the versions associated with it. For unversioned items this will be a single-element
   * array. Versions are sorted by timestamp.
   */
  versionedItems: VersionedItemsMap
  /** Visible item IDs, in order. If empty, the pane is closed. */
  openItems: readonly PreviewableContentIdentifier[]
  /** Item IDs that were visible before switching subthreads. Used to restore open files after new subthread loads */
  openItemsBeforeSubthreadChange: readonly PreviewableContentIdentifier[]
  /** Message ids that existed in the thread when a subthread change happened */
  messagesBeforeSubthreadChange: string[]
  /** Currently selected item. */
  selectedItem: PreviewableContentIdentifier | undefined
  /** Whether the preview pane is open. */
  previewPaneOpen: boolean
  /** Whether the loading UI is visible */
  showLoadingState: boolean

  /** Add or update an item. */
  updateItem: (item: PreviewableContent) => void
  /** Set the items to restore after a subthread change. */
  setOpenItemsBeforeSubthreadChange: (items: readonly PreviewableContentIdentifier[]) => void
  /** Set the current messages in the thread when a subthread change is happening. */
  setMessagesBeforeSubthreadChange: (messages: string[]) => void
  /** Open the item, selecting it if specified. Does **not** open the pane if the pane is closed. */
  openItem: (id: PreviewableContentIdentifier, selectItem?: boolean) => void
  /** Close (hide) the item. */
  closeItem: (id: PreviewableContentIdentifier) => void
  /** Close the entire preview pane. Preserves open items for when reopened. */
  closePreviewPane: () => void
  /** Open the preview pane and restore any previously open items. */
  openPreviewPane: () => void
  /** Removes the items and openItems with the given IDs, or all if undefined  */
  removeItems: (ids?: PreviewableContentIdentifier[]) => void
  /** Shows the loading UI */
  enableLoadingState: () => void
  /** Hides the loading UI */
  disableLoadingState: () => void
}

export const ContentPreviewContext = createContext<ContentPreviewContext | undefined>(undefined)

const emptyItems: ItemsMap = new Map()
const emptyOpenItems: ContentPreviewContext['openItems'] = []

export function ContentPreviewProvider({children}: {children: React.ReactNode}) {
  const [items, setItems] = useState(emptyItems)
  const [openItems, setOpenItems] = useState(emptyOpenItems)
  const [openItemsBeforeSubthreadChange, setOpenItemsBeforeSubthreadChange] = useState(emptyOpenItems)
  const [messagesBeforeSubthreadChange, setMessagesBeforeSubthreadChange] = useState<string[]>([])
  const [selectedItem, setSelectedItem] = useState<PreviewableContentIdentifier | undefined>(undefined)
  const [previewPaneOpen, openPreviewPane, closePreviewPane] = useBooleanState(false)
  const [showLoadingState, enableLoadingState, disableLoadingState] = useBooleanState(false)
  const activePlugin = usePlugin(useChatStateValue('activePlugin'))

  const previousThreadId = usePreviousValue(useChatStateLens(s => s.selectedThreadID))
  const threadId = useChatStateLens(s => s.selectedThreadID)
  useEffect(() => {
    if (!previousThreadId || previousThreadId === threadId) return
    setItems(emptyItems)
    setOpenItems(emptyOpenItems)
    setSelectedItem(undefined)
    if (!activePlugin?.PreviewAreaComponent) closePreviewPane()
  }, [closePreviewPane, threadId, previousThreadId, activePlugin])

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
    if (selectItem) setSelectedItem(id)
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
      setOpenItems(prevOpenItems => prevOpenItems.filter(item => item !== id))
      if (selectedItem === id) {
        setSelectedItem(index > 0 ? openItems[index - 1] : openItems[0])
      }
    },
    [openItems, selectedItem],
  )

  const removeItems = useCallback((ids?: PreviewableContentIdentifier[]) => {
    if (ids) {
      for (const id of ids) {
        setItems(prevItems => {
          const newItems = new Map(prevItems)
          newItems.delete(id)
          return newItems
        })
        setOpenItems(prevOpenItems => prevOpenItems.filter(item => item !== id))
      }
    } else {
      setItems(emptyItems)
      setOpenItems(emptyOpenItems)
      setSelectedItem(undefined)
    }
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

  const value = useMemo(
    () => ({
      items,
      versionedItems,
      openItems: previewPaneOpen ? openItems : emptyOpenItems,
      openItemsBeforeSubthreadChange,
      messagesBeforeSubthreadChange,
      previewPaneOpen,
      selectedItem,
      updateItem,
      setOpenItemsBeforeSubthreadChange,
      setMessagesBeforeSubthreadChange,
      openItem,
      closeItem,
      openPreviewPane,
      closePreviewPane,
      removeItems,
      showLoadingState,
      enableLoadingState,
      disableLoadingState,
    }),
    [
      items,
      versionedItems,
      previewPaneOpen,
      openItems,
      openItemsBeforeSubthreadChange,
      messagesBeforeSubthreadChange,
      selectedItem,
      updateItem,
      setOpenItemsBeforeSubthreadChange,
      setMessagesBeforeSubthreadChange,
      openItem,
      closeItem,
      openPreviewPane,
      closePreviewPane,
      removeItems,
      showLoadingState,
      enableLoadingState,
      disableLoadingState,
    ],
  )

  return <ContentPreviewContext.Provider value={value}>{children}</ContentPreviewContext.Provider>
}

export function useContentPreview() {
  const context = useContext(ContentPreviewContext)
  if (!context) {
    throw new Error('useContentPreview must be used within ContentPreviewContextProvider')
  }
  return context
}
