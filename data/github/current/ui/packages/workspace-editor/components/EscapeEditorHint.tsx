import {isMacOS} from '@github-ui/get-os'
import {useLocalStorage} from '@github-ui/use-safe-storage/local-storage'
import {XIcon} from '@primer/octicons-react'
import {IconButton} from '@primer/react'
import {KeybindingHint} from '@primer/react/experimental'

import styles from './EscapeEditorHint.module.css'

const macForwardHintString = 'Alt+Tab'
const macBackwardHintString = 'Alt+Shift+Tab'
const windowsForwardHintString = 'Ctrl+M+Tab'
const windowsBackwardHintString = 'Ctrl+M+Shift+Tab'
export const escapeEditorHintAltText = isMacOS()
  ? 'Use Option + Tab or Shift + Option + Tab to escape the editor.'
  : 'Use Control + M + Tab or Shift + Control + M + Shift + Tab to escape the editor.'

export function EscapeEditorHint() {
  const [escapeHintHidden, setEscapeHintHidden] = useLocalStorage('hadron-editor/hide-escape-hint', false)

  const forwardTabHint = (
    <KeybindingHint keys={isMacOS() ? macForwardHintString : windowsForwardHintString} format="full" />
  )
  const backwardTabHint = (
    <KeybindingHint keys={isMacOS() ? macBackwardHintString : windowsBackwardHintString} format="full" />
  )

  return escapeHintHidden ? null : (
    <div className={styles.hint}>
      <p className={styles.hintContent}>
        Use {forwardTabHint} or {backwardTabHint} to escape the editor.
      </p>
      <IconButton
        aria-label="Dismiss hint"
        icon={XIcon}
        variant="invisible"
        size="small"
        tooltipDirection="nw"
        onClick={() => setEscapeHintHidden(true)}
      />
    </div>
  )
}
