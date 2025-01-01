import {testIdProps} from '@github-ui/test-id-props'
import {Button, IconButton} from '@primer/react'
import {HistoryIcon} from '@primer/octicons-react'
import styles from './RestoreHistoryButton.module.css'

interface RestoreHistoryButtonProps {
  onClick: () => void
}

export const RestoreHistoryButton = ({onClick}: RestoreHistoryButtonProps) => {
  return (
    <div className={styles.container}>
      <IconButton
        {...testIdProps('restore-history-button')}
        icon={HistoryIcon}
        size="small"
        onClick={onClick}
        className={styles.iconButton}
        aria-label="Restore last session"
      />
      <Button size="small" onClick={onClick} className={styles.button}>
        Restore last session
      </Button>
    </div>
  )
}
