import {useCallback, useState} from 'react'
import {UploadIcon} from '@primer/octicons-react'
import {FormControl, Button, Checkbox, Spinner} from '@primer/react'
import {useRAGContext} from '../../contexts/RAGContext'
import CreateIndexDialog from './CreateIndexDialog'
import IndexDetailsDialog from './IndexDetailsDialog'
import IndexItem from './IndexItem'
import {deleteIndex} from '../../../../utils/rag-index-manager'
import {testIdProps} from '@github-ui/test-id-props'

import styles from './IndexParameter.module.css'

type IndexParameterProps = {
  value: boolean
  onChange: (isSelected: boolean) => void
}

export default function IndexParameter({value, onChange}: IndexParameterProps) {
  const {index, setIndex, isFetchingIndex} = useRAGContext()
  const [isCreateIndexDialogOpen, setIsCreateIndexDialogOpen] = useState(false)
  const [isIndexDetailsDialogOpen, setIsIndexDetailsDialogOpen] = useState(false)
  const [isDeleteWarningVisible, setIsDeleteWarningVisible] = useState(false)

  const handleIsUseIndexChange = () => {
    onChange(!value)
  }

  const handleDeleteIndex = async () => {
    setIndex(null)
    onChange(false)
    setIsIndexDetailsDialogOpen(false)
    setIsDeleteWarningVisible(false)
    try {
      deleteIndex()
    } catch (error) {
      // TODO: Handle errors properly
      // eslint-disable-next-line no-console
      console.error('Error deleting index:', error)
    }
  }

  const handleDeleteIconClick = useCallback(() => {
    setIsDeleteWarningVisible(true)
    setIsIndexDetailsDialogOpen(true)
  }, [])

  const handleIndexDetailDialogClose = useCallback(() => {
    setIsIndexDetailsDialogOpen(false)
    setIsDeleteWarningVisible(false)
  }, [])

  return (
    <FormControl className={styles.container}>
      <FormControl.Label>Grounding data</FormControl.Label>

      <FormControl disabled={!index || index.status !== 'Success'}>
        <Checkbox checked={!!index && value} onChange={handleIsUseIndexChange} />
        <FormControl.Label className={styles.label}>Use index for model context</FormControl.Label>
      </FormControl>

      {index ? (
        <IndexItem index={index} onClick={() => setIsIndexDetailsDialogOpen(true)} onDelete={handleDeleteIconClick} />
      ) : (
        <Button
          leadingVisual={isFetchingIndex ? <Spinner size="small" /> : UploadIcon}
          value="Upload files to create index"
          onClick={() => setIsCreateIndexDialogOpen(true)}
          block
          disabled={isFetchingIndex}
          {...testIdProps('upload-files-to-create-index')}
        >
          Upload files to create index
        </Button>
      )}

      <span className={styles.label}>
        The model will use these files to generate responses that are grounded in the Azure Al Search index.
      </span>

      {isCreateIndexDialogOpen && <CreateIndexDialog onClose={() => setIsCreateIndexDialogOpen(false)} />}

      {isIndexDetailsDialogOpen && (
        <IndexDetailsDialog
          onClose={handleIndexDetailDialogClose}
          onDelete={handleDeleteIndex}
          files={index?.files ?? []}
          showWarning={isDeleteWarningVisible}
        />
      )}
    </FormControl>
  )
}
