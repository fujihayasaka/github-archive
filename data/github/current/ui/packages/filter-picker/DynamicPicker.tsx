import {PencilIcon} from '@primer/octicons-react'
import {IconButton} from '@primer/react'
import {useId, useRef, useState} from 'react'

import {TokenizedQuery} from './TokenizedQuery'
import type {PublicDialogProps} from './types'

interface DynamicPickerProps {
  'aria-describedby'?: string
  query?: string
  isOpenInitially?: boolean
  renderDialog(props: PublicDialogProps): JSX.Element
}

export function DynamicPicker(props: DynamicPickerProps) {
  const [isDialogOpen, setDialogOpen] = useState(Boolean(props.isOpenInitially))
  const openDialogButtonRef = useRef<HTMLAnchorElement>(null)

  const anchorLabelId = useId()

  return (
    <>
      <div className="d-flex flex-items-center gap-2">
        <span id={anchorLabelId}>
          {props.query ? (
            <>
              <span className="sr-only">Active filter: </span>
              <TokenizedQuery query={props.query} />
            </>
          ) : (
            'No filter'
          )}
        </span>
        <IconButton
          ref={openDialogButtonRef}
          onClick={() => setDialogOpen(true)}
          icon={PencilIcon}
          aria-label="Open filter dialog"
          aria-describedby={props['aria-describedby'] ?? anchorLabelId}
        />
        {isDialogOpen &&
          props.renderDialog({onDismiss: () => setDialogOpen(false), returnFocusRef: openDialogButtonRef})}
      </div>
    </>
  )
}
