import {testIdProps} from '@github-ui/test-id-props'
import {XIcon} from '@primer/octicons-react'
import {IconButton} from '@primer/react'
import {clsx} from 'clsx'

import styles from './RemoveFilterButton.module.css'

type RemoveFilterButtonProps = {
  onClick: () => void
  ariaLabel: string
  testId?: string
  className?: string
}

export const RemoveFilterButton = ({ariaLabel, onClick, className, testId = ''}: RemoveFilterButtonProps) => {
  return (
    <IconButton
      icon={XIcon}
      size="small"
      variant="invisible"
      aria-label={ariaLabel}
      onClick={onClick}
      className={clsx(className, styles.IconButton_0)}
      {...testIdProps(testId)}
    />
  )
}
