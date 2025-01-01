import {Button} from '@primer/react'
import {useRef, useState} from 'react'

import type {IPickerItem, ItemConfig, PublicDialogProps} from './types'

interface MultiSelectPickerProps<T extends IPickerItem> {
  'aria-describedby'?: string
  selected?: T[]
  isOpenInitially?: boolean
  itemConfig: ItemConfig<T>
  renderDialog(props: PublicDialogProps): JSX.Element
}

export function MultiSelectPicker<T extends IPickerItem>(props: MultiSelectPickerProps<T>) {
  const [isDialogOpen, setDialogOpen] = useState(Boolean(props.isOpenInitially))
  const openDialogButtonRef = useRef<HTMLButtonElement>(null)

  const {selected} = props
  const count = selected?.length
  const first = selected?.[0]
  const {
    itemConfig: {onRenderItemLeadingVisual, itemName, itemsName},
  } = props

  return (
    <>
      <Button
        ref={openDialogButtonRef}
        onClick={() => setDialogOpen(true)}
        leadingVisual={
          first && onRenderItemLeadingVisual ? (onRenderItemLeadingVisual(first) as React.ReactElement) : null
        }
        aria-describedby={props['aria-describedby']}
      >
        {count ? `${count} ${count > 1 ? itemsName : itemName} selected` : `Select ${itemsName}`}
      </Button>
      {isDialogOpen && props.renderDialog({onDismiss: () => setDialogOpen(false), returnFocusRef: openDialogButtonRef})}
    </>
  )
}
