import {ChevronDownIcon} from '@primer/octicons-react'
import {ActionList} from '@primer/react'

import styles from './AnnotationsList.module.css'

interface AnnotationsListProps {
  summary: React.ReactNode
  icon: React.ReactNode
  children: React.ReactNode
}

export function AnnotationsList({summary, icon, children}: AnnotationsListProps) {
  return (
    <details className={styles.container}>
      <summary className={styles.summary}>
        {icon} <span className={styles.summaryText}>{summary}</span>
        <span className={styles.chevron}>
          <ChevronDownIcon size="small" />
        </span>
      </summary>

      <ActionList variant="full" className={styles.items}>
        {children}
      </ActionList>
    </details>
  )
}
