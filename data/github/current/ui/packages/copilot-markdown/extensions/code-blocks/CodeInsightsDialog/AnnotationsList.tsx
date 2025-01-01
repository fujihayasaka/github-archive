import {ChevronRightIcon} from '@primer/octicons-react'
import {ActionList} from '@primer/react'

import styles from './AnnotationsList.module.css'

interface AnnotationsListProps {
  summary: React.ReactNode
  icon: React.ReactNode
  children: React.ReactNode
}

export function AnnotationsList({summary, icon, children}: AnnotationsListProps) {
  return (
    <details>
      <summary className={styles.summary}>
        <span className={styles.chevron}>
          <ChevronRightIcon size="small" />
        </span>
        {icon} <span className={styles.summaryText}>{summary}</span>
      </summary>

      <div className={styles.items}>
        <ActionList variant="full">{children}</ActionList>
      </div>
    </details>
  )
}
