import {SelectPanel} from '@primer/react'
import type {ActionListItemInput as ItemInput} from '@primer/react/deprecated'

import type {CustomPropertySelectPanelProps} from './use-select-panel-props'
import {isDefaultGroup, isEmptyGroup, useSelectPanelProps} from './use-select-panel-props'

interface CustomPropertySingleSelectPanelProps extends CustomPropertySelectPanelProps {
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
  const selectPanelProps = useSelectPanelProps({
    propertyName,
    defaultValue,
    allowedValues,
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
