import type {IconButtonProps} from '@primer/react'
import {IconButton} from '@primer/react'
import {forwardRef} from 'react'

import {type CommandId, getCommandMetadata, getKeybinding} from '../commands'
import {useCommandsContext} from '../commands-context'

export interface CommandIconButtonProps extends Omit<IconButtonProps, 'aria-label' | 'aria-labelledby'> {
  commandId: CommandId
  /** If `aria-label` is not provided, the button will render the command name as its label by default. */
  ['aria-label']?: IconButtonProps['aria-label']
}

/**
 * `CommandButton` is a wrapper around `@primer/react` `Button`, but instead of an `onClick` handler it takes a
 * command ID and handles clicks by emitting command trigger events.
 *
 * If the command is gated by a disabled feature flag, nothing will render.
 */
export const CommandIconButton = forwardRef<HTMLButtonElement, CommandIconButtonProps>(
  ({commandId, ['aria-label']: ariaLabel, onClick: externalOnClick, ...forwardProps}, ref) => {
    const metadata = getCommandMetadata(commandId)
    const {triggerCommand} = useCommandsContext()

    if (!metadata) return null

    return (
      <IconButton
        aria-label={ariaLabel ?? metadata.name}
        onClick={event => {
          externalOnClick?.(event)
          if (!event.defaultPrevented) triggerCommand(commandId, event.nativeEvent)
        }}
        ref={ref}
        keybindingHint={getKeybinding(commandId)}
        {...forwardProps}
      />
    )
  },
)
CommandIconButton.displayName = 'CommandIconButton'
