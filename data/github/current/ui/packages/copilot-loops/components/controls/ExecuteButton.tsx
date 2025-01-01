import {SquareFillIcon, SyncIcon} from '@primer/octicons-react'
import {IconButton, Button} from '@primer/react'
import type {IconButtonProps, ButtonProps} from '@primer/react'
import type {NodeValue} from '../../types/app'
import type React from 'react'

interface ExecuteButtonProps {
  value?: NodeValue
  className?: string
  size?: 'small' | 'medium' | 'large'
  isLoading: boolean
  onClick: (e: React.MouseEvent<HTMLButtonElement>) => void
  onStop?: (e: React.MouseEvent<HTMLButtonElement>) => void
  variant?: IconButtonProps['variant'] | ButtonProps['variant']
  disabled?: boolean
  iconOnly?: boolean
}

export function ExecuteButton({
  value,
  isLoading,
  onClick,
  onStop,
  variant = 'invisible',
  disabled,
  iconOnly,
}: ExecuteButtonProps) {
  const getAriaLabel = () => {
    if (isLoading) return 'Loading...'
    return value ? 'Run node' : 'Run loop'
  }

  const handleClick = (e: React.MouseEvent<HTMLButtonElement>) => {
    if (isLoading) {
      onStop?.(e)
    } else {
      onClick(e)
    }
  }

  if (!iconOnly) {
    return (
      <Button disabled={disabled} variant={isLoading ? 'danger' : variant} onClick={handleClick}>
        {isLoading ? 'Stop' : 'Run'}
      </Button>
    )
  }

  return (
    <IconButton
      disabled={disabled}
      aria-label={getAriaLabel()}
      icon={isLoading ? SquareFillIcon : SyncIcon}
      onClick={handleClick}
      variant={isLoading ? 'danger' : variant}
    />
  )
}
