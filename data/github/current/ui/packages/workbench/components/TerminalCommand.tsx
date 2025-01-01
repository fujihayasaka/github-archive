import {ChevronDownIcon, ChevronRightIcon, XCircleFillIcon} from '@primer/octicons-react'
import {Button, IconButton, TextInput} from '@primer/react'
import {clsx} from 'clsx'
import type React from 'react'
import {useCallback, useEffect, useRef, useState} from 'react'

import TerminalCommandStatusIcon from '../../workspace-editor/components/TerminalCommandStatusIcon'
import {commandTaskToString} from '../../workspace-editor/utilities/command-task-to-string'
import {formatCommandDuration} from '../../workspace-editor/utilities/format-command-duration'
import {generateCommandStatusText} from '../../workspace-editor/utilities/generate-command-status-text'
import type {CommandResult} from '../../workspace-editor/utilities/terminal-reducer'
import {getCommandForTask} from '../../workspace-editor/utilities/terminal-tasks'
import {useTerminalContext} from '../contexts/TerminalContext'
import TerminalCommandActions from './TerminalCommandActions'

interface TerminalCommandProps {
  toggleCollapse: (command: CommandResult) => void
  command: CommandResult
}

const TerminalCommand: React.FC<TerminalCommandProps> = ({toggleCollapse, command}) => {
  const {
    state: {tasks},
    dispatch: terminalDispatch,
  } = useTerminalContext()
  const {task, exitCode, channel, collapsed, output, loading, startTime, endTime} = command

  // Get the command preview for the task and convert any new lines to && to make it fit on one line
  const commandForTask = getCommandForTask(tasks, task)
  const commandInputRef = useRef<HTMLInputElement>(null)
  const editCommandRef = useRef<HTMLButtonElement>(null)
  const [commandInputValue, setCommandInputValue] = useState(commandForTask)
  const [editingCommand, setEditingCommand] = useState(false)
  const [commandDuration, setCommandDuration] = useState('')

  // If the command is running or has completed, the channel should be set
  const commandExecuted = channel != null || exitCode != null || loading
  const backgroundColor = commandForTask ? 'bgColor-muted' : 'bgColor-default'

  useEffect(() => {
    // If the start time doesn't exist, the command is either loading or hasn't been started by the user (meaning this won't be shown)
    if (!startTime) {
      return
    }

    // If end time exists, show the final duration and return early so the timer stops
    if (endTime) {
      setCommandDuration(formatCommandDuration(startTime, endTime))
      return
    }

    // Set initial duration
    setCommandDuration('0s')

    // Update the duration every second
    const interval = setInterval(() => {
      setCommandDuration(formatCommandDuration(startTime, new Date()))
    }, 1000)

    return () => clearInterval(interval)
  }, [commandExecuted, startTime, endTime, loading, channel])

  const updateCommand = useCallback(() => {
    // If the command has changed, update it
    if (commandInputValue !== commandForTask) {
      terminalDispatch({type: 'SET_TASK', task, command: commandInputValue || ''})
    }

    setTimeout(() => editCommandRef.current?.focus(), 0)
    setEditingCommand(false)
  }, [terminalDispatch, task, commandInputValue, commandForTask])

  const resetCommand = useCallback(() => {
    setCommandInputValue(commandForTask)
    setTimeout(() => editCommandRef.current?.focus(), 0)
    setEditingCommand(false)
  }, [commandForTask])

  const renderOutput = () => {
    return (
      <pre className="text-mono px-3 py-2">
        <span className="text-bold mb-2">$ {commandForTask}</span>
        {`\n\n${output}`}
      </pre>
    )
  }

  const innerContent = collapsed ? null : renderOutput()

  if (command === undefined) {
    return <></>
  }

  return (
    <div key={command.task} className={clsx('d-flex flex-column rounded-2', backgroundColor)}>
      <div
        className={clsx(
          'd-flex flex-items-center gap-2 px-1 py-1 position-sticky top-0 rounded-2',
          backgroundColor,
          commandExecuted ? '' : 'border-box border-dashed borderColor-muted',
        )}
        style={{height: '44px', borderWidth: commandExecuted ? '' : '2px'}}
      >
        {editingCommand ? (
          <div className="d-flex flex-justify-between flex-items-center gap-1 width-full">
            <TextInput
              ref={commandInputRef}
              value={commandInputValue}
              onChange={e => {
                setCommandInputValue(e.target.value)
              }}
              onKeyDown={e => {
                // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
                if (e.key === 'Enter') {
                  updateCommand()
                }

                // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
                if (e.key === 'Escape') {
                  resetCommand()
                }
              }}
              placeholder={commandForTask}
              className="width-full"
              trailingAction={
                <TextInput.Action
                  icon={XCircleFillIcon}
                  aria-label="Discard changes"
                  className="fgColor-muted"
                  onClick={() => {
                    resetCommand()
                  }}
                />
              }
            />
            <Button name="Save" type="submit" onClick={updateCommand}>
              Save
            </Button>
          </div>
        ) : (
          <>
            <IconButton
              aria-label={collapsed ? 'Expand' : 'Collapse'}
              icon={collapsed ? ChevronRightIcon : ChevronDownIcon}
              variant="invisible"
              size="small"
              onClick={() => toggleCollapse(command)}
              disabled={!commandExecuted}
            />
            <TerminalCommandStatusIcon command={command} />
            <div className="d-flex flex-justify-between flex-items-center width-full">
              <div className="d-flex f6">
                <div style={{width: '35px'}}>
                  <span className="text-bold">{commandTaskToString(task)}</span>
                </div>
                <span className="fgColor-muted">
                  {generateCommandStatusText(command, commandExecuted, commandDuration, commandForTask)}
                </span>
              </div>
              <TerminalCommandActions
                command={command}
                commandForTask={commandForTask}
                commandExecuted={commandExecuted}
                commandInputRef={commandInputRef}
                editCommandRef={editCommandRef}
                setEditingCommand={setEditingCommand}
              />
            </div>
          </>
        )}
      </div>
      {innerContent}
    </div>
  )
}

export default TerminalCommand
