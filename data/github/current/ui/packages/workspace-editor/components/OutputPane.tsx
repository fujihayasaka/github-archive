import {useEffect, useRef} from 'react'

import {useTerminalContext} from '../contexts/TerminalContext'
import type {CommandResult} from '../utilities/terminal-reducer'
import HistoryItem from './HistoryItem'
import {TerminalMenu} from './TerminalMenu'

interface OutputPanelProps {
  onTerminalVisibilityChange: () => void
  isCodespaceReady: boolean
}

export function OutputPane({onTerminalVisibilityChange, isCodespaceReady}: OutputPanelProps): JSX.Element {
  const {
    state: {history, currentCommand},
    dispatch,
  } = useTerminalContext()

  const toggleCollapse = (command: CommandResult) => {
    const commandId = command.id
    if (command.collapsed) {
      dispatch({type: 'EXPAND_COMMAND', id: commandId})
    } else {
      dispatch({type: 'COLLAPSE_COMMAND', id: commandId})
    }
  }

  const renderBuildMenu = () => (
    <div className="gap-3 p-6">
      <div className="d-flex flex-column flex-items-center gap-3 p-6">
        <p className="m-0 color-fg-muted">Run a command to view its output.</p>
        <TerminalMenu onTerminalVisibilityChange={onTerminalVisibilityChange} isCodespaceReady={isCodespaceReady} />
      </div>
    </div>
  )

  const outputRef = useRef<HTMLUListElement>(null)
  // Scroll to the bottom when the output renders
  useEffect(() => {
    outputRef.current?.scrollTo({left: 0, top: outputRef.current?.scrollHeight, behavior: 'auto'})
  }, [outputRef])

  const allCommands = [...Object.values(history)]
  if (currentCommand !== null) {
    allCommands.push(currentCommand)
  }

  return (
    <>
      {allCommands.length ? (
        <>
          {allCommands.map((command: CommandResult, idx: number) => (
            <HistoryItem
              key={command.id}
              command={command}
              toggleCollapse={toggleCollapse}
              isLastItem={idx === allCommands.length - 1}
            />
          ))}
        </>
      ) : (
        renderBuildMenu()
      )}
    </>
  )
}
