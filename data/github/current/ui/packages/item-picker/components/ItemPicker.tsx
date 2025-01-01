import {useKeyPress} from '@github-ui/use-key-press'
import {type OverlayProps, SelectPanel, type SelectPanelProps, useResizeObserver} from '@primer/react'
import {useCallback, useEffect, useId, useMemo, useState} from 'react'
import type {ActionListItemProps as ItemProps, ActionListItemInput as ItemInput} from '@primer/react/deprecated'
import type {RefObject} from 'react'
import type React from 'react'

import {useItemPickersContext} from '../contexts/ItemPickersContext'
import {type ItemGroup, noMatchesItem, noResultsItem} from '../shared'
import {IDS} from '../constants/ids'
import {SELECTORS} from '../constants/selectors'
import {GlobalCommands, type CommandId} from '@github-ui/ui-commands'
import {isFeatureEnabled} from '@github-ui/feature-flags'
import {FeatureFlags} from '@primer/react/experimental'

export type SharedBulkActionsItemPickerProps = {
  issuesToActOn: string[]
  useQueryForAction: boolean
  repositoryId?: string
  query?: string
  onCompleted?: (jobId?: string) => void
  onError?: (error: Error) => void
}

export type ItemPickerProps<T> = Pick<OverlayProps, 'height' | 'width'> & {
  items: Array<T & {__isNew__?: boolean}>
  initialSelectedItems: T[] | string[]
  placeholderText: string
  selectionVariant: 'single' | 'multiple'
  loading?: boolean
  groups?: ItemGroup[]
  filterItems: (filter: string) => void
  renderAnchor: (props: React.HTMLAttributes<HTMLElement>) => JSX.Element
  getItemKey: (item: T) => string
  convertToItemProps: (item: T) => ExtendedItemProps<T>
  onSelectionChange: (items: T[]) => void
  onOpen?: () => void
  onClose?: () => void
  selectPanelRef?: RefObject<HTMLButtonElement>
  enforceAtleastOneSelected?: boolean
  insidePortal?: boolean
  maxVisibleItems?: number
  /**
   * Whether to render the item picker as a nested select panel (true) versus a standalone select
   * panel (false; default).
   */
  nested?: boolean
  resultListAriaLabel?: string
  title?: string | React.ReactElement
  subtitle?: string | React.ReactElement
  preventClose?: boolean
  triggerOpen?: boolean
  initialFilter?: string
  customNoResultsItem?: ItemProps
  customNoMatchItem?: T
  footer?: string | React.ReactElement
  keybindingCommandId?: CommandId
  pickerId?: string
  onCancel?: () => void
  // temporary, this will go away when fully ship the FF
  responsiveOnNarrow?: boolean
  portalContainerName?: string
  secondaryAction?:
    | React.ReactElement<typeof SelectPanel.SecondaryActionButton>
    | React.ReactElement<typeof SelectPanel.SecondaryActionLink>
  /**
   * When enabled, prevents "No matches" placeholder from being announced as a selectable item
   * by screen readers. This improves accessibility by ensuring only actual selectable items
   * are counted in screen reader navigation. Can be customised with `noMatchMessage` prop.
   */
  improvedNoMatchAccessibility?: boolean
  /**
   * Optional message to display in select panel when no items match the filter.
   *
   * If `improvedNoMatchAccessibility` is enabled, it will be displayed when there are no items to show.
   * This is used to display a message in the select panel, such as "No results found" or "Loading...".
   */
  noMatchMessage?: SelectPanelProps['message']
  /**
   * When enabled, prevents "No matches" placeholder from being returned.
   */
  suppressNoMatchItem?: boolean
} & Pick<SelectPanelProps, 'notice' | 'className'>

export type ExtendedItemProps<T> = ItemProps & {source: T}

export function ItemPicker<T>({
  items,
  initialSelectedItems,
  placeholderText,
  selectionVariant,
  loading,
  groups,
  filterItems,
  renderAnchor,
  getItemKey,
  convertToItemProps,
  onSelectionChange,
  onOpen,
  onClose,
  height = 'small',
  width = 'small',
  selectPanelRef,
  enforceAtleastOneSelected,
  insidePortal,
  maxVisibleItems = 9,
  nested = false,
  resultListAriaLabel,
  title,
  subtitle,
  preventClose,
  triggerOpen,
  initialFilter,
  customNoResultsItem,
  customNoMatchItem,
  footer,
  keybindingCommandId,
  pickerId,
  responsiveOnNarrow,
  secondaryAction,
  notice,
  className,
  portalContainerName,
  improvedNoMatchAccessibility,
  noMatchMessage,
  suppressNoMatchItem,
}: ItemPickerProps<T>) {
  const [open, setOpen] = useState(triggerOpen ?? false)
  const [selected, setSelected] = useState<ItemInput[]>([])
  const [filter, setFilter] = useState<string>(initialFilter ?? '')
  const {updateOpenState, anyItemPickerOpen} = useItemPickersContext()
  const [isNarrow, setIsNarrow] = useState(false)
  let id = useId()
  if (pickerId) {
    id = pickerId
  }
  const blurOnCloseEnabled = isFeatureEnabled('issues_react_blur_item_picker_on_close')
  // allow individual item pickers to opt-in to fullscreen mode on narrow screens
  const responsiveOnNarrowEnabled =
    responsiveOnNarrow || isFeatureEnabled('primer_react_select_panel_fullscreen_on_narrow')

  useResizeObserver(() => {
    setIsNarrow(window.innerWidth < 768)
  })

  // Update open state if controlled by consumer
  useEffect(() => {
    if (triggerOpen !== undefined) setOpen(triggerOpen)
  }, [triggerOpen])

  const handleKeyDown = useCallback(() => {
    if (anyItemPickerOpen() || open) {
      return
    }
    setOpen(true)
    if (onOpen) onOpen()
  }, [anyItemPickerOpen, open, onOpen])

  useEffect(() => {
    updateOpenState(id, open)
  }, [id, open, updateOpenState])

  const map = useMemo(
    () => new Map<string, ExtendedItemProps<T>>(),
    // eslint-disable-next-line react-hooks/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [id, initialSelectedItems],
  )

  const toItemProps = useCallback(
    (item: T, itemSelected: boolean): ExtendedItemProps<T> => {
      const itemKey = getItemKey(item)
      let itemProps = map.get(itemKey)
      if (itemProps) {
        return itemProps
      }

      itemProps = convertToItemProps(item)

      itemProps.selected = itemSelected
      const onAction = itemProps.onAction
      itemProps.onAction = (props, event) => {
        const i = map.get(itemKey)
        if (!i) return
        i.selected = !i.selected

        // if using single select, clear selection of all other items
        if (selectionVariant === 'single' && (item as ItemProps).id !== filter) {
          for (const [, value] of map) {
            if (value !== i) {
              value.selected = false
            }
          }
        }

        if (onAction) {
          onAction(props, event)
        }
      }

      map.set(itemKey, itemProps)
      return itemProps
    },
    [convertToItemProps, filter, getItemKey, map, selectionVariant],
  )

  const wrappedGetItemKey = useCallback(
    (item: T | string) => (typeof item === 'string' ? item : getItemKey(item)),
    [getItemKey],
  )

  const selectPanelItems = useMemo<ItemProps[]>(() => {
    const itemProps = items.map(i => {
      // If we have newly created items, we remove the __isNew__ flag from the item
      // after selecting it, so that it can be deselected.
      // We also remove the "no match" item since clicking on it adds it to the selected items,
      // and we don't want to add that synthetic item to the mutation.
      if (i.__isNew__) {
        delete i.__isNew__
        if (customNoMatchItem) map.delete(getItemKey(customNoMatchItem))
        // We auto select newly created items
        return toItemProps(i, true)
      }
      return toItemProps(
        i,
        initialSelectedItems.some(is => wrappedGetItemKey(is) === getItemKey(i)),
      )
    })

    if (itemProps.length === 0) {
      // If improvedNoMatchAccessibility is enabled, return empty array
      // The empty state message will be handled by SelectPanel's message prop
      if (improvedNoMatchAccessibility) {
        return []
      }

      if (customNoMatchItem) return [toItemProps(customNoMatchItem, false)]

      if (suppressNoMatchItem) {
        return []
      }

      // Differentiate between no results and no matches
      return filter ? [customNoMatchItem ?? noMatchesItem] : [customNoResultsItem ?? noResultsItem]
    }

    return itemProps
  }, [
    customNoMatchItem,
    items,
    map,
    toItemProps,
    initialSelectedItems,
    wrappedGetItemKey,
    getItemKey,
    filter,
    customNoResultsItem,
    improvedNoMatchAccessibility,
    suppressNoMatchItem,
  ])

  useEffect(() => {
    setSelected(selectPanelItems.filter(i => i.selected))
  }, [selectPanelItems])

  const selectPanelSelectedItems = useMemo<ItemInput | ItemInput[]>(() => {
    if (selectionVariant === 'single') {
      return selected[0]!
    } else {
      return selected
    }
  }, [selected, selectionVariant]) as ItemProps[]

  const onSelectedChange = useCallback(
    (param: ItemInput[] | ItemInput | undefined) => {
      if (param === undefined) {
        if (!enforceAtleastOneSelected) {
          setSelected([])
        }
        return
      }

      const selectedItemInputs = Array.isArray(param) ? param : [param]
      const newSelection = selectedItemInputs
        .map(i => selectPanelItems.find(item => i.id === item.id))
        .filter(i => i !== undefined) as Array<ExtendedItemProps<T>>

      setSelected(newSelection)
    },
    [enforceAtleastOneSelected, selectPanelItems],
  )

  const onSpaceKeyPress = (event: KeyboardEvent) => {
    if (open) {
      const activeOption = document.querySelector(SELECTORS.activePickerOption(IDS.itemPickerRootId))

      if (activeOption) {
        const activeDataId = activeOption.getAttribute('data-id')
        const item = [...map.values()].find(i => i.id === activeDataId)

        if (item) {
          event.preventDefault()
          event.stopPropagation()
          // Toggle the selected state of the item
          item.selected = !item.selected
          setSelected([...map.values()].filter(i => i.selected))
        }
      }
    }
  }

  useKeyPress([' '], onSpaceKeyPress, {
    triggerWhenInputElementHasFocus: true,
    triggerWhenPortalIsActive: true,
  })

  const onOpenChange = useCallback(
    (
      isOpen: boolean,
      gesture: 'anchor-click' | 'anchor-key-press' | 'click-outside' | 'escape' | 'selection' | 'cancel',
    ) => {
      if (preventClose && !isOpen) {
        return
      }
      if (gesture === 'cancel') {
        return
      }
      // Fix for an issue in safari where the issue would scroll down all the way
      // when the item picker is closed with escape
      if (blurOnCloseEnabled && !isOpen && document.activeElement instanceof HTMLElement) {
        // eslint-disable-next-line github/no-blur
        document.activeElement?.blur()
      }
      setOpen(isOpen)

      if (isOpen && onOpen) {
        onOpen()
        return
      }

      setFilter('')
      if (onClose) onClose()
      const selectedItems = [...map.values()].filter(i => i.selected).map(i => i.source)
      const selectionChanged =
        selectedItems.length !== initialSelectedItems.length ||
        selectedItems.some(item => !initialSelectedItems.some(item2 => wrappedGetItemKey(item2) === getItemKey(item)))

      if (selectionChanged) {
        onSelectionChange(selectedItems)
      }
    },
    [
      preventClose,
      onClose,
      map,
      initialSelectedItems,
      onOpen,
      wrappedGetItemKey,
      getItemKey,
      onSelectionChange,
      blurOnCloseEnabled,
    ],
  )

  const onCancel = useCallback(() => {
    if (preventClose) {
      return
    }

    setFilter('')

    const selectedItems = [...map.values()].filter(i => i.selected).map(i => i.source)
    const selectionChanged =
      selectedItems.length !== initialSelectedItems.length ||
      selectedItems.some(item => !initialSelectedItems.some(item2 => wrappedGetItemKey(item2) === getItemKey(item)))

    if (selectionChanged) {
      // reset selection since it was cancelled
      // Update the selection state of items based on initialSelectedItems
      for (const i of map.values()) {
        if (initialSelectedItems.some(item => wrappedGetItemKey(item) === getItemKey(i.source))) {
          // Reselect unselected items that were initially selected
          i.selected = true
        } else {
          // Deselect all items that are not in the initialSelectedItems
          i.selected = false
        }
      }
      // Filter items to get the initially selected ones
      const initiallySelected = [...map.values()].filter(i => i.selected)
      setSelected(initiallySelected)
    }

    setOpen(false)

    if (onClose) onClose()
  }, [preventClose, map, initialSelectedItems, onClose, wrappedGetItemKey, getItemKey])

  useEffect(() => {
    filterItems(filter)
  }, [filter, filterItems])

  let hasItems = selectPanelItems.length > 0
  if (
    selectPanelItems.length === 1 &&
    (selectPanelItems[0]!.id === noMatchesItem.id || selectPanelItems[0]!.id === noResultsItem.id)
  ) {
    // Don't show groups if there are only placeholder items (which aren't grouped)
    hasItems = false
  }

  // SelectPanel doesn't handle an empty groupMetadata prop properly
  const groupMetadataProp = useMemo(
    () => (groups && groups?.length > 1 && hasItems ? {groupMetadata: groups} : {}),
    [groups, hasItems],
  )

  const regularHeight = selectPanelItems.length <= maxVisibleItems ? 'auto' : height
  const adjustedOverlayProps = getAdjustedOverlayProps(
    insidePortal,
    selectPanelRef,
    regularHeight,
    isNarrow && responsiveOnNarrowEnabled,
  )

  // Fallback to generic no match message if one is not provided
  const message = useMemo(
    () =>
      noMatchMessage
        ? noMatchMessage
        : filter
          ? {
              variant: 'empty' as const,
              title: 'No matches found',
              body: 'Try a different search term',
            }
          : {
              variant: 'empty' as const,
              title: 'No items to show',
              body: '',
            },
    [noMatchMessage, filter],
  )

  const selectPanelProps = useMemo<SelectPanelProps>(
    () => ({
      renderAnchor,
      placeholderText,
      open,
      onOpenChange,
      loading,
      items: selectPanelItems,
      selected: selectPanelSelectedItems,
      onSelectedChange,
      filterValue: filter,
      onFilterChange: setFilter,
      showItemDividers: true,
      overlayProps: {
        width,
        className,
        portalContainerName,
        ...adjustedOverlayProps,
      },
      ...groupMetadataProp,
      'aria-label': resultListAriaLabel,
      'data-id': IDS.itemPickerRootId,
      'data-testid': IDS.itemPickerTestId,
      title,
      subtitle,
      footer,
      onCancel,
      secondaryAction,
      notice,
      // Add message prop for improved no-match accessibility,
      message: improvedNoMatchAccessibility && selectPanelItems.length === 0 ? message : undefined,
    }),
    [
      renderAnchor,
      placeholderText,
      open,
      onOpenChange,
      loading,
      selectPanelItems,
      selectPanelSelectedItems,
      onSelectedChange,
      filter,
      width,
      adjustedOverlayProps,
      groupMetadataProp,
      resultListAriaLabel,
      title,
      subtitle,
      footer,
      message,
      onCancel,
      secondaryAction,
      notice,
      className,
      portalContainerName,
      improvedNoMatchAccessibility,
    ],
  )

  const flags = {
    primer_react_select_panel_with_modern_action_list: true,
    // footer is deprecated and doesn't mesh well with fullscreen on narrow functionality, should use secondaryActions instead
    primer_react_select_panel_fullscreen_on_narrow: footer === undefined && responsiveOnNarrowEnabled,
  }

  return (
    <FeatureFlags flags={flags}>
      {keybindingCommandId && <GlobalCommands commands={{[keybindingCommandId]: handleKeyDown}} />}
      <SelectPanel anchorRef={nested ? undefined : selectPanelRef} {...selectPanelProps} />
    </FeatureFlags>
  )
}

/**
 * When `insidePortal` is true, such as with the Create Issue dialog,
 * the SelectPanel sometimes gets rendered below the buttons and cut off by the viewport.
 * To fix this, we:
 * - set a fixed height (`large`, 432px) for the SelectPanel.
 * - set the position to `fixed` to handle scrolling and varied portal positions.
 * - overwrite the `top` value to the `top` of its anchor button minus the height of the SelectPanel and some padding (4px).
 * - overwrite the `left` value to the `left` of its anchor button.
 * This will force the SelectPanel to always be rendered just above the buttons and be accessible within the viewport.
 *
 * Note: This is a workaround that doesn't require fixing the Primer components/behaviors themselves.
 * If this gets fixed in Primer, we can remove it.
 * Ref: https://github.com/github/primer/issues/4027
 */
export function getAdjustedOverlayProps(
  insidePortal: boolean | undefined,
  ref: RefObject<HTMLButtonElement> | undefined,
  regularHeight: OverlayProps['height'],
  isFullScreen: boolean = false,
): Pick<OverlayProps, 'height' | 'top' | 'left' | 'position'> {
  const height = insidePortal ? 'large' : regularHeight

  if (!insidePortal || !ref?.current) {
    return {height}
  }

  const {top: buttonTop, left: buttonLeft} = ref.current.getBoundingClientRect()
  const top = isFullScreen ? 0 : buttonTop - 436
  const left = isFullScreen ? 0 : buttonLeft

  if (top < 0) {
    return {height}
  }

  return {
    height,
    top,
    left,
    position: 'fixed',
  }
}
