import {useAppPayload} from '@github-ui/react-core/use-app-payload'
import {MarkGithubIcon} from '@primer/octicons-react'
import {Button, Link} from '@primer/react'

import type {CopilotImmersiveLoggedOutPayload} from '../copilot-immersive-logged-out-types'
import styles from './CopilotHeader.module.css'

export const CopilotHeader: React.FC = () => {
  const {signInPath, signUpPath} = useAppPayload<CopilotImmersiveLoggedOutPayload>()

  return (
    <header className={styles.AppHeader}>
      <Link aria-label="Homepage" href="/">
        <MarkGithubIcon className={styles.AppHeaderLogo} />
      </Link>
      <span className={styles.AppHeaderTitle}>Copilot</span>

      <div className={styles.buttonContainer}>
        <Button as="a" href={signInPath} variant="default">
          Sign In
        </Button>
        <Button as="a" href={signUpPath} variant="primary">
          Sign Up
        </Button>
      </div>
    </header>
  )
}
