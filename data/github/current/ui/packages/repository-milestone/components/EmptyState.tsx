import {Link} from '@primer/react'
import styles from './EmptyState.module.css'
import {LABELS} from '../constants/labels'

export const EmptyState = ({
  selected,
  ariaLabel,
  id,
  descriptionUrl,
}: {
  selected: 'open' | 'closed'
  ariaLabel?: string
  id?: string
  descriptionUrl: string
}) => {
  // If the selected returns other than open or closed we set it to open
  if (selected !== 'open' && selected !== 'closed') {
    selected = 'open'
  }

  return (
    <div
      id={id}
      className={styles.emptyState}
      role="region"
      aria-label={ariaLabel}
      aria-live="polite"
      aria-atomic="true"
    >
      <h3 className={styles.emptyStateHeading}>
        {selected === 'open' ? LABELS.emptyStateOpenIssues : LABELS.emptyStateClosedIssues}
      </h3>
      <p>
        {selected === 'open' ? (
          <>
            Add issues to milestones to help organize your work for a particular release or project. Find and add{' '}
            <Link inline href={descriptionUrl}>
              issues with no milestones
            </Link>{' '}
            in this repo.
          </>
        ) : (
          'Issues will automatically be moved here when they are closed.'
        )}
      </p>
    </div>
  )
}
