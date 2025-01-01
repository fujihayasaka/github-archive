import {PencilIcon} from '@primer/octicons-react'
import {IconButton} from '@primer/react'
import {useRef, useState} from 'react'

import {TokenizedQuery} from './components/TokenizedQuery'
import {DynamicReposPickerDialog} from './DynamicReposPickerDialog'
import type {DynamicMatchingProps, ReposPickerCommonProps} from './types'

export function DynamicReposPicker(props: DynamicMatchingProps & ReposPickerCommonProps) {
  const [isDialogOpen, setDialogOpen] = useState(false)
  const openDialogButtonRef = useRef<HTMLAnchorElement>(null)

  return (
    <>
      <div className="d-flex flex-items-center gap-2">
        {props.query ? <TokenizedQuery query={props.query} /> : 'No filter'}
        <IconButton
          aria-label="Open filter dialog"
          ref={openDialogButtonRef}
          onClick={() => setDialogOpen(true)}
          icon={PencilIcon}
        />
        {isDialogOpen && (
          <DynamicReposPickerDialog
            {...props}
            onDismiss={() => setDialogOpen(false)}
            returnFocusRef={openDialogButtonRef}
          />
        )}
      </div>
    </>
  )
}
