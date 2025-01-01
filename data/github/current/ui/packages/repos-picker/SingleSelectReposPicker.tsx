import {Button} from '@primer/react'
import {useRef, useState} from 'react'

import {ListItemRepoIcon} from './components/ListItemRepoIcon'
import {SingleSelectReposPickerDialog} from './SingleSelectReposPickerDialog'
import type {SingleSelectProps} from './types'

export function SingleSelectReposPicker(props: SingleSelectProps) {
  const [isDialogOpen, setDialogOpen] = useState(false)
  const openDialogButtonRef = useRef<HTMLButtonElement>(null)

  const {selected} = props
  return (
    <>
      <Button
        ref={openDialogButtonRef}
        onClick={() => setDialogOpen(true)}
        leadingVisual={selected ? <ListItemRepoIcon visibility={selected.visibility} /> : null}
      >
        {selected ? selected.name : 'Select a repository'}
      </Button>
      {isDialogOpen && (
        <SingleSelectReposPickerDialog
          {...props}
          onDismiss={() => setDialogOpen(false)}
          returnFocusRef={openDialogButtonRef}
        />
      )}
    </>
  )
}
