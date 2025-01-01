import {PencilIcon, PlayIcon, PlusIcon, SquareFillIcon, SyncIcon, TrashIcon} from '@primer/octicons-react'
import {IconButton} from '@primer/react'
import {useCallback} from 'react'

import type {CommandResult} from '../../workspace-editor/utilities/terminal-reducer'
import {useTerminalContext} from '../contexts/TerminalContext'

interface TerminalCommandActionsProps {
  command: CommandResult
  commandExecuted: boolean
  commandForTask?: string
  commandInputRef: React.RefObject<HTMLInputElement>
  editCommandRef: React.RefObject<HTMLButtonElement>
  setEditingCommand: (editingCommand: boolean) => void
}

const TerminalCommandActions: React.FC<TerminalCommandActionsProps> = ({
  command,
  commandForTask,
  commandExecuted,
  commandInputRef,
  editCommandRef,
  setEditingCommand,
}) => {
  const {executeCommand, stopCommand, dispatch: terminalDispatch} = useTerminalContext()
  const {task, exitCode, stopped} = command

  const clearTask = useCallback(() => {
    terminalDispatch({type: 'CLEAR_TASK', task})
  }, [terminalDispatch, task])

  const handleEditCommand = useCallback(() => {
    setTimeout(() => commandInputRef?.current?.focus(), 0)
    setEditingCommand(true)
  }, [commandInputRef, setEditingCommand])

  return (
    <div className="d-flex">
      {!stopped && commandExecuted && exitCode === null ? (
        <IconButton
          icon={SquareFillIcon}
          onClick={() => stopCommand(command)}
          variant="invisible"
          size="small"
          style={{marginLeft: 'auto'}}
          aria-label="Stop execution"
        />
      ) : (
        <>
          {commandForTask ? (
            <IconButton
              aria-label="Configure command"
              icon={PencilIcon}
              variant="invisible"
              onClick={handleEditCommand}
              ref={editCommandRef}
            />
          ) : (
            <IconButton
              aria-label="Add command"
              icon={PlusIcon}
              variant="invisible"
              onClick={handleEditCommand}
              ref={editCommandRef}
            />
          )}
          {!commandExecuted && commandForTask && (
            <IconButton
              aria-label="Execute command"
              icon={PlayIcon}
              variant="invisible"
              onClick={() => executeCommand(commandForTask, task)}
            />
          )}
          {exitCode != null && commandForTask && (
            <>
              <IconButton aria-label="Clear output" icon={TrashIcon} variant="invisible" onClick={clearTask} />
              <IconButton
                icon={SyncIcon}
                onClick={() => {
                  executeCommand(commandForTask, task)
                }}
                variant="invisible"
                aria-label="Re-run"
              />
            </>
          )}
        </>
      )}
    </div>
  )
}

export default TerminalCommandActions
