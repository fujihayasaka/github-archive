import {IconButton, Spinner} from '@primer/react'
import {FileIcon, TrashIcon} from '@primer/octicons-react'

import styles from './FileList.module.css'

export type FileUpload = {
  file: {name: string; size: number}
  promise?: Promise<void>
  isUploadInProgress?: boolean
}

export type FileListProps = {
  files: FileUpload[]
  disabled?: boolean
  onFileDeleted?: (index: number) => void
}

export default function FileList({files, disabled = false, onFileDeleted}: FileListProps) {
  return (
    <ul aria-label="File list" className={styles.fileList}>
      {files.map(({file, isUploadInProgress}, index) => (
        // File's don't have a unique identifier, so we'll use the name and index as a key
        // eslint-disable-next-line @eslint-react/no-array-index-key
        <li key={file.name + index} className={styles.fileListItem}>
          {/* TODO: Add checkmark when upload is complete? */}
          {isUploadInProgress ? <Spinner size="small" /> : <FileIcon aria-label="Uploaded file" />}
          <span className={styles.fileListItemName}>{file.name}</span>
          <span className={styles.fileListItemSize}>{`${(file.size / 1000000).toFixed(2)} MB`}</span>

          {/* Only show the delete button if a callback is provided */}
          {!!onFileDeleted && (
            <IconButton
              className={styles.deleteButton}
              size="small"
              icon={TrashIcon}
              aria-label="Remove file"
              variant="link"
              tooltipDirection="w"
              onClick={() => onFileDeleted(index)}
              disabled={isUploadInProgress || disabled}
            >
              Remove file
            </IconButton>
          )}
        </li>
      ))}
    </ul>
  )
}
