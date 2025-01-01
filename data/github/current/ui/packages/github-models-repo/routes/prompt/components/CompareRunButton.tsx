import {Button, Tooltip} from '@primer/react'
import {PlayIcon, SquareFillIcon} from '@primer/octicons-react'

type CompareRunButtonProps = {
  className?: string
  isRunning: boolean
  canRun: boolean
  tooltipText?: string
  handleStop: () => void
  handleRun: () => void
}

export function CompareRunButton({
  className,
  isRunning,
  canRun,
  tooltipText = '',
  handleStop,
  handleRun,
}: CompareRunButtonProps) {
  if (isRunning) {
    return (
      <Button size="small" leadingVisual={SquareFillIcon} className={className} variant="danger" onClick={handleStop}>
        Stop
      </Button>
    )
  }

  if (canRun) {
    return (
      <Button size="small" leadingVisual={PlayIcon} className={className} variant="primary" onClick={handleRun}>
        Run
      </Button>
    )
  }

  return (
    <Tooltip text={tooltipText}>
      <Button size="small" leadingVisual={PlayIcon} className={className} variant="primary" inactive>
        Run
      </Button>
    </Tooltip>
  )
}
