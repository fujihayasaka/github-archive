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
          {
            onClick: () => setWasTriggered(true),
            onKeyPress: (event: React.KeyboardEvent<HTMLLIElement>) => {
              // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
              if (event.key === 'Enter' || event.key === ' ') {
                event.preventDefault()
                setWasTriggered(true)
              }
            },
          },

          anchorRef,
        )}
      </>
    )
  }

  return createChild()
}
