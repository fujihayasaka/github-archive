import {GearIcon, PlayIcon} from '@primer/octicons-react'
import {ActionList} from '@primer/react'

import {useTerminalContext} from '../contexts/TerminalContext'
import {commandTaskToString} from '../utilities/command-task-to-string'
import {getCommands} from '../utilities/terminal-tasks'

interface ITerminalMenuCommandActionList {
  showConfigurePanel: () => void
}
export function TerminalMenuCommandActionList({showConfigurePanel}: ITerminalMenuCommandActionList): JSX.Element {
  const {
    state: {tasks},
    executeCommand,
  } = useTerminalContext()

  const taskEntries = getCommands(tasks)

  return (
    <ActionList>
      <ActionList.Group selectionVariant={false}>
        <ActionList.GroupHeading>Commands</ActionList.GroupHeading>
        {taskEntries.map(({task, command}) => {
          return (
            <ActionList.Item onSelect={() => executeCommand(command, task)} key={task}>
              <ActionList.LeadingVisual>
                <PlayIcon />
              </ActionList.LeadingVisual>
              <span className="text-normal">{commandTaskToString(task)}</span>
              <ActionList.Description variant="inline" truncate>
                {command}
              </ActionList.Description>
            </ActionList.Item>
          )
        })}
      </ActionList.Group>
      <>
        <ActionList.Divider />
        <ActionList.Group selectionVariant={false}>
          <ActionList.Item selected={false} onSelect={showConfigurePanel}>
            <ActionList.LeadingVisual>
              <GearIcon />
            </ActionList.LeadingVisual>
            Configure
          </ActionList.Item>
        </ActionList.Group>
      </>
    </ActionList>
  )
}
