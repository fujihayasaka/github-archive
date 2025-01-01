import {AlertIcon} from '@primer/octicons-react'
import {Link} from '@primer/react'
import {Blankslate} from '@primer/react/experimental'

import styles from './ErrorFallback.module.css'

interface ErrorFallbackProps {
  /**
   * Sentence-case name of this region. This should work as the subject of a sentence - ie, "The canvas"
   * or "The side panel" or "This component". This will fill in the blank for "______ is temporarily unavailable..."
   */
  regionName: string
}

/**
 * Fallback to be used in case of errors thrown during the render cycle (in tandem with `ComponentErrorBoundary`). This is not
 * the same as `ErrorState`, which is designed for known, handleable errors such as API outages.
 */
export function ErrorFallback({regionName}: ErrorFallbackProps) {
  return (
    <div className={styles.errorFallbackContainer}>
      <Blankslate>
        <Blankslate.Visual>
          <AlertIcon size="medium" />
        </Blankslate.Visual>
        <Blankslate.Heading>Something went wrong</Blankslate.Heading>
        <Blankslate.Description>
          {regionName} is temporarily unavailable due to an unknown error. Try reloading the page or, if the error
          persists,{' '}
          <Link href="https://support.github.com/" inline>
            contact support
          </Link>
          .
        </Blankslate.Description>
      </Blankslate>
    </div>
  )
}
