import {GearIcon, PlayIcon, TriangleDownIcon} from '@primer/octicons-react'
import {ActionMenu, Button, ButtonGroup, IconButton} from '@primer/react'
import {Tooltip} from '@primer/react/next'
import {useRef, useState} from 'react'

import {useTerminalContext} from '../contexts/TerminalContext'
import {activeCommand, getFirstCommand} from '../utilities/terminal-tasks'
import {TerminalConfigurationPanel} from './TerminalConfigurationPanel'
import styles from './TerminalMenu.module.css'
import {TerminalMenuCommandActionList} from './TerminalMenuCommandActionList'
import {TerminalMenuCommandRunningList} from './TerminalMenuCommandRunningList'

interface ITerminalMenuProps {
  onTerminalVisibilityChange: (visibility: 'visible' | 'hidden') => void
  isCodespaceReady: boolean
}

export function TerminalMenu({onTerminalVisibilityChange, isCodespaceReady}: ITerminalMenuProps): JSX.Element {
  const [isConfigurePanelOpen, setIsConfigurePanelOpen] = useState(false)
  const {
    state: {currentCommand, tasks},
    executeCommand,
  } = useTerminalContext()

  let rootButton: JSX.Element
  const commandPickerButtonRef = useRef<HTMLDivElement | null>(null)

  const firstCommand = getFirstCommand(tasks)
  if (firstCommand) {
    rootButton = (
      <Button
        className={styles.anchorButton}
        leadingVisual={PlayIcon}
        aria-label="Run command"
        size="medium"
        onClick={() => {
          if (!currentCommand && isCodespaceReady) {
            executeCommand(firstCommand.command, firstCommand.name)
          }
        }}
        inactive={!isCodespaceReady}
      >
        {currentCommand ? activeCommand(currentCommand) : firstCommand.name}
      </Button>
    )
  } else {
    rootButton = (
      <Button
        inactive={!isCodespaceReady}
        className={styles.anchorButton}
        leadingVisual={GearIcon}
        aria-label="Configure commands"
        size="medium"
        onClick={() => {
          setIsConfigurePanelOpen(true)
        }}
      >
        Configure
      </Button>
    )
  }

  const commandExecutionPickerButton = (
    <IconButton
      inactive={!isCodespaceReady}
      className={styles.commandExecutionPicker}
      icon={TriangleDownIcon}
      aria-label="Command execution picker"
      size="medium"
    />
  )

  const activeButtonGroup = (
    <>
      <ButtonGroup>
        {rootButton}
        <ActionMenu anchorRef={commandPickerButtonRef}>
          <ActionMenu.Anchor>{commandExecutionPickerButton}</ActionMenu.Anchor>
          <ActionMenu.Overlay width="small">
            {currentCommand !== null ? (
              <TerminalMenuCommandRunningList
                showTerminal={() => onTerminalVisibilityChange('visible')}
                showConfigurePanel={() => setIsConfigurePanelOpen(true)}
                runningCommand={currentCommand}
              />
            ) : (
              <TerminalMenuCommandActionList showConfigurePanel={() => setIsConfigurePanelOpen(true)} />
            )}
          </ActionMenu.Overlay>
        </ActionMenu>
      </ButtonGroup>
      {isConfigurePanelOpen && (
        <TerminalConfigurationPanel
          returnFocusRef={commandPickerButtonRef}
          close={() => setIsConfigurePanelOpen(false)}
        />
      )}
    </>
  )

  const inactiveButtonGroup = (
    <>
      <Tooltip text={'Reconnect to Codespace. Commands are enabled only when connected.'} type={'description'}>
        <ButtonGroup>
          {rootButton}
          {commandExecutionPickerButton}
        </ButtonGroup>
      </Tooltip>
    </>
  )

  return isCodespaceReady ? activeButtonGroup : inactiveButtonGroup
}
