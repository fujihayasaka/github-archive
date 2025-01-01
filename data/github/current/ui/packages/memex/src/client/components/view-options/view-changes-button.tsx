import {testIdProps} from '@github-ui/test-id-props'
import {Button, Stack} from '@primer/react'
import {useCallback} from 'react'

import {ViewOptionsMenuUI} from '../../api/stats/contracts'
import {ViewerPrivileges} from '../../helpers/viewer-privileges'
import type {BaseViewState, ViewIsDirtyStates} from '../../hooks/use-view-state-reducer/types'
import {useViews} from '../../hooks/use-views'
import {Resources} from '../../strings'
import styles from './view-changes-button.module.css'

export function ViewChangeButtons({
  view,
  setOpen,
}: {
  view: BaseViewState & ViewIsDirtyStates
  setOpen: React.Dispatch<React.SetStateAction<boolean>>
}) {
  const {hasWritePermissions} = ViewerPrivileges()
  const {saveCurrentViewState, resetViewState} = useViews()

  const handleSaveView = useCallback(async () => {
    await saveCurrentViewState(view.number, {
      ui: ViewOptionsMenuUI,
    })
    setOpen(false)
  }, [saveCurrentViewState, setOpen, view.number])

  const handleResetChanges = useCallback(async () => {
    resetViewState(view.number, {
      ui: ViewOptionsMenuUI,
    })

    setOpen(false)
  }, [resetViewState, setOpen, view.number])

  return (
    <Stack direction="horizontal" justify="end" gap="condensed" padding="normal" className={styles.Footer}>
      <Button onClick={handleResetChanges} {...testIdProps('view-options-menu-reset-changes-button')}>
        {Resources.discardChanges}
      </Button>
      {hasWritePermissions && !view.isDeleted ? (
        <Button
          variant="primary"
          onClick={handleSaveView}
          disabled={!view.isViewStateDirty}
          {...testIdProps('view-options-menu-save-changes-button')}
        >
          {Resources.saveChanges}
        </Button>
      ) : null}
    </Stack>
  )
}
