import {useLocalStorage} from '@github-ui/use-safe-storage/local-storage'
import {Button, Checkbox, FormControl} from '@primer/react'
import type {DialogProps} from '@primer/react/experimental'
import {Dialog, KeybindingHint} from '@primer/react/experimental'
import {clsx} from 'clsx'

import {DragAndDropResources} from '../../strings'
import styles from './keyboard-reorder-instructions-modal.module.css'

type KeyboardReorderInstructionsModalProps = {
  isOpen: boolean
  onClose: () => void
}

export const HideKeyboardReorderInstructionsModalKey = 'hideReorderKeyboardInstructions'

/* Modal component that displays keyboard instructions to perform drag and drop actions.
 * using the Primer Dialog component.
 */
export const KeyboardReorderInstructionsModal = ({isOpen, onClose}: KeyboardReorderInstructionsModalProps) => {
  if (!isOpen) return null

  return (
    <Dialog
      title="How to move objects via keyboard"
      subtitle="This navigation is only available when move mode is activated."
      onClose={onClose}
      renderFooter={() => (
        <Dialog.Footer className={styles.Dialog_Footer}>
          <KeyboardReorderInstructionsFooter onClose={onClose} />
        </Dialog.Footer>
      )}
    >
      <div className={styles.instructionContainerSx}>
        <div className={styles.instructionSx}>
          <span>{DragAndDropResources.cancelDrag}</span>
          <KeybindingHint keys="esc" />
        </div>
        <div className={styles.instructionSx}>
          <span>{DragAndDropResources.moveDown}</span>
          <KeybindingHint keys="down" />
        </div>
        <div className={styles.instructionSx}>
          <span>{DragAndDropResources.moveUp}</span>
          <KeybindingHint keys="up" />
        </div>
        <div className={clsx(styles.instructionSx, styles.Box_2)}>
          <span>{DragAndDropResources.endDrag}</span>
          <div>
            <KeybindingHint keys="enter" />
            <span> or </span>
            <KeybindingHint keys="space" />
          </div>
        </div>
      </div>
    </Dialog>
  )
}

type KeyboardReorderInstructionsFooterProps = {
  onClose: () => void
} & DialogProps

export const KeyboardReorderInstructionsFooter = ({onClose}: KeyboardReorderInstructionsFooterProps) => {
  const [doNotShowAgain, setDoNotShowAgain] = useLocalStorage(HideKeyboardReorderInstructionsModalKey, false)
  return (
    <div className={styles.Box_3}>
      <FormControl className={styles.FormControl}>
        <Checkbox checked={doNotShowAgain} onChange={() => setDoNotShowAgain(!doNotShowAgain)} />
        <FormControl.Label>{`Don't show this again`}</FormControl.Label>
      </FormControl>
      <div className={styles.Box_4}>
        <Button onClick={onClose}>Close</Button>
      </div>
    </div>
  )
}
