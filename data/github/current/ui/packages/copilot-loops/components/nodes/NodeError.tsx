import {AlertIcon, BeakerIcon} from '@primer/octicons-react'
import {Button} from '@primer/react'
import styles from './NodeError.module.css'

interface NodeErrorProps {
  title?: string
  errors: string[]
  onFixErrorClick: () => void
}

export function NodeError({errors, onFixErrorClick, title}: NodeErrorProps) {
  return (
    <div className={styles.errorContainer}>
      <div className={styles.errorNotice}>
        <AlertIcon className={styles.errorIcon} />
        {title}
      </div>
      {errors.map(error => (
        <p key={error} className={styles.errorText}>
          {error}
        </p>
      ))}
      <Button className={styles.fixErrorButton} leadingVisual={BeakerIcon} onClick={onFixErrorClick}>
        Try to fix it
      </Button>
    </div>
  )
}
