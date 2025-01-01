import {isEmptyPropertyValue, isPropertyValueArray} from '@github-ui/custom-properties-types/helpers'
import {SelectPanel} from '@primer/react'
import type {ActionListItemInput as ItemInput} from '@primer/react/deprecated'
import {useState} from 'react'

import type {CustomPropertySelectPanelProps} from './use-select-panel-props'
import {isDefaultGroup, isOptionsGroup, useSelectPanelProps} from './use-select-panel-props'

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
  const selectPanelProps = useSelectPanelProps({
    propertyName,
    defaultValue,
    allowedValues,
    mixed,
    currentSelection: propertyValue,
    anchorProps,
    singleSelectMode: false,
  })

  const [defaultSelected, setDefaultSelected] = useState(
    () => defaultValue && isEmptyPropertyValue(propertyValue) && !mixed,
  )

  const selectedItems = selectPanelProps.items.filter(item => {
    if (defaultSelected) {
      return isDefaultGroup(item) || defaultValue?.includes(item.text || '')
    } else {
      return isOptionsGroup(item) && item.selected
    }
  })

  return (
    <SelectPanel
      {...selectPanelProps}
      anchorRef={anchorRef}
      onSelectedChange={(newItemValues: ItemInput[]) => {
        const {filterValue = ''} = selectPanelProps
        const isFilteredOut = (value: string) => !value.toLowerCase().includes(filterValue.toLowerCase())

        // If default was selected any action would unselect it. Otherwise check update.
        const isDefaultSelected = defaultSelected ? false : newItemValues.some(isDefaultGroup)
        setDefaultSelected(isDefaultSelected)

        if (isDefaultSelected) {
          return onChange([])
        }

        let hiddenSelectedValues: string[] = []
        if (filterValue) {
          // default was selected and user unselects it, set default values as manual selection
          if (defaultSelected && !isDefaultSelected && isPropertyValueArray(defaultValue)) {
            hiddenSelectedValues = defaultValue.filter(isFilteredOut)
          } else {
            hiddenSelectedValues = propertyValue.filter(isFilteredOut)
          }
        }

        const newValues = newItemValues.filter(isOptionsGroup).map(item => item.text || '')
        onChange(hiddenSelectedValues.concat(newValues))
      }}
      onOpenChange={(open, _gesture) => {
        selectPanelProps.onOpenChange(open)
        if (!open) {
          // Reset default state on panel close
          setDefaultSelected(defaultValue && isEmptyPropertyValue(propertyValue) && !mixed)
        }
      }}
      selected={selectedItems}
    />
  )
}
