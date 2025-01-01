import {SingleSignOnBanner} from '@github-ui/single-sign-on-banner'
import {AlertIcon} from '@primer/octicons-react'
import {Blankslate} from '@primer/react/experimental'
import type {ReactNode} from 'react'

import styles from './ErrorState.module.css'

export interface ErrorStateProps {
  title: string
  description?: ReactNode
  ssoOrgs?: string[]
}

export function ErrorState({title, description, ssoOrgs}: ErrorStateProps) {
  const showSSO = ssoOrgs && ssoOrgs.length > 0
  return (
    <div className={styles.container}>
      <h1 className="sr-only">Copilot Chat</h1>
      <Blankslate border={false}>
        <Blankslate.Visual>
          <AlertIcon size="medium" className={styles.icon} />
        </Blankslate.Visual>
        <Blankslate.Heading as="h2">{title}</Blankslate.Heading>
        {(description !== undefined || showSSO) && (
          <Blankslate.Description>
            <div className={styles.description}>
              <span>{description}</span>
              {showSSO && <SingleSignOnBanner sx={{textAlign: 'left'}} protectedOrgs={ssoOrgs} />}
            </div>
          </Blankslate.Description>
        )}
      </Blankslate>
    </div>
  )
}
