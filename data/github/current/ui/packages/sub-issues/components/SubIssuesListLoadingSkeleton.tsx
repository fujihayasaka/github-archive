import {LoadingSkeleton} from '@github-ui/skeleton/LoadingSkeleton'

import styles from './SubIssuesListLoadingSkeleton.module.css'

export function SubIssuesListLoadingSkeleton() {
  return (
    <div data-testid="sub-issues-loading-skeleton">
      <div className={styles.Box}>
        <h3 className={styles.Heading}>Sub-issues</h3>
      </div>
      <div className={styles.LoadingBox}>
        <LoadingSkeleton />
      </div>
    </div>
  )
}
