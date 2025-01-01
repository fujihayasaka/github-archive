import {Button, IconButton, Spinner} from '@primer/react'
import {BookIcon, CheckIcon, TrashIcon} from '@primer/octicons-react'
import type {Index} from '../../../../types'

import styles from './IndexItem.module.css'

type IndexItemProps = {
  index: Index
  onClick: () => void
  onDelete: () => void
}

export default function IndexItem({index, onDelete, onClick}: IndexItemProps) {
  return (
    <div className={styles.container}>
      <div className={styles.containerLeft}>
        <Button
          className={styles.detailButton}
          onClick={onClick}
          variant="invisible"
          leadingVisual={() => (
            <div className={styles.leadingIcon}>
              <BookIcon />
            </div>
          )}
          alignContent="start"
          labelWrap
          size="small"
        >
          <span className={styles.detailButtonText}>{index.name}</span>
          <span className={styles.detailButtonSubtext}>
            {/* TODO: Use real date */}
            {`${index.files.length} ${index.files.length === 1 ? 'file' : 'files'} added on ${new Date()
              .toLocaleDateString('en-US')
              .replace(/\//g, '-')}`}{' '}
            {/* TODO: Use icon to indicate index status (in progresss, complete, erro) */}
            {index.status === 'InProgress' || index.status === null ? (
              <Spinner size="small" />
            ) : (
              <CheckIcon size={14} className={styles.statusIcon} />
            )}
          </span>
        </Button>
      </div>

      <div className={styles.containerRight}>
        <IconButton icon={TrashIcon} size="medium" variant="invisible" onClick={onDelete} aria-label="Delete index" />
      </div>
    </div>
  )
}
