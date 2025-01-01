import {GearIcon, StopIcon, SyncIcon, TerminalIcon} from '@primer/octicons-react'
import {ActionList} from '@primer/react'

import {useTerminalContext} from '../contexts/TerminalContext'
import type {CommandResult} from '../utilities/terminal-reducer'

interface ITerminalMenuCommandRunningList {
  showTerminal: () => void
  showConfigurePanel: () => void
  runningCommand: CommandResult
}
export function TerminalMenuCommandRunningList({
  showTerminal,
  showConfigurePanel,
  runningCommand,
}: ITerminalMenuCommandRunningList): JSX.Element {
  const {stopCommand, restartCommand} = useTerminalContext()
  return (
    <ActionList>
      <ActionList.Group selectionVariant={false}>
        <ActionList.Item onSelect={() => stopCommand(runningCommand)}>
          <ActionList.LeadingVisual>
            <StopIcon fill="var(--fgColor-closed)" />
          </ActionList.LeadingVisual>
          <span className="text-normal">Stop</span>
        </ActionList.Item>
        <ActionList.Item
          onSelect={() => {
            restartCommand(runningCommand)
          }}
        >
          <ActionList.LeadingVisual>
            <SyncIcon />
          </ActionList.LeadingVisual>
          <span className="text-normal">Restart</span>
        </ActionList.Item>
        <ActionList.Item onSelect={showTerminal}>
          <ActionList.LeadingVisual>
            <TerminalIcon />
          </ActionList.LeadingVisual>
          <span className="text-normal">View output</span>
        </ActionList.Item>
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
