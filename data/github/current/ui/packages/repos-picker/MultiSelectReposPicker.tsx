import {Button} from '@primer/react'
import {useRef, useState} from 'react'

import {ListItemRepoIcon} from './components/ListItemRepoIcon'
import {MultiSelectReposPickerDialog} from './MultiSelectReposPickerDialog'
import type {MultiSelectProps} from './types'

export function MultiSelectReposPicker(props: MultiSelectProps) {
  const [isDialogOpen, setDialogOpen] = useState(false)
  const openDialogButtonRef = useRef<HTMLButtonElement>(null)

  const {selected} = props
  const count = selected?.length
  return (
    <>
      <Button
        ref={openDialogButtonRef}
        onClick={() => setDialogOpen(true)}
        leadingVisual={selected?.[0] ? <ListItemRepoIcon visibility={selected[0].visibility} /> : null}
      >
        {count ? `${count} ${count > 1 ? 'repositories' : 'repository'} selected` : 'Select repositories'}
      </Button>
      {isDialogOpen && (
        <MultiSelectReposPickerDialog
          {...props}
          onDismiss={() => setDialogOpen(false)}
          returnFocusRef={openDialogButtonRef}
        />
      )}
    </>
  )
}
