import {GlobalCommands, type CommandId} from '@github-ui/ui-commands'
import {useCallback, useRef, useState, type RefObject} from 'react'

type LazyItemPickerProps = {
  anchorElement: (props: React.HTMLAttributes<HTMLElement>, ref: RefObject<HTMLButtonElement>) => JSX.Element
  createChild: () => JSX.Element
  insidePortal?: boolean
  keybindingCommandId?: CommandId
}

export function LazyItemPicker({anchorElement, createChild, keybindingCommandId}: LazyItemPickerProps): JSX.Element {
  const [wasTriggered, setWasTriggered] = useState(false)
  const anchorRef = useRef<HTMLButtonElement>(null)

  const handleKeyPress = useCallback(() => {
    if (!wasTriggered) {
      setWasTriggered(true)
    }
  }, [wasTriggered, setWasTriggered])

  if (!wasTriggered) {
    return (
      <>
        {keybindingCommandId && <GlobalCommands commands={{[keybindingCommandId]: handleKeyPress}} />}

        {anchorElement(
          {onClick: () => setWasTriggered(true)},
          // eslint-disable-next-line react-compiler/react-compiler
          anchorRef,
        )}
      </>
    )
  }

  return createChild()
}
