import {testIdProps} from '@github-ui/test-id-props'
import {Button} from '@primer/react'

import {Resources} from '../../strings'
import styles from './filter-input-actions.module.css'

type FilterInputActionsProps = {
  /**
   * Optional handler for the reset changes button. If this callback is not provided,
   * then the button will not be shown.
   */
  onResetChanges?: React.MouseEventHandler<HTMLButtonElement>

  /**
   * Optional handler for the save changes button. If this callback is not provided,
   * then the button will not be shown.
   */
  onSaveChanges?: React.MouseEventHandler<HTMLButtonElement>

  /**
   * Text to display on the save changes button
   */
  saveButtonText?: string

  hideSaveButton?: boolean
  hideResetChangesButton?: boolean
}

export function FilterInputActions({
  onResetChanges,
  onSaveChanges,
  saveButtonText,
  hideSaveButton,
  hideResetChangesButton,
  children,
}: React.PropsWithChildren<FilterInputActionsProps>) {
  if (hideSaveButton && hideResetChangesButton) return null
  return (
    <div className={styles.Box}>
      {children}
      <div className={styles.Box_1} {...testIdProps('filter-state-actions')}>
        {hideResetChangesButton ? null : (
          <Button
            onClick={onResetChanges}
            size="small"
            disabled={!onResetChanges}
            {...testIdProps('filter-actions-reset-changes-button')}
          >
            {Resources.discardChanges}
          </Button>
        )}

        {hideSaveButton ? null : (
          <Button
            variant="primary"
            size="small"
            onClick={onSaveChanges}
            disabled={!onSaveChanges}
            {...testIdProps('filter-actions-save-changes-button')}
          >
            {saveButtonText ?? Resources.saveChanges}
          </Button>
        )}
      </div>
    </div>
  )
}
