import FileInput, {allowedFileTypes} from './FileInput'
import FileList, {type FileUpload} from './FileList'
import {createUploadSession, completeUploadSession, uploadFile} from '../../../../utils/rag-index-manager'
import {useRAGContext} from '../../contexts/RAGContext'
import {useState} from 'react'
import {Dialog} from '@primer/react'

import styles from './CreateIndexDialog.module.css'

type CreateIndexDialogProps = {
  onClose: () => void
}

export default function CreateIndexDialog({onClose}: CreateIndexDialogProps) {
  const [fileUploads, setFileUploads] = useState<FileUpload[]>([] as FileUpload[])
  const [isUploading, setIsUploading] = useState(false)
  const {setIndex, pollUntilCompleted} = useRAGContext()

  const totalFileBytes = fileUploads.reduce((acc, upload) => acc + upload.file.size, 0)

  const addFiles = (newFiles: FileList) => {
    const newFileUploads = Array.from(newFiles)
      .filter(file => allowedFileTypes.some(allowedType => file.name.endsWith(allowedType)))
      .map(file => ({file}))
    setFileUploads([...fileUploads, ...newFileUploads])
  }

  const removeFile = (index: number) => {
    setFileUploads(fileUploads.filter((_, i) => i !== index))
  }

  const updateFile = (index: number, fileUpload: FileUpload) => {
    setFileUploads((prevFileUploads: FileUpload[]) => [
      ...prevFileUploads.slice(0, index),
      {...fileUpload},
      ...prevFileUploads.slice(index + 1),
    ])
  }

  const onUploadAndCreateIndex = async () => {
    try {
      setIsUploading(true)

      const uploadSessionID = await createUploadSession()

      //  Start each file upload
      const nextFileUploads = fileUploads.map((upload, index) => {
        const promise = (async () => {
          await uploadFile(uploadSessionID, upload.file as File)

          //  Update file's upload status after uploading
          updateFile(index, {...upload, isUploadInProgress: false})
        })()

        return {
          ...upload,
          promise,
          isUploadInProgress: true,
        }
      })
      setFileUploads(nextFileUploads)

      //  Wait for all files to finish uploading
      await Promise.all(nextFileUploads.map(upload => upload.promise))

      //  Start creating the index on the server
      await completeUploadSession(uploadSessionID)

      // Set preliminary index state
      setIndex({
        // TODO: Use the real index name. The completeUploadSession was recently changed to return the name of the
        // indexer instead. Harcoding for now
        name: 'default-vector-index',
        status: 'InProgress',
        files: fileUploads.map(upload => ({name: upload.file.name, size: upload.file.size})),
      })

      setIsUploading(false)
      pollUntilCompleted()
      onClose()
    } catch (error) {
      // TODO: Handle errors properly
      // eslint-disable-next-line no-console
      console.error('Failed to upload files:', error)
      setIsUploading(false)
    }
  }

  return (
    <Dialog
      onClose={onClose}
      aria-labelledby="header"
      title="Create index"
      width="large"
      footerButtons={[
        {
          buttonType: 'default',
          content: 'Cancel',
          onClick: onClose,
        },
        {
          buttonType: 'primary',
          content: 'Upload and create index',
          onClick: onUploadAndCreateIndex,
          disabled: !fileUploads.length || isUploading,
          loading: isUploading,
        },
      ]}
    >
      <div className={styles.container}>
        <span>
          Select the files you would like to upload. Models in the playground will use these files as grounding context
          to generate an answer.
        </span>

        {/* TODO: Determine actual file count/size limits */}
        <span className={styles.header}>
          Upload files
          {fileUploads.length > 0 && (
            <span className={styles.headerSubtext}>
              {` (${fileUploads.length} file${fileUploads.length > 1 ? 's' : ''}, ${(totalFileBytes / 1000000).toFixed(
                1,
              )}/50 MB limit used)`}
            </span>
          )}
        </span>

        {/* TODO: Add upload progress indicator */}

        <FileInput onFilesSelected={addFiles} condensed={fileUploads.length > 0} />

        {/* TODO: Add scrolling to the file list */}
        {fileUploads.length > 0 && <FileList files={fileUploads} disabled={isUploading} onFileDeleted={removeFile} />}
      </div>
    </Dialog>
  )
}
