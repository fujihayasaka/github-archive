import {FileIcon} from '@primer/octicons-react'
import {FormControl} from '@primer/react'
import {Blankslate} from '@primer/react/experimental'

import styles from './FileInput.module.css'

export type FileInputProps = {
  onFilesSelected: (files: FileList) => void
  condensed?: boolean
}

export const allowedFileTypes = ['.pdf', '.txt', '.md', '.docx', '.pptx', '.xlsx']

export default function FileInput({onFilesSelected, condensed = false}: FileInputProps) {
  const handleFileChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    e.preventDefault()
    if (e.target.files) {
      onFilesSelected(e.target.files)
    }
  }

  return (
    <div
      className={styles.container}
      onDrop={e => {
        e.preventDefault()
        onFilesSelected(e.dataTransfer.files)
      }}
      onDragOver={e => {
        e.preventDefault()
      }}
      onDragEnter={e => {
        e.preventDefault()
      }}
    >
      <Blankslate>
        {!condensed && (
          <Blankslate.Visual>
            <FileIcon size={32} />
          </Blankslate.Visual>
        )}

        <div>
          Drag and drop files here
          {condensed ? ' ' : <br />}
          or{' '}
          <FormControl className={styles.chooseFiles}>
            <input
              type="file"
              hidden
              id="browse"
              onChange={handleFileChange}
              accept={allowedFileTypes.join(',')}
              multiple
            />
            <FormControl.Label htmlFor="browse" className={styles.chooseFilesLabel}>
              choose files
            </FormControl.Label>
          </FormControl>
        </div>

        <Blankslate.Description>
          <span className={styles.description}>
            {/* TODO: Determine actual list of supported file types */}
            50MB limit. (Supported formats: {allowedFileTypes.join(', ')}).
          </span>
        </Blankslate.Description>
      </Blankslate>
    </div>
  )
}
