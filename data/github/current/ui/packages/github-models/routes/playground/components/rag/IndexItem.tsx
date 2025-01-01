import {Button, IconButton, Spinner} from '@primer/react'
import {BookIcon, CheckIcon, TrashIcon, XIcon} from '@primer/octicons-react'
import type {Index} from '../../../../types'
import {testIdProps} from '@github-ui/test-id-props'
import {useClickAnalytics} from '@github-ui/use-analytics'

import styles from './IndexItem.module.css'

type IndexItemProps = {
  index: Index
  onClick: () => void
  onDelete: () => void
}

export default function IndexItem({index, onDelete, onClick}: IndexItemProps) {
  const {sendClickAnalyticsEvent} = useClickAnalytics()

  const handleDelete = () => {
    sendClickAnalyticsEvent({
      category: 'github_models_playground',
      action: 'rag_delete_index',
    })
    onDelete()
  }

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
          {...testIdProps('rag-index-button')}
        >
          <span className={styles.detailButtonText}>{index.name}</span>
          <span className={styles.detailButtonSubtext}>
            {/* TODO: Use real date */}
            {`${index.files.length} ${index.files.length === 1 ? 'file' : 'files'} added on ${new Date()
              .toLocaleDateString('en-US')
              .replace(/\//g, '-')}`}{' '}
            {index.status === 'InProgress' ? (
              <Spinner size="small" />
            ) : index.status === 'Success' ? (
              <CheckIcon size={14} className={styles.statusIconSuccess} aria-label="Success" />
            ) : (
              <XIcon size={14} className={styles.statusIconDanger} aria-label="Failure" />
            )}
          </span>
        </Button>
      </div>

      <div className={styles.containerRight}>
        <IconButton
          icon={TrashIcon}
          size="medium"
          variant="invisible"
          onClick={handleDelete}
          aria-label="Delete index"
          {...testIdProps('delete-index')}
        />
      </div>
    </div>
  )
}
