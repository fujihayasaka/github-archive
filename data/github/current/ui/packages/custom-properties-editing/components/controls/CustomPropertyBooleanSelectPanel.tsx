import {SelectPanel} from '@primer/react'
import type {ActionListItemInput as ItemInput} from '@primer/react/deprecated'

import type {CustomPropertySelectPanelProps} from './use-select-panel-props'
import {isDefaultGroup, isEmptyGroup, useSelectPanelProps} from './use-select-panel-props'

const booleanAllowedValues = ['true', 'false']

interface CustomPropertyBooleanSelectPanelProps extends Omit<CustomPropertySelectPanelProps, 'allowedValues'> {
  propertyValue: string
}

export function CustomPropertyBooleanSelectPanel({
  anchorRef,
  propertyName,
  defaultValue,
  propertyValue,
  mixed,
  onChange,
  anchorProps,
}: CustomPropertyBooleanSelectPanelProps) {
  const selectPanelProps = useSelectPanelProps({
    propertyName,
    defaultValue,
    allowedValues: booleanAllowedValues,
    mixed,
    currentSelection: propertyValue ? [propertyValue] : [],
    anchorProps,
    singleSelectMode: true,
  })
  const selectedItem = selectPanelProps.items.find(item => item.selected)

  return (
    <SelectPanel
      {...selectPanelProps}
      anchorRef={anchorRef}
      onSelectedChange={(newItemValue?: ItemInput) => {
        if (!newItemValue) {
          // User clicked on the selected option, ignore and close panel.
          return
        }

        if (isDefaultGroup(newItemValue) || isEmptyGroup(newItemValue)) {
          onChange('')
        } else {
          onChange(newItemValue.text || '')
        }
      }}
      selected={selectedItem}
    />
  )
}
