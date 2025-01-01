/* eslint eslint-comments/no-use: off */
/* eslint-disable @github-ui/github-monorepo/filename-convention */
import type {PropertyValue} from '@github-ui/custom-properties-types'
import {isEmptyPropertyValue, isPropertyValueArray} from '@github-ui/custom-properties-types/helpers'
import {CircleSlashIcon, TriangleDownIcon} from '@primer/octicons-react'
import {Button, type SelectPanel, type SelectPanelProps, Truncate} from '@primer/react'
import type {ActionListItemInput as ItemInput} from '@primer/react/deprecated'
import {type ComponentProps, type RefObject, useMemo, useState} from 'react'

const mixedValuePlaceholder = '(Mixed)'
const defaultGroupId = 'default'
const optionsGroupId = 'options'
const emptyGroupId = 'empty'

const noMatchesItem: ItemInput = {
  leadingVisual: CircleSlashIcon,
  text: 'No matches',
  disabled: true,
  selected: undefined, // hide checkbox
  key: 'no-matches',
  id: 'no-matches',
  groupId: optionsGroupId,
}

export interface CustomPropertySelectPanelProps {
  propertyName: string
  defaultValue: PropertyValue | null
  allowedValues: string[] | null
  propertyValue?: PropertyValue
  anchorRef?: RefObject<HTMLElement>
  mixed: boolean
  onChange: (value: PropertyValue) => void
  anchorProps?: React.HTMLAttributes<HTMLElement>
}
const maxItemsViewport = 7

interface HookProps {
  propertyName: string
  defaultValue: PropertyValue | null
  allowedValues: string[] | null
  mixed: boolean
  currentSelection: string[]
  anchorProps?: React.HTMLAttributes<HTMLElement>
  singleSelectMode?: boolean
}

export function useSelectPanelProps({
  propertyName,
  defaultValue,
  allowedValues,
  mixed,
  currentSelection,
  anchorProps = {},
  singleSelectMode,
}: HookProps) {
  const [isOpen, setOpen] = useState(false)
  const [filterText, setFilterText] = useState('')

  const allItems = useMemo(
    () => (allowedValues || []).map(value => toItemInput(value, currentSelection.includes(value))),
    [allowedValues, currentSelection],
  )

  const [items, groupMetadata] = useMemo(() => {
    const displayItems = getDisplayItems(allItems, filterText.toLowerCase())
    const groups: ComponentProps<typeof SelectPanel>['groupMetadata'] = [{groupId: optionsGroupId, key: optionsGroupId}]

    const additionalItems: ItemInput[] = []
    if (defaultValue) {
      additionalItems.unshift(toDefaultItemInput(defaultValue, !currentSelection.length && !mixed))
      groups.unshift({groupId: defaultGroupId, key: defaultGroupId})
    } else if (singleSelectMode) {
      additionalItems.unshift(toEmptyItemInput(!currentSelection.length && !mixed))
      groups.unshift({groupId: emptyGroupId, key: emptyGroupId})
    }

    return [additionalItems.concat(displayItems), groups]
  }, [singleSelectMode, allItems, currentSelection.length, defaultValue, filterText, mixed])

  const height = items.length > maxItemsViewport ? 'medium' : 'auto'

  const anchorLabel = getDisplayAnchorLabel(currentSelection, defaultValue, mixed)
  return {
    items,
    renderAnchor: (panelAnchorProps: React.HTMLAttributes<HTMLElement>) => (
      <Button
        block
        alignContent="start"
        aria-label={mixed ? mixedValuePlaceholder : `Select ${propertyName}`}
        trailingAction={TriangleDownIcon}
        sx={{minWidth: 0, '>span[data-component="buttonContent"]': {flex: 1}}}
        {...panelAnchorProps}
        {...anchorProps}
      >
        <Truncate maxWidth="100%" title={anchorLabel}>
          {anchorLabel}
        </Truncate>
      </Button>
    ),
    placeholderText: 'Search for values',
    filterValue: filterText,
    open: isOpen,
    onFilterChange: setFilterText,
    onOpenChange: (newIsOpen: boolean) => {
      setOpen(newIsOpen)
      setFilterText('')
    },
    overlayProps: {height, width: 'medium'},
    groupMetadata,
    // Had to omit renderAnchor too because of a weird null type that TypeScript complains about
  } as Omit<SelectPanelProps, 'renderAnchor' | 'selected' | 'onSelectedChange'>
}

function toItemInput(value: string, selected: boolean): ItemInput {
  return {
    id: value,
    text: value,
    selected,
    groupId: optionsGroupId,
  }
}

function toDefaultItemInput(defaultValue: PropertyValue, selected: boolean, sourceName?: string): ItemInput {
  return {
    id: 'default',
    text: `Default (${getValueLabel(defaultValue, 'options')})`,
    selected,
    groupId: defaultGroupId,
    description: sourceName ? `inherited from ${sourceName}` : undefined,
    descriptionVariant: 'block',
  }
}

function toEmptyItemInput(selected: boolean): ItemInput {
  return {
    text: '(Empty)',
    key: '(empty)',
    id: '(empty)',
    selected,
    groupId: emptyGroupId,
    description: 'Unset value',
    descriptionVariant: 'block',
  }
}

function getDisplayItems(allItems: ItemInput[], filter: string) {
  const matchesFilter = (item: ItemInput) => (item.text || '').toLowerCase().includes(filter)
  const items = filter ? allItems.filter(matchesFilter) : allItems
  if (items.length === 0) {
    return [noMatchesItem]
  }
  return items
}

export function isDefaultGroup(item: ItemInput) {
  return item.groupId === defaultGroupId
}

export function isOptionsGroup(item: ItemInput) {
  return item.groupId === optionsGroupId
}

export function isEmptyGroup(item: ItemInput) {
  return item.groupId === emptyGroupId
}

export function getDisplayAnchorLabel(
  value: PropertyValue,
  defaultValue: PropertyValue | null,
  mixed: boolean,
): string {
  if (mixed) {
    return mixedValuePlaceholder
  }

  if (!isEmptyPropertyValue(value)) {
    return getValueLabel(value)
  } else if (!isEmptyPropertyValue(defaultValue)) {
    return `Default (${getValueLabel(defaultValue || '')})`
  } else {
    return 'Choose an option'
  }
}

function getValueLabel(value: PropertyValue, itemsName: string = 'selected'): string {
  if (isPropertyValueArray(value)) {
    if (value.length <= 1) {
      return value[0] || ''
    } else {
      return `${value.length} ${itemsName}`
    }
  } else {
    return value
  }
}
