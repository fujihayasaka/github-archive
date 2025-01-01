import {StopIcon} from '@primer/octicons-react'

import styles from './ErrorMessage.module.css'
import {Fragment} from 'react/jsx-runtime'

export function ErrorMessage({error}: {error?: string}) {
  const msgLines = error?.split('\n') ?? []
  return (
    <div className={styles.error}>
      <span className={styles.errorIcon}>
        <StopIcon size={24} />
      </span>
      <h2 className={styles.errorHeader}>HTML rendering failed</h2>
      {msgLines.length > 0 ? (
        <p>
          {msgLines.map(line => (
            <Fragment key={`error-line-${line}}`}>
              {line}
              <br />
            </Fragment>
          ))}
        </p>
      ) : (
        <p>Refresh the page or check the HTML</p>
      )}
    </div>
  )
}
