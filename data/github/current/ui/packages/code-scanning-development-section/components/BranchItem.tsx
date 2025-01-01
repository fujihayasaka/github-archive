import styles from '../CodeScanningDevelopmentSection.module.css'
import {Link, RelativeTime} from '@primer/react'
import {GitBranchIcon} from '@primer/octicons-react'
import {clsx} from 'clsx'
import type {BranchData} from '../types'

type BranchItemProps = {
  branch: BranchData
}

export function BranchItem({branch: {name, url, lastModifiedAt}}: BranchItemProps) {
  return (
    <div className={styles.DevelopmentSectionItem} data-testid="development-section-branch-item">
      <GitBranchIcon size="small" className={styles.DevelopmentSectionItem__icon} />
      <Link href={url} className={styles.DevelopmentSectionItem__link} target="_blank">
        <div className={clsx(styles.DevelopmentSectionItem__title)}>{name}</div>
      </Link>
      <div className={styles.DevelopmentSectionItem__description} data-testid="development-section-branch-description">
        <div className={styles.DevelopmentSectionItem__text}>
          Updated <RelativeTime datetime={lastModifiedAt} tense="past" />
        </div>
      </div>
    </div>
  )
}
