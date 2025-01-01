import {AlertFillIcon} from '@primer/octicons-react'
import {clsx} from 'clsx'
import {memo} from 'react'

import styles from './CopilotBadge.module.css'
import CopilotThinkingAnimation from './CopilotThinkingAnimation'

export interface CopilotBadgeProps {
  isLoading?: boolean
  isError?: boolean
  className?: string
}

function CopilotBadge({isLoading, isError, className}: CopilotBadgeProps) {
  return (
    <div className={clsx(styles.copilotBadge, isLoading && styles.loading, className)}>
      <CopilotThinkingAnimation isLoading={isLoading || false} />
      {isError && (
        <div className={styles.errorIcon}>
          <AlertFillIcon size={12} />
        </div>
      )}
    </div>
  )
}

export default memo(CopilotBadge)
