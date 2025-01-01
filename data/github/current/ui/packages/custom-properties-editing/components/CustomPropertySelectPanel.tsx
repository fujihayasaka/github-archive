import type {PropertyValue} from '@github-ui/custom-properties-types'
import {isEmptyPropertyValue, isPropertyValueArray} from '@github-ui/custom-properties-types/helpers'
import {TriangleDownIcon} from '@primer/octicons-react'
import {Button, SelectPanel, Truncate} from '@primer/react'
import type {ActionListItemInput as ItemInput} from '@primer/react/deprecated'
import {type RefObject, useMemo, useState} from 'react'

export const mixedValuePlaceholder = '(Mixed)'

const EMPTY_STATE_MESSAGE: {title: string; body: string; variant: 'empty'} = {
  title: 'No property values were found',
  body: 'Try searching for a different value for results.',
  variant: 'empty',
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

export interface CustomPropertySingleSelectPanelProps extends CustomPropertySelectPanelProps {
  propertyValue: string
}
export function CustomPropertySingleSelectPanel({
  anchorRef,
  propertyName,
  defaultValue,
  allowedValues,
  propertyValue,
  mixed,
  onChange,
  anchorProps,
}: CustomPropertySingleSelectPanelProps) {
  const selectPanelProps = useSelectPanelProps(
    propertyName,
    defaultValue,
    allowedValues,
    mixed,
    propertyValue ? [propertyValue] : [],
    anchorProps,
  )
  const selectedItem = selectPanelProps.items.find(item => item.text && propertyValue === item.text)

  return (
    <SelectPanel
      {...selectPanelProps}
      anchorRef={anchorRef}
      onSelectedChange={(newItemValue?: ItemInput) => onChange(newItemValue?.text || '')}
      selected={selectedItem}
      message={selectPanelProps.items.length === 0 ? EMPTY_STATE_MESSAGE : undefined}
    />
  )
}

interface CustomPropertyMultiSelectPanelProps extends CustomPropertySelectPanelProps {
  propertyValue: string[]
}
export function CustomPropertyMultiSelectPanel({
  anchorRef,
  propertyName,
  defaultValue,
  allowedValues,
  propertyValue,
  mixed,
  onChange,
  anchorProps,
}: CustomPropertyMultiSelectPanelProps) {
  const selectPanelProps = useSelectPanelProps(
    propertyName,
    defaultValue,
    allowedValues,
    mixed,
    propertyValue,
    anchorProps,
  )
  const selectedItems = selectPanelProps.items.filter(item => item.selected)

  return (
    <SelectPanel
      {...selectPanelProps}
      anchorRef={anchorRef}
      onSelectedChange={(newItemValues: ItemInput[]) => {
        const {filterValue} = selectPanelProps
        const newValues = newItemValues.map(item => item.text || '')
        if (!filterValue) {
          onChange(newValues)
        } else {
          const isFilteredOut = (value: string) => !value.toLowerCase().includes(filterValue.toLowerCase())
          const hiddenSelectedValues = propertyValue.filter(isFilteredOut)
          onChange([...hiddenSelectedValues, ...newValues])
        }
      }}
      selected={selectedItems}
      message={selectPanelProps.items.length === 0 ? EMPTY_STATE_MESSAGE : undefined}
    />
  )
}

const maxItemsViewport = 7
function useSelectPanelProps(
  propertyName: string,
  defaultValue: PropertyValue | null,
  allowedValues: string[] | null,
  mixed: boolean,
  initialSelection: string[],
  anchorProps: React.HTMLAttributes<HTMLElement> = {},
) {
  const [isOpen, setOpen] = useState(false)
  const [filterText, setFilterText] = useState('')

  const allItems = useMemo(
    () => (allowedValues || []).map(value => toItemInput(value, initialSelection.includes(value))),
    [allowedValues, initialSelection],
  )
  const items = getDisplayItems(allItems, filterText.toLowerCase())
  const height: 'medium' | 'auto' = items.length > maxItemsViewport ? 'medium' : 'auto'

  const anchorLabel = getDisplayAnchorLabel(initialSelection, defaultValue, mixed)
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
    overlayProps: {height, width: 'medium' as const},
  }
}

function toItemInput(value: string, selected: boolean): ItemInput {
  return {
    id: value,
    text: value,
    selected,
  }
}

function getDisplayItems(allItems: ItemInput[], filter: string) {
  const matchesFilter = (item: ItemInput) => (item.text || '').toLowerCase().includes(filter)
  const items = filter ? allItems.filter(matchesFilter) : allItems
  if (items.length === 0) {
    return []
  }
  return items
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

function getValueLabel(value: PropertyValue): string {
  if (isPropertyValueArray(value)) {
    if (value.length <= 1) {
      return value[0] || ''
    } else {
      return `${value.length} selected`
    }
  } else {
    return value
  }
}
