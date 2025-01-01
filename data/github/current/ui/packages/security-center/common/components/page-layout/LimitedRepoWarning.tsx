import {Link} from '@primer/react'

import styles from './LimitedRepoWarning.module.css'

type Props = {
  show: boolean
  href: string
}

function LimitedRepoWarning({show, href}: Props): JSX.Element {
  return (
    <>
      {show && (
        <p data-testid="incomplete-data-warning" className={styles.LimitedRepoWarningMessage}>
          Results are based on a{' '}
          <Link href={href} muted inline>
            limited selection
          </Link>{' '}
          of repositories.
        </p>
      )}
    </>
  )
}

LimitedRepoWarning.displayName = 'PageLayout.LimitedRepoWarning'

export default LimitedRepoWarning
