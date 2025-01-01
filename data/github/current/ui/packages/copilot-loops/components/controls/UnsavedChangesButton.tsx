import {Button, ConfirmationDialog} from '@primer/react'
import {UndoIcon} from '@primer/octicons-react'
import {useResetLoop} from '../../hooks/mutations/use-reset-loop'
import {useState} from 'react'
import {sendEvent} from '@github-ui/hydro-analytics'
import styles from './UnsavedChangesButton.module.css'
import {clsx} from 'clsx'
import {useLoop} from '../../hooks/queries/use-loop'

const WarningDot = () => <div className={styles.warningDot} />

export function UnsavedChangesButton() {
  const {data: loop} = useLoop()
  const {mutate: resetLoop, isPending: isResetPending} = useResetLoop()
  const [isActive, setIsActive] = useState(false)
  const [showConfirmation, setShowConfirmation] = useState(false)
  const showRevert = isActive || showConfirmation

  const handleResetConfirm = () => {
    if (!loop) return

    resetLoop(loop?.id)
    setShowConfirmation(false)
    sendEvent('dotcom_chat.activate', {target: 'LOOP_RESET_CHANGES', mode: 'loops'})
  }

  const handleResetClick = () => {
    if (isResetPending || !loop) return
    setShowConfirmation(true)
  }

  return (
    <>
      <Button
        className={clsx(styles.button, showRevert && styles.active)}
        variant="invisible"
        onMouseEnter={() => setIsActive(true)}
        onMouseLeave={() => setIsActive(false)}
        onFocus={() => setIsActive(true)}
        onBlur={() => setIsActive(false)}
        onClick={handleResetClick}
        leadingVisual={showRevert ? <UndoIcon className={styles.undoIcon} /> : <WarningDot />}
      >
        {showRevert ? 'Revert changes' : 'Unsaved changes'}
      </Button>

      {showConfirmation && (
        <ConfirmationDialog
          title="Revert changes"
          onClose={gesture => {
            if (gesture === 'confirm') {
              handleResetConfirm()
            } else {
              setShowConfirmation(false)
            }
          }}
          confirmButtonContent="Revert"
          confirmButtonType="danger"
        >
          Are you sure you want to revert all changes since your last save? This action cannot be undone.
        </ConfirmationDialog>
      )}
    </>
  )
}
