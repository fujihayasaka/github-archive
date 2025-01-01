import {useState} from 'react'
import {GlobalCommands} from '@github-ui/ui-commands'
import {ShortcutsDialog} from './components/ShortcutsDialog'

interface KeyboardShortcutsDialog {
  docsUrl: string
}

export function KeyboardShortcutsDialog({docsUrl}: KeyboardShortcutsDialog) {
  const [isVisible, setVisible] = useState(false)

  return (
    <>
      <GlobalCommands commands={{'keyboard-shortcuts-dialog:show-dialog': () => setVisible(true)}} />
      <ShortcutsDialog visible={isVisible} onVisibleChange={setVisible} docsUrl={docsUrl} />
    </>
  )
}
