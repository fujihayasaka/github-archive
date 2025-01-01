import {IssueReopenedIcon, SquareFillIcon} from '@primer/octicons-react'
import styles from './ExecuteButton.module.css'
import {IconButton} from '@primer/react'
import type {IconButtonProps} from '@primer/react'
import {clsx} from 'clsx'
import type {NodeValue} from '../../types/app'

interface ExecuteButtonProps {
  type: string
  value?: NodeValue
  className?: string
  size?: 'small' | 'medium' | 'large'
  isLoading: boolean
  onClick: (e: React.MouseEvent<HTMLButtonElement>) => void
  onStop?: (e: React.MouseEvent<HTMLButtonElement>) => void
  variant?: IconButtonProps['variant']
}

export function ExecuteButton({
  type,
  value,
  className,
  isLoading,
  onClick,
  onStop,
  variant = 'invisible',
}: ExecuteButtonProps) {
  const getAriaLabel = () => {
    if (isLoading) return 'Loading...'
    if (type === 'code') return 'Evaluate'
    return value ? 'Re-generate output' : 'Generate output'
  }

  return (
    <IconButton
      aria-label={getAriaLabel()}
      className={clsx(className, styles.executeButton, isLoading ? styles.loading : '')}
      icon={isLoading ? SquareFillIcon : IssueReopenedIcon}
      onClick={e => {
        if (isLoading) {
          onStop?.(e)
        } else {
          onClick(e)
        }
      }}
      variant={variant}
    />
  )
}
