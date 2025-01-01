import {useAppPayload} from '@github-ui/react-core/use-app-payload'
import {SingleSignOnBanner} from '@github-ui/single-sign-on-banner'
import {AlertIcon, LockIcon} from '@primer/octicons-react'
import {Link} from '@primer/react'
import {Blankslate} from '@primer/react/experimental'
import type {ReactNode} from 'react'

import type {CopilotImmersivePayload} from '../routes/payloads'
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
          <div className={styles.description}>
            <Blankslate.Description>
              <span>{description}</span>
            </Blankslate.Description>
            <div className={styles.sso}>{showSSO && <SingleSignOnBanner protectedOrgs={ssoOrgs} />}</div>
          </div>
        )}
      </Blankslate>
    </div>
  )
}

export function SharedThreadForbidden() {
  const {helpUrl} = useAppPayload<CopilotImmersivePayload>()

  return (
    <div className={styles.container}>
      <h1 className="sr-only">Copilot Chat</h1>
      <Blankslate border={false}>
        <Blankslate.Visual>
          <LockIcon size="medium" className={styles.icon} />
        </Blankslate.Visual>
        <Blankslate.Heading as="h2">You don&apos;t have access to this shared conversation</Blankslate.Heading>
        <div className={styles.description}>
          <Blankslate.Description>
            <span>
              To view this shared link, you must have permissions to all resources referenced in the conversation.
            </span>
          </Blankslate.Description>
          <Link
            inline
            href={`${helpUrl}/copilot/using-github-copilot/copilot-chat/asking-github-copilot-questions-in-github#sharing-copilot-chat-conversations`}
          >
            Learn more
          </Link>
        </div>
      </Blankslate>
    </div>
  )
}
