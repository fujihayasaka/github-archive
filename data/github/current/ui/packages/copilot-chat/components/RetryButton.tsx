import {SyncIcon, TriangleDownIcon} from '@primer/octicons-react'
import {Button, IconButton} from '@primer/react'
import {clsx} from 'clsx'

import styles from './RetryButton.module.css'

export interface RetryButtonProps {
  handleRetryMessage: () => void
  disabled?: boolean
  showModelPicker?: boolean
  modelName?: string
}

export function RetryButton({
  handleRetryMessage,
  disabled = false,
  showModelPicker = false,
  modelName = '',
}: RetryButtonProps) {
  const handleClick = () => {
    handleRetryMessage()
  }

  return showModelPicker ? (
    <Button
      className={clsx(styles.baseButtonStyle)}
      variant="invisible"
      aria-label="Retry"
      data-testid="retry-button"
      onClick={handleClick}
      disabled={disabled}
      leadingVisual={SyncIcon}
      trailingAction={TriangleDownIcon}
    >
      {modelName}
    </Button>
  ) : (
    <IconButton
      variant="invisible"
      aria-label="Retry"
      data-testid="retry-button"
      onClick={handleClick}
      icon={SyncIcon}
      disabled={disabled}
    />
  )
}
