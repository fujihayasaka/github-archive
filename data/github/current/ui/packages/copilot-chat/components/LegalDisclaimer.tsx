import {Link} from '@primer/react'

import styles from './LegalDisclaimer.module.css'

export const LegalDisclaimer = () => {
  return (
    <span className={styles.container}>
      <Link
        href="https://docs.github.com/en/copilot/responsible-use-of-github-copilot-features/responsible-use-of-github-copilot-chat-in-githubcom"
        inline
        muted
      >
        Copilot
      </Link>{' '}
      uses AI. Check for mistakes.
    </span>
  )
}
