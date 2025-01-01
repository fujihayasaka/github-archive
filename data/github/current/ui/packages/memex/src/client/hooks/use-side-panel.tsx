import {useLocalStorage} from '@github-ui/use-safe-storage/local-storage'
import {useTrackingRef} from '@github-ui/use-tracking-ref'
import {useConfirm} from '@primer/react'
import {
  createContext,
  type Dispatch,
  memo,
  type ReactNode,
  type SetStateAction,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
} from 'react'
import {useBeforeUnload, useLocation} from 'react-router-dom'

import {SubIssueSidePanelItem} from '../api/memex-items/hierarchy'
import {ItemType} from '../api/memex-items/item-type'
import {type SidePanelItem, SidePanelTypeParam} from '../api/memex-items/side-panel-item'
import type {SuggestedRepository} from '../api/repository/contracts'
import {
  BulkAddSidePanelOpen,
  type BulkAddSidePanelOpenUIType,
  CommandPaletteUI,
  DraftOpen,
  SidePanelBoardOpen,
  SidePanelTableOpen,
} from '../api/stats/contracts'
import {useCommands} from '../commands/hook'
import {focusPrevious, useStableBoardNavigation} from '../components/board/navigation'
import type {OmnibarItemAttrs} from '../components/omnibar/types'
import {moveTableFocus, useStableTableNavigation} from '../components/react_table/navigation'
import useToasts, {ToastType} from '../components/toasts/use-toasts'
import {ViewerPrivileges} from '../helpers/viewer-privileges'
import {IssueModel, type MemexItemModel} from '../models/memex-item-model'
import {FocusType} from '../navigation/types'
import {ITEM_ID_PARAM, NWO_REFERENCE_PARAM, PANE_PARAM, STATUS_UPDATE_ID_PARAM} from '../platform/url'
import {useSearchParams} from '../router'
import {useMemexItems} from '../state-providers/memex-items/use-memex-items'
import {Resources} from '../strings'
import {usePostStats} from './common/use-post-stats'
import {useProjectViewRouteMatch} from './use-project-view-route-match'
import {useSidePanelItem} from './use-side-panel-item'

export type OpenSidePanelFn = (item: SidePanelItem, onClose?: () => void) => void

export type SidePanelContextValue = {
  sidePanelState: SidePanelState
  openProjectItemInPane: OpenSidePanelFn
  reloadPaneItem: () => void
  openPaneInfo: (statusUpdateId?: number) => void
  openPaneBulkAdd: (
    ui: BulkAddSidePanelOpenUIType,
    targetRepository?: SuggestedRepository,
    query?: string,
    newItemAttributes?: OmnibarItemAttrs,
  ) => void
  closePane: (opts?: {force?: boolean}) => Promise<boolean>
  dirtyItems: typeof defaultDirtyItems
  setDirtyItems: Dispatch<SetStateAction<typeof defaultDirtyItems>>
  hasUnsavedChanges: boolean
  isPaneOpened: boolean
  supportedItemTypes: Set<ItemType>
  openPaneHistoryItem: (item: HistoryItem) => void
  openPaneHierarchyHistoryItem: (item: HistoryItem) => void
  pinned: boolean
  setPinned: Dispatch<boolean>
  pinButtonRef: React.RefObject<HTMLButtonElement>
  initialFocusRef: React.RefObject<HTMLButtonElement>
  containerRef: React.RefObject<HTMLDivElement>
}

export type MemexItemSidePanelState = {
  type: typeof SidePanelTypeParam.ISSUE
  item: SidePanelItem
}

type MemexInfoSidePanelState = {
  type: typeof SidePanelTypeParam.INFO
}

type MemexBulkAddSidePanelState = {
  type: typeof SidePanelTypeParam.BULK_ADD
  targetRepository?: SuggestedRepository
  query?: string
  newItemAttributes?: OmnibarItemAttrs
}

export type HistoryItem = {
  historyIdx?: number
  item?: SidePanelItem
}

const supportedItemTypes = new Set<ItemType>([ItemType.DraftIssue, ItemType.Issue])

/**
 * @deprecated
 */
const DEPRECATED_SIDE_PANEL_PARAM = 'item'

export type SidePanelState = MemexItemSidePanelState | MemexInfoSidePanelState | MemexBulkAddSidePanelState | null

const infoTabState: MemexInfoSidePanelState = {type: SidePanelTypeParam.INFO}

function useClearParamsWhenNoVisibleItemForId({
  itemIdParam,
  paneItem,
  externalItem,
}: {
  itemIdParam: string | null
  paneItem?: MemexItemModel
  externalItem: boolean
}) {
  const {addToast} = useToasts()
  const [, setSearchParams] = useSearchParams()
  const addToastRef = useTrackingRef(addToast)

  useEffect(() => {
    if (!itemIdParam) return
    if (paneItem?.contentType && supportedItemTypes.has(paneItem.contentType)) return
    // This will be true if an issue param is provided and is only needed for external sub-issues
    // that aren't part of the project
    if (externalItem) return

    addToastRef.current({
      type: ToastType.error,
      message:
        paneItem?.contentType === ItemType.PullRequest
          ? Resources.sidePanelItemNotSupported
          : Resources.sidePanelItemNotFound,
    })

    setSearchParams(
      params => {
        params.delete(PANE_PARAM)
        params.delete(ITEM_ID_PARAM)
        params.delete(NWO_REFERENCE_PARAM)
        return params
      },
      {replace: true},
    )
  }, [addToastRef, externalItem, itemIdParam, paneItem, setSearchParams])
}

const defaultDirtyItems: ReadonlySet<symbol> = new Set()

export const SidePanelContext = createContext<SidePanelContextValue | null>(null)
const SidePanelCurrentItemIdContext = createContext<number | undefined>(undefined)
const SidePanelBreadcrumbHistoryContext = createContext<ReadonlyArray<SidePanelItem>>([])

function isValidSidePanelTypeParams(param: string | null): param is ObjectValues<typeof SidePanelTypeParam> {
  if (!param) return false
  return new Set<string>(Object.values(SidePanelTypeParam)).has(param)
}

function getSubIssueSidePanelItemFromNWOReference(
  itemId: string,
  nwoReference: string,
): SubIssueSidePanelItem | undefined {
  const [owner, repo, numberRaw] = nwoReference.split('|')

  if (!owner || !repo || !numberRaw) return

  return new SubIssueSidePanelItem({
    id: parseInt(itemId),
    number: parseInt(numberRaw),
    owner,
    repo,
    state: '',
    stateReason: '',
    title: '',
    url: '',
  })
}

function getPanelState(
  paneParam: string | null,
  opts: {
    [Key in ObjectValues<typeof SidePanelTypeParam>]: Extract<SidePanelState, {type: Key}> | null
  },
): SidePanelState {
  if (isValidSidePanelTypeParams(paneParam)) {
    return opts[paneParam]
  }
  return null
}

/**
 * When the pane param is SidePanelTypeParam.ITEM, redirect to SidePanelTypeParam.ISSUE
 * replace the history instead of appending
 */
function useRedirectWhenDeprecatedItemParam() {
  const [searchParams, setSearchParams] = useSearchParams()
  const isDeprecatedItemParam = searchParams.get(PANE_PARAM) === DEPRECATED_SIDE_PANEL_PARAM

  useEffect(() => {
    if (!isDeprecatedItemParam) return
    setSearchParams(
      params => {
        params.set(PANE_PARAM, SidePanelTypeParam.ISSUE)
        return params
      },
      {replace: true},
    )
  }, [isDeprecatedItemParam, setSearchParams])
}

const defaultItemPanelBreadcrumbHistory: ReadonlyArray<SidePanelItem> = []

export const SidePanelProviderRenderFunction = ({children}: {children: ReactNode}) => {
  const [searchParams, setSearchParams] = useSearchParams()
  const {items} = useMemexItems()
  const paneParam = searchParams.get(PANE_PARAM)
  const isBulkAddParam = paneParam === SidePanelTypeParam.BULK_ADD
  const isIssuePane = paneParam === DEPRECATED_SIDE_PANEL_PARAM || paneParam === SidePanelTypeParam.ISSUE
  const itemIdParam = searchParams.get(ITEM_ID_PARAM)
  const itemNWOReference = searchParams.get(NWO_REFERENCE_PARAM)
  const {paneItem, isItemLoading, reloadPaneItem, setQueryDataForSidePanelItem, setItemIsLoaded, loadPaneItemData} =
    useSidePanelItem(itemIdParam)

  useRedirectWhenDeprecatedItemParam()

  // If we are in the process of loading the item from the server (because we have an itemIdParam from the URL
  // but we were unable to find the item in `useMemexItems`), we _don't_ want to clear the params from the URL.
  // Passing `null` as the first parameter (the item id), will cause the `useClearParamsWhenNoVisibleItemForId`
  // to return early and not clear the params.
  // Once the query resolves - either successfully or unsuccessfully, we can pass the itemIdParam, along with the
  // recently requested item, to this hook, so that it can use the proper logic.
  useClearParamsWhenNoVisibleItemForId({
    itemIdParam: isItemLoading ? null : itemIdParam,
    paneItem,
    externalItem: !!itemNWOReference && !paneItem,
  })

  const [breadcrumbHistoryState, setBreadcrumbHistory] = useState<ReadonlyArray<SidePanelItem>>(
    paneItem ? [paneItem] : defaultItemPanelBreadcrumbHistory,
  )

  const historyEmpty = breadcrumbHistoryState.length === 0
  /**
   * when navigating back, if the history is empty, add the current item to the history
   */
  if (paneItem && historyEmpty) {
    setBreadcrumbHistory([paneItem])
  }

  if (historyEmpty) {
    if (paneItem) {
      setBreadcrumbHistory([paneItem])
    } else if (itemIdParam && itemNWOReference) {
      const item = getSubIssueSidePanelItemFromNWOReference(itemIdParam, itemNWOReference)
      if (item) {
        setBreadcrumbHistory([item])
      }
    }
  }

  const breadcrumbHistoryStateWithItem: typeof breadcrumbHistoryState = useMemo(() => {
    if (breadcrumbHistoryState.length === 0) return defaultItemPanelBreadcrumbHistory
    return breadcrumbHistoryState.reduce((acc, historyItem) => {
      if (!historyItem.memexItemId) {
        acc.push(historyItem)
        return acc
      }
      const itemId = historyItem.memexItemId()
      if (paneItem && itemId === paneItem.id) {
        acc.push(paneItem)
      } else {
        const item = items.find(i => i.id === itemId)
        if (item) {
          acc.push(item)
        }
      }
      return acc
    }, [] as Array<SidePanelItem>)
  }, [breadcrumbHistoryState, items, paneItem])

  const lastHistoryItem = breadcrumbHistoryStateWithItem.at(-1)

  const itemPaneState = useMemo(() => {
    if (!isIssuePane) return null
    if (!lastHistoryItem) return null
    const itemState: MemexItemSidePanelState = {
      type: SidePanelTypeParam.ISSUE,
      item: lastHistoryItem,
    }
    return itemState
  }, [isIssuePane, lastHistoryItem])

  const {hasWritePermissions} = ViewerPrivileges()

  const location = useLocation()
  const bulkAddState = useMemo(() => {
    if (!hasWritePermissions || !isBulkAddParam) return null
    const bulkState: MemexBulkAddSidePanelState = {
      ...parseStatefulOpts(location.state),
      type: SidePanelTypeParam.BULK_ADD,
    }
    return bulkState
  }, [isBulkAddParam, hasWritePermissions, location.state])

  useEffect(() => {
    if (isBulkAddParam && !hasWritePermissions) {
      setSearchParams(
        params => {
          params.delete(PANE_PARAM)
          return params
        },
        {replace: true},
      )
    }
  }, [hasWritePermissions, isBulkAddParam, setSearchParams])

  const sidePanelState = getPanelState(paneParam, {
    [SidePanelTypeParam.ISSUE]: itemPaneState,
    [SidePanelTypeParam.INFO]: infoTabState,
    [SidePanelTypeParam.BULK_ADD]: bulkAddState,
  })

  // This little hack ensures that we can support using the browser back/forward buttons to navigate
  // between history items in the side panel. By removing the breadcrumbs,
  // we enable side-panel items to loaded in the side-panel correctly.
  useEffect(() => {
    const listener = () => {
      setBreadcrumbHistory(defaultItemPanelBreadcrumbHistory)
    }

    window.addEventListener('popstate', listener)

    return () => window.removeEventListener('popstate', listener)
  }, [])

  useEffect(() => {
    if (!sidePanelState && onCloseRef.current) {
      onCloseRef.current?.()
      onCloseRef.current = undefined
    }
  }, [sidePanelState])

  const isPaneOpened = !!sidePanelState

  useEffect(() => {
    // Pull focus into the panel upon opening or updating. The modal version handles this automatically but not the
    // docked version
    if (itemIdParam && !containerRef.current?.contains(document.activeElement)) {
      // eslint-disable-next-line @eslint-react/web-api/no-leaked-timeout
      window.setTimeout(() => initialFocusRef.current?.focus())
    }
  }, [itemIdParam])

  const {postStats} = usePostStats()

  const [pinned, _setPinned] = useLocalStorage('projects.sidePanelPinned', false)

  const setPinned = useCallback(
    (value: boolean) => {
      _setPinned(value)
      // When the pin button is activated, we want to force focus to return to the same button in the new panel, even
      // when the overlay panel tries to pull focus to the close button
      setTimeout(() => pinButtonRef.current?.focus(), 25)
      postStats({
        name: 'side_panel_pin',
        context: value ? 'pin' : 'unpin',
      })
    },
    [_setPinned, postStats],
  )

  const [dirtyItems, setDirtyItems] = useState(defaultDirtyItems)
  const hasUnsavedChanges = dirtyItems.size > 0
  const resetDirtyItems = useCallback(() => setDirtyItems(defaultDirtyItems), [])

  const onCloseRef = useRef<(() => void) | undefined>(undefined)

  const openProjectItemInPane = useCallback(
    (item: SidePanelItem, newItemOnClose?: () => void) => {
      if (!supportedItemTypes.has(item.contentType)) return
      setQueryDataForSidePanelItem(item)
      if (item.contentType === ItemType.DraftIssue) {
        resetDirtyItems()
        setItemIsLoaded(false)
      }
      setSearchParams(nextParams => {
        nextParams.set(PANE_PARAM, SidePanelTypeParam.ISSUE)
        nextParams.set(ITEM_ID_PARAM, item.id.toString())

        if (item instanceof IssueModel || item instanceof SubIssueSidePanelItem) {
          const paramValue = item.getNameWithOwnerReferenceParam()

          if (paramValue) {
            nextParams.set(NWO_REFERENCE_PARAM, paramValue)
          }
        } else {
          // Otherwise, clear the issue param
          nextParams.delete(NWO_REFERENCE_PARAM)
        }

        return nextParams
      })
      onCloseRef.current = newItemOnClose

      setBreadcrumbHistory([item])
      postStats({
        /**
         * This is not just drafts, but we've historically
         * only sent this when the item pane is interacted with
         */
        name: DraftOpen,
        memexProjectItemId: item.id,
      })
    },
    [setQueryDataForSidePanelItem, setSearchParams, postStats, resetDirtyItems, setItemIsLoaded],
  )

  const openPaneInfo = useCallback(
    (statusUpdateId?: number) => {
      if (searchParams.get(PANE_PARAM) === SidePanelTypeParam.INFO) return
      setSearchParams(
        params => {
          params.set(PANE_PARAM, SidePanelTypeParam.INFO)
          params.delete(ITEM_ID_PARAM)
          params.delete(NWO_REFERENCE_PARAM)

          if (statusUpdateId) {
            params.set(STATUS_UPDATE_ID_PARAM, statusUpdateId.toString())
          }
          return params
        },
        {flushSync: true},
      )
    },
    [searchParams, setSearchParams],
  )

  const openPaneBulkAdd = useCallback(
    (
      ui: BulkAddSidePanelOpenUIType,
      targetRepository?: SuggestedRepository,
      query?: string,
      newItemAttributes?: OmnibarItemAttrs,
    ) => {
      resetDirtyItems()
      setSearchParams(
        params => {
          params.set(PANE_PARAM, SidePanelTypeParam.BULK_ADD)
          params.delete(ITEM_ID_PARAM)
          params.delete(NWO_REFERENCE_PARAM)

          return params
        },
        {
          state: {
            targetRepository,
            newItemAttributes,
            query,
          },
        },
      )
      postStats({name: BulkAddSidePanelOpen, ui})
    },
    [resetDirtyItems, postStats, setSearchParams],
  )

  const confirmClose = useConfirm()

  const confirmUnsaved = useCallback(async () => {
    if (!hasUnsavedChanges) return true
    return await confirmClose({
      ...Resources.sidePanelCloseConfirmation,
      confirmButtonType: 'danger',
    })
  }, [confirmClose, hasUnsavedChanges])

  const closePane = useCallback(
    async (opts?: {force?: boolean}) => {
      if (hasUnsavedChanges && !(opts && opts.force)) {
        const close = await confirmUnsaved()
        if (!close) return false
        resetDirtyItems()
      }
      setSearchParams(params => {
        params.delete(PANE_PARAM)
        params.delete(ITEM_ID_PARAM)
        params.delete(NWO_REFERENCE_PARAM)

        // clear the status update id if it's present
        if (params.get(STATUS_UPDATE_ID_PARAM)) {
          params.delete(STATUS_UPDATE_ID_PARAM)
        }
        return params
      })

      setBreadcrumbHistory(defaultItemPanelBreadcrumbHistory)
      return true
    },
    [hasUnsavedChanges, resetDirtyItems, setSearchParams, confirmUnsaved],
  )

  const beforeUnload = useCallback(
    (event: BeforeUnloadEvent) => {
      if (hasUnsavedChanges) {
        event.preventDefault()
        return (event.returnValue = '')
      }
    },
    [hasUnsavedChanges],
  )

  useBeforeUnload(beforeUnload)

  const updateBreadcrumbHistoryAndPostStats = useCallback(
    (historyItem?: HistoryItem) => {
      if (!historyItem) return

      const {historyIdx, item} = historyItem
      if (!item) return

      setBreadcrumbHistory(prev => {
        let next = prev.slice()
        if (historyIdx !== undefined) {
          next = prev.slice(0, historyIdx)
        }
        return [...next, item]
      })

      /**
       * This used to be called again by calling openPaneItem, but now we don't
       * call that method a second time, so we need to call postStats here
       *
       * We are currently using DraftOpen as the 'side panel item opened' event
       * which is odd, but history.  I don't want to break any dashboards that
       * might rely on this
       */
      postStats({
        name: DraftOpen,
        memexProjectItemId: item.id,
      })
    },
    [postStats],
  )

  const openPaneHistoryItem = useCallback(
    async (historyItem?: HistoryItem) => {
      if (sidePanelState?.type !== SidePanelTypeParam.ISSUE) return

      // If no SidePanelItem to open, open link in new tab as usual
      if (!historyItem) return
      const {item} = historyItem
      if (!item) return

      const close = await confirmUnsaved()
      if (!close) return

      loadPaneItemData(item)
      resetDirtyItems()
      updateBreadcrumbHistoryAndPostStats(historyItem)
    },
    [sidePanelState?.type, loadPaneItemData, resetDirtyItems, updateBreadcrumbHistoryAndPostStats, confirmUnsaved],
  )

  const openPaneHierarchyHistoryItem = useCallback(
    async (historyItem?: HistoryItem) => {
      // If no SidePanelItem to open, open link in new tab as usual
      if (!historyItem) return
      if (!historyItem.item?.isHierarchy) return

      const {item} = historyItem
      if (!item) return

      const close = await confirmUnsaved()
      if (!close) return

      loadPaneItemData(item)
      resetDirtyItems()
      updateBreadcrumbHistoryAndPostStats(historyItem)
    },
    [loadPaneItemData, resetDirtyItems, updateBreadcrumbHistoryAndPostStats, confirmUnsaved],
  )

  const {isProjectViewRoute} = useProjectViewRouteMatch()
  useCommands(() => {
    if (!isProjectViewRoute || sidePanelState?.type === SidePanelTypeParam.BULK_ADD) return null
    return ['a', 'Add items', BulkAddSidePanelOpen, () => openPaneBulkAdd(CommandPaletteUI)]
  }, [isProjectViewRoute, sidePanelState, openPaneBulkAdd])

  useCommands(() => {
    if (!sidePanelState) return null
    return pinned
      ? ['p', Resources.sidePanelUnpinLabel, 'side-panel-unpin', () => setPinned(false)]
      : ['p', Resources.sidePanelPinLabel, 'side-panel-pin', () => setPinned(true)]
  }, [sidePanelState, pinned, setPinned])

  const pinButtonRef = useRef<HTMLButtonElement>(null)
  const initialFocusRef = useRef<HTMLButtonElement>(null)
  const containerRef = useRef<HTMLDivElement>(null)

  const contextValue: SidePanelContextValue = useMemo(() => {
    return {
      sidePanelState,
      openProjectItemInPane,
      reloadPaneItem,
      openPaneInfo,
      openPaneBulkAdd,
      closePane,
      hasUnsavedChanges,
      setDirtyItems,
      dirtyItems,
      isPaneOpened,
      supportedItemTypes,
      openPaneHistoryItem,
      openPaneHierarchyHistoryItem,
      pinned,
      setPinned,
      pinButtonRef,
      initialFocusRef,
      containerRef,
    }
  }, [
    closePane,
    setDirtyItems,
    dirtyItems,
    hasUnsavedChanges,
    isPaneOpened,
    openPaneBulkAdd,
    openPaneHierarchyHistoryItem,
    openPaneHistoryItem,
    openPaneInfo,
    openProjectItemInPane,
    reloadPaneItem,
    sidePanelState,
    pinned,
    setPinned,
  ])
  return (
    <SidePanelContext.Provider value={contextValue}>
      <SidePanelCurrentItemIdContext.Provider
        value={sidePanelState && 'item' in sidePanelState ? sidePanelState.item.id : undefined}
      >
        <SidePanelBreadcrumbHistoryContext.Provider value={breadcrumbHistoryStateWithItem}>
          {children}
        </SidePanelBreadcrumbHistoryContext.Provider>
      </SidePanelCurrentItemIdContext.Provider>
    </SidePanelContext.Provider>
  )
}

export const SidePanelProvider = memo(SidePanelProviderRenderFunction)

function parseStatefulOpts(state: any) {
  const opts: {
    targetRepository: SuggestedRepository | undefined
    query: string | undefined
    newItemAttributes: OmnibarItemAttrs | undefined
  } = {
    targetRepository: undefined,
    query: undefined,
    newItemAttributes: undefined,
  }

  if (state) {
    if ('targetRepository' in state) {
      opts.targetRepository = state.targetRepository
    }
    if ('query' in state) {
      opts.query = state.query
    }
    if ('newItemAttributes' in state) {
      opts.newItemAttributes = state.newItemAttributes
    }
  }

  return opts
}

export const useSidePanelBreadcrumbHistory = () => useContext(SidePanelBreadcrumbHistoryContext)

export const useSidePanelItemId = () => {
  const context = useContext(SidePanelCurrentItemIdContext)
  return context
}

export const useSidePanel = () => {
  const context = useContext(SidePanelContext)
  if (context === null) {
    throw new Error('useSidePanel must be used within a SidePanelProvider')
  }

  return context
}

// Use this hook when opening the pane from the table and you want to maintain
// focus position in the table.
export const useTableSidePanel = () => {
  const {openProjectItemInPane, ...rest} = useSidePanel()
  const {navigationDispatch} = useStableTableNavigation()
  const {postStats} = usePostStats()

  const openPaneWithTableFocus = useCallback(
    (item: SidePanelItem) => {
      openProjectItemInPane(item, () => {
        navigationDispatch(moveTableFocus({focusType: FocusType.Focus}))
      })
      postStats({name: SidePanelTableOpen, context: JSON.stringify({contentType: item.contentType})})
      navigationDispatch(moveTableFocus({focusType: FocusType.Suspended}))
    },
    [navigationDispatch, openProjectItemInPane, postStats],
  )

  return {
    openPane: openPaneWithTableFocus,
    ...rest,
  }
}

// Use this hook when opening the pane from the board and you want to maintain
// focus position.
export const useBoardSidePanel = () => {
  const {openProjectItemInPane, ...rest} = useSidePanel()
  const {navigationDispatch} = useStableBoardNavigation()
  const {postStats} = usePostStats()

  const openPaneWithTableFocus = useCallback(
    (item: SidePanelItem) => {
      openProjectItemInPane(item, () => {
        navigationDispatch(focusPrevious())
      })
      postStats({name: SidePanelBoardOpen, context: JSON.stringify({contentType: item.contentType})})
    },
    [navigationDispatch, openProjectItemInPane, postStats],
  )

  return {
    openPane: openPaneWithTableFocus,
    ...rest,
  }
}
