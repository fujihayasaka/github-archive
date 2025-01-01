import {Spinner, Stack} from '@primer/react'

import styles from './SavingSpinner.module.css'

export function SavingSpinner({isSaving}: {isSaving: boolean}) {
  if (!isSaving) {
    return null
  }
  return (
    <div className={styles.Box}>
      <Stack direction="horizontal" align="center">
        <Spinner size="small" /> <i>Saving...</i>
      </Stack>
    </div>
  )
}
