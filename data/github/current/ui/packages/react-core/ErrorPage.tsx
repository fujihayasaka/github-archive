import {Heading} from '@primer/react'

import type {PageError} from './app-routing-types'
import styles from './ErrorPage.module.css'

const errorMessages: {[httpStatus: number]: string} = {
  404: 'Didn’t find anything here!',
  500: 'Looks like something went wrong!',
}

export function ErrorPage({httpStatus, type}: PageError) {
  const message = type === 'fetchError' ? 'Looks like network is down!' : errorMessages[httpStatus || 500]
  return (
    <Heading as="h1" tabIndex={-1} className={styles.Heading}>
      Error
      {httpStatus ? <div className={styles.Status}>{httpStatus}</div> : null}
      <div className={styles.Message}>{message}</div>
    </Heading>
  )
}
