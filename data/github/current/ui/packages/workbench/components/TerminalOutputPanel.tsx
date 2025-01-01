import {useEffect, useRef} from 'react'

import type {CommandResult} from '../../workspace-editor/utilities/terminal-reducer'
import {useTerminalContext} from '../contexts/TerminalContext'
import TerminalCommand from './TerminalCommand'

export function TerminalOutputPanel(): JSX.Element {
  const {
    state: {history},
    dispatch,
  } = useTerminalContext()

  const toggleCollapse = (command: CommandResult) => {
    const task = command.task
    if (command.collapsed) {
      dispatch({type: 'EXPAND_COMMAND', task})
    } else {
      dispatch({type: 'COLLAPSE_COMMAND', task})
    }
  }

  const outputRef = useRef<HTMLUListElement>(null)
  // Scroll to the bottom when the output renders
  useEffect(() => {
    outputRef.current?.scrollTo({left: 0, top: outputRef.current?.scrollHeight, behavior: 'auto'})
  }, [outputRef])

  return (
    <div className="d-flex flex-column gap-1 p-2">
      {Object.values(history).map((command: CommandResult) => (
        <TerminalCommand key={command.task} command={command} toggleCollapse={toggleCollapse} />
      ))}
    </div>
  )
}
