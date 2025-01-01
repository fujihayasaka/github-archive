import {testIdProps} from '@github-ui/test-id-props'
import {AlertIcon} from '@primer/octicons-react'
import {Button} from '@primer/react'
import {Dialog} from '@primer/react/deprecated'
import {useEffect, useState} from 'react'

import styles from './command-palette-warning.module.css'

const shortcutFromEvent = (e: KeyboardEvent | React.KeyboardEvent) => {
  let str = ''

  // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
  if (e.ctrlKey) str += 'Ctrl+'
  // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
  if (e.metaKey) str += 'Meta+'
  if (e.shiftKey) str += 'Shift+'

  // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
  str += e.key

  return str
}

function isMacOS() {
  return /^mac/i.test(window.navigator.platform)
}

const platformMeta = isMacOS() ? 'Meta' : 'Ctrl'

export function CommandPaletteWarning() {
  const [isOpen, setIsOpen] = useState<boolean>(false)

  useEffect(() => {
    const listener = (ev: KeyboardEvent) => {
      const shortcut = shortcutFromEvent(ev)
      if (shortcut === `${platformMeta}+k`) {
        setIsOpen(true)
      }
    }

    window.addEventListener('keydown', listener)

    return () => {
      window.removeEventListener('keydown', listener)
    }
  }, [])

  return (
    <Dialog isOpen={isOpen} onDismiss={() => setIsOpen(false)} aria-labelledby="label">
      <Dialog.Header>
        <div>
          <AlertIcon />{' '}
          <span {...testIdProps('command_palette_warning_title')} className={styles.Text}>
            Command palette not available in staging
          </span>
        </div>
      </Dialog.Header>
      <div className={styles.Box}>
        <span id="label" className={styles.Text_1}>
          The command palette implementation now lives in <code>github/github</code>, so tests that try to access the
          command palette in staging are now a no-op.
        </span>
        <div className={styles.Box_1}>
          <Button variant="primary" onClick={() => setIsOpen(false)}>
            Close
          </Button>
        </div>
      </div>
    </Dialog>
  )
}
