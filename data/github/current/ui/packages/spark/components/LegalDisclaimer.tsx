import {Link} from '@primer/react'

import styles from './LegalDisclaimer.module.css'

export const LegalDisclaimer: React.FC = () => {
  return (
    <p className={styles.container}>
      <Link href="https://gh.io/responsible-use-of-github-spark" inline muted>
        Spark
      </Link>{' '}
      uses AI. Check for mistakes.
    </p>
  )
}
