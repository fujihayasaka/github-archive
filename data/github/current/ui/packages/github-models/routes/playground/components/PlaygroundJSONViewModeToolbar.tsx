import {Button, IconButton} from '@primer/react'
import {PencilIcon} from '@primer/octicons-react'
import styles from './PlaygroundJSONViewModeToolbar.module.css'

interface PlaygroundJSONViewModeToolbarProps {
  doEdit: () => void
}

export function PlaygroundJSONViewModeToolbar({doEdit}: PlaygroundJSONViewModeToolbarProps) {
  return (
    <>
      <IconButton
        className={styles.iconButton}
        size="small"
        icon={PencilIcon}
        aria-label="Edit JSON"
        onClick={doEdit}
      />
      <Button className={styles.editButton} onClick={doEdit} size="small">
        Edit
      </Button>
    </>
  )
}
