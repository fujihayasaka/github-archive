import {FileMediaIcon, ImageIcon, UploadIcon} from '@primer/octicons-react'
import {ActionList} from '@primer/react'
import {useEffect, useMemo, useRef, useState} from 'react'

import {useFilesContext} from '../../../contexts/FilesContext'
import {useFileSyncerContext} from '../../../contexts/FileSyncerContext'
import {Region, RegionState, useRegionState} from '../../../hooks/use-region-state'
import {PanelBlankslate} from '../PanelBlankslate'
import {Section} from '../Section'
import styles from './AssetsPanel.module.css'

const assetsLocation = 'src/assets/'
const imageExtensions = ['.png', '.jpg', '.jpeg', '.gif', '.svg', '.webp']

function getReadableFileSize(content: string): string {
  if (!content) return '0 bytes'
  let bytesCount = 0

  // If the content is a Data URL with base64 data, decode it.
  if (content.startsWith('data:')) {
    const parts = content.split(',')
    if (parts.length === 2) {
      const base64Data = parts[1]
      const decoded = atob(base64Data || '')
      bytesCount = decoded.length
    }
  } else {
    // Fallback: use the string length as the byte count.
    bytesCount = content.length
  }

  if (bytesCount < 1024) {
    return `${bytesCount} bytes`
  } else if (bytesCount < 1024 * 1024) {
    return `${(bytesCount / 1024).toFixed(2)} KB`
  } else if (bytesCount < 1024 * 1024 * 1024) {
    return `${(bytesCount / (1024 * 1024)).toFixed(2)} MB`
  } else {
    return `${(bytesCount / (1024 * 1024 * 1024)).toFixed(2)} GB`
  }
}

export function AssetsPanel() {
  const {getFileList, editFile, writeFileBytes} = useFilesContext()
  const fileInputRef = useRef<HTMLInputElement>(null)
  const {forceFileTreeRefresh, getFileSyncerV2} = useFileSyncerContext()

  const [isFetching, setIsFetching] = useState<boolean>(true)

  const files = useMemo(() => {
    return getFileList().map(file => file.path)
  }, [getFileList])

  const [assets, setAssets] = useState<Array<{name: string; size: string}>>([])

  const isUploadDisabled = useRegionState(Region.ASSETS) === RegionState.READ_ONLY

  useEffect(() => {
    run()

    async function run() {
      setIsFetching(true)
      const newAssets = []
      for (const file of files) {
        if (file.startsWith(assetsLocation)) {
          const fileSyncer = getFileSyncerV2()
          if (fileSyncer) {
            const content = await fileSyncer.readFileString(file)
            newAssets.push({name: file.slice(assetsLocation.length), size: getReadableFileSize(content || '')})
          }
        }
      }
      setIsFetching(false)
      setAssets(newAssets)
    }
  }, [files, getFileSyncerV2])

  const uploadFile = (e: React.ChangeEvent<HTMLInputElement>) => {
    if (e.target.files && e.target.files[0]) {
      const file = e.target.files[0]
      const filePath = `${assetsLocation}${file.name}`
      const reader = new FileReader()

      reader.onload = async () => {
        // For binary files, we want to use the ArrayBuffer result
        if (reader.result instanceof ArrayBuffer) {
          // Create a Uint8Array from the ArrayBuffer
          const uint8Array = new Uint8Array(reader.result)

          // Save as raw binary - pass the Uint8Array directly
          await writeFileBytes({filePath, content: uint8Array})
        } else if (typeof reader.result === 'string') {
          // For text files
          await editFile({filePath, newFileContent: reader.result})
        }

        forceFileTreeRefresh()
      }

      // Read as binary data instead of DataURL
      reader.readAsArrayBuffer(file)

      // Clear the input value to allow the same file to be uploaded again if needed
      e.target.value = ''
    }
  }

  const triggerFileInput = () => {
    fileInputRef.current?.click()
  }

  if (!isFetching && assets.length === 0) {
    return (
      <div className="mt-3">
        <PanelBlankslate
          icon={ImageIcon}
          title="No assets yet"
          description="Add image files for use in your spark."
          primaryAction="Upload file"
          primaryActionOnClick={triggerFileInput}
          secondaryAction="Learn more about assets"
          actionDisabled={isUploadDisabled}
        />
        <input
          type="file"
          ref={fileInputRef}
          onChange={uploadFile}
          className="d-none"
          accept={imageExtensions.join(',')}
        />
      </div>
    )
  }

  return (
    <div className="mt-3">
      <Section title="Assets" showTitle={false} readOnly={isUploadDisabled} loading={isFetching}>
        <Section.PrimaryAction icon={UploadIcon} onSelect={triggerFileInput}>
          Upload file
        </Section.PrimaryAction>
        <input
          type="file"
          ref={fileInputRef}
          onChange={uploadFile}
          className="d-none"
          accept={imageExtensions.join(',')}
        />

        <ActionList>
          {assets.map(asset => (
            <ActionList.Item key={asset.name} className={styles.listItem}>
              <ActionList.LeadingVisual>
                <FileMediaIcon />
              </ActionList.LeadingVisual>
              {asset.name}
              <ActionList.Description variant="block">Image · {asset.size}</ActionList.Description>
            </ActionList.Item>
          ))}
        </ActionList>
      </Section>
    </div>
  )
}
