import {Button} from '@primer/react'
import {useRef, useState} from 'react'

import type {IPickerItem, ItemConfig, PublicDialogProps} from './types'

interface SingleSelectPickerProps<T extends IPickerItem> {
  'aria-describedby'?: string
  selected?: T
  isOpenInitially?: boolean
  itemConfig: ItemConfig<T>
  renderDialog(props: PublicDialogProps): JSX.Element
}

export function SingleSelectPicker<T extends IPickerItem>(props: SingleSelectPickerProps<T>) {
  const [isDialogOpen, setDialogOpen] = useState(false)
  const openDialogButtonRef = useRef<HTMLButtonElement>(null)

  const {selected} = props
  const {
    itemConfig: {onRenderItemLeadingVisual, onRenderItemName, itemName},
  } = props

  return (
    <>
      <Button
        ref={openDialogButtonRef}
        onClick={() => setDialogOpen(true)}
        leadingVisual={
          selected && onRenderItemLeadingVisual ? (onRenderItemLeadingVisual(selected) as React.ReactElement) : null
        }
        aria-describedby={props['aria-describedby']}
      >
        {selected ? onRenderItemName(selected) : `Select a ${itemName}`}
      </Button>
      {isDialogOpen && props.renderDialog({onDismiss: () => setDialogOpen(false), returnFocusRef: openDialogButtonRef})}
    </>
  )
}
