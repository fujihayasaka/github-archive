import {
  GitMergeIcon,
  GitPullRequestClosedIcon,
  GitPullRequestDraftIcon,
  GitPullRequestIcon,
} from '@primer/octicons-react'
import {Link, RelativeTime} from '@primer/react'

import type {PullRequestData} from '../types'
import styles from '../CodeScanningDevelopmentSection.module.css'

type PullRequestItemProps = {
  pr: PullRequestData
}

function PullRequestIcon({pr}: PullRequestItemProps) {
  const {state, isDraft} = pr
  switch (state) {
    case 'OPEN':
      return isDraft ? (
        <GitPullRequestDraftIcon size="small" />
      ) : (
        <GitPullRequestIcon size="small" className={'fgColor-open'} />
      )
    case 'CLOSED':
      return <GitPullRequestClosedIcon size="small" className={'fgColor-closed'} />
    case 'MERGED':
      return <GitMergeIcon size="small" className={'fgColor-done'} />
  }
}

function PullRequestDescription({
  pr: {state, number, createdAt, baseRefName, baseRefUrl, closedAt, mergedAt},
}: PullRequestItemProps) {
  const getDescription = () => {
    switch (state) {
      case 'OPEN':
        return (
          <div className={styles.DevelopmentSectionItem__text}>
            #{number} opened <RelativeTime datetime={createdAt} tense="past" /> merges into{' '}
            <Link inline href={baseRefUrl} target="_blank">
              {baseRefName}
            </Link>
          </div>
        )
      case 'CLOSED':
        return (
          <div className={styles.DevelopmentSectionItem__text}>
            #{number} was closed {closedAt && <RelativeTime datetime={closedAt} tense="past" />}
          </div>
        )
      case 'MERGED':
        return (
          <div className={styles.DevelopmentSectionItem__text}>
            #{number} was merged into{' '}
            <Link inline href={baseRefUrl} target="_blank">
              {baseRefName}
            </Link>{' '}
            {mergedAt && <RelativeTime datetime={mergedAt} tense="past" />}
          </div>
        )
    }
  }

  return (
    <div
      data-testid="development-section-pull-request-description"
      className={styles.DevelopmentSectionItem__description}
    >
      {getDescription()}
    </div>
  )
}

export function PullRequestItem({pr}: PullRequestItemProps) {
  const {title, url} = pr
  return (
    <div className={styles.DevelopmentSectionItem} data-testid="development-section-pull-request-item">
      <div className={styles.DevelopmentSectionItem__icon}>
        <PullRequestIcon pr={pr} />
      </div>
      <Link href={url} className={styles.DevelopmentSectionItem__link} target="_blank">
        <div className={styles.DevelopmentSectionItem__title}>{title}</div>
      </Link>
      <PullRequestDescription pr={pr} />
    </div>
  )
}
