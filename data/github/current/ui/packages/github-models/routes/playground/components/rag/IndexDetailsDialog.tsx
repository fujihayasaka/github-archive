import {useState} from 'react'
import {Banner} from '@primer/react/experimental'
import FileList from './FileList'
import {Dialog} from '@primer/react'
import type {FileUpload} from './FileList'
import {testIdProps} from '@github-ui/test-id-props'

import styles from './IndexDetailsDialog.module.css'

type IndexDetailsDialogProps = {
  onClose: () => void
  onDelete: () => void
  files: Array<FileUpload['file']>
  showWarning?: boolean
}

export default function IndexDetailsDialog({onClose, onDelete, files, showWarning = false}: IndexDetailsDialogProps) {
  const [isWarningVisible, setIsWarningVisible] = useState(showWarning)

  const totalFileBytes = files.reduce((acc, file) => acc + file.size, 0)

  return (
    <Dialog
      onClose={onClose}
      aria-labelledby="header"
      title="Index details"
      width="large"
      footerButtons={[
        {
          buttonType: 'default',
          content: 'Cancel',
          onClick: onClose,
        },
        {
          buttonType: 'danger',
          content: 'Delete index',
          onClick: isWarningVisible ? onDelete : () => setIsWarningVisible(true),
          disabled: false,
          loading: false,
        },
      ]}
    >
      <div className={styles.container}>
        <span>
          Models in the playground will use these files as grounding context. To create a new index, you must delete
          this current index first.
        </span>

        {/* TODO: Determine actual file count/size limits */}
        <span className={styles.header}>
          Index files
          <span {...testIdProps('file-bytes-used')} className={styles.headerSubtext}>
            {' '}
            (created 10-03-2024, {(totalFileBytes / 1000000).toFixed(1)}/50 MB limit used)
          </span>
        </span>

        {/* TODO: Add scrolling to the file list */}
        {files.length > 0 && (
          <FileList
            files={files.map(file => ({
              file,
            }))}
          />
        )}
        {isWarningVisible && (
          <Banner
            variant="warning"
            title="Warning"
            hideTitle
            description="Deleting this index will remove all listed file context for models across your GitHub account (i.e. VS Code, Codespaces, Playground)."
          />
        )}
      </div>
    </Dialog>
  )
}
