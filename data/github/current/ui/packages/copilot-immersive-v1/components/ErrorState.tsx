import {AlertIcon} from '@primer/octicons-react'
import {Blankslate} from '@primer/react/experimental'
import type {ReactNode} from 'react'

import styles from './ErrorState.module.css'

export interface ErrorStateProps {
  title: string
  description?: ReactNode
}

export function ErrorState({title, description}: ErrorStateProps) {
  return (
    <div className={styles.container}>
      <h1 className="sr-only">Copilot Chat</h1>
      <Blankslate border={false}>
        <Blankslate.Visual>
          <AlertIcon size="medium" className={styles.icon} />
        </Blankslate.Visual>
        <Blankslate.Heading as="h2">{title}</Blankslate.Heading>
        {description !== undefined && <Blankslate.Description>{description}</Blankslate.Description>}
      </Blankslate>
    </div>
  )
}
