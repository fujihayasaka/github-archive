import {CommandButton, GlobalCommands} from '@github-ui/ui-commands'
import {PlayIcon, SquareFillIcon} from '@primer/octicons-react'
import {Button} from '@primer/react'

type PromptRunButtonProps = {
  className?: string
  isRunning: boolean
  canRun: boolean
  handleStop?: () => void
  handleRun?: () => void
  disabled?: boolean
}

export function PromptRunButton({className, isRunning, canRun, handleStop, handleRun, disabled}: PromptRunButtonProps) {
  return (
    <>
      <GlobalCommands commands={{'github:submit-form': () => canRun && handleRun && handleRun()}} />
      {isRunning ? (
        <Button
          size="small"
          className={className}
          leadingVisual={SquareFillIcon}
          variant="danger"
          onClick={() => handleStop && handleStop()}
        >
          Stop
        </Button>
      ) : (
        <CommandButton
          size="small"
          className={className}
          leadingVisual={PlayIcon}
          variant="primary"
          commandId="github:submit-form"
          disabled={disabled || canRun === false}
          showKeybindingHint
        >
          Run
        </CommandButton>
      )}
    </>
  )
}
