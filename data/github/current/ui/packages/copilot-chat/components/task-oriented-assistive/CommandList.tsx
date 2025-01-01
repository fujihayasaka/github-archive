// eslint-disable-next-line import/no-namespace
import * as icons from '@primer/octicons-react'
import {ActionList} from '@primer/react'
import {clsx} from 'clsx'

import type {Command} from './commands'
import styles from './CommandWindow.module.css'

interface CommandListProps {
  headingText: string
  commands: Array<Command & {selected: boolean}>
  onSelect: (command: Command) => void
}

export function CommandList({headingText, commands, onSelect}: CommandListProps): JSX.Element {
  return (
    <ActionList variant="full" className="my-2">
      <ActionList.Group>
        <ActionList.GroupHeading as="h4" className="ml-n2">
          {headingText}
        </ActionList.GroupHeading>
        {commands.map(command => {
          const Icon = icons[command.iconName]
          return (
            <ActionList.Item
              key={command.name}
              className={clsx('p-2', command.selected ? styles.commandListItemSelected : '')}
              onSelect={() => onSelect(command)}
            >
              <ActionList.LeadingVisual>
                <Icon />
              </ActionList.LeadingVisual>
              {command.name}
              {command.selected && <ActionList.TrailingVisual>Ask Copilot</ActionList.TrailingVisual>}
            </ActionList.Item>
          )
        })}
      </ActionList.Group>
    </ActionList>
  )
}
