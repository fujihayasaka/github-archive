import CodeMirror from '@github-ui/code-mirror'
import {useChatState} from '@github-ui/copilot-chat/CopilotChatContext'
import {NullMessageId} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {CopyToClipboardButton} from '@github-ui/copy-to-clipboard/Button'
import {sendEvent} from '@github-ui/hydro-analytics'
import {useTrackingRef} from '@github-ui/use-tracking-ref'
import {DownloadIcon} from '@primer/octicons-react'
import {IconButton, SegmentedControl} from '@primer/react'
import debounce from 'lodash-es/debounce'
import {useCallback, useEffect, useId, useMemo, useRef, useState} from 'react'

import {useGuessCodeMirrorSettings} from '../../hooks/use-code-mirror-config'
import {useHydrateReference} from '../../utils/use-hydrate-reference'
import {type File, type PreviewableContent, stripVersionFromId, type VersionedItemsMap} from './content-preview-types'
import {useContentPreview} from './ContentPreviewContext'
import {downloadFile} from './download-file'
import styles from './FilePreview.module.css'
import {HtmlPreview} from './HtmlPreview'
import {MarkdownPreview} from './MarkdownPreview'
import {VersionSelector} from './VersionSelector'

interface FilePreviewProps {
  isPreviewOpening: boolean
  file: File
  onClose: () => void
}

function prettySize(bytes: number) {
  if (bytes === 0) return '0 bytes'
  if (bytes === 1) return '1 byte'

  const sizes = ['bytes', 'KB', 'MB', 'GB', 'TB']
  const i = Math.floor(Math.log(bytes) / Math.log(1024))
  return `${Math.round(bytes / Math.pow(1024, i))} ${sizes[i]}`
}

function useFileInfo(file: File) {
  return useMemo(() => {
    const bytes = new Blob([file.value]).size
    const previewableLanguages = new Set<string>(['markdown', 'html'])

    return {
      linesOfCode: file.value.split('\n').length,
      isPreviewable: previewableLanguages.has(file.language),
      size: prettySize(bytes),
    }
  }, [file.language, file.value])
}

export function FilePreview({isPreviewOpening, file, onClose}: FilePreviewProps) {
  const {updateItem} = useContentPreview()
  const state = useChatState()
  const fileMessage = file.isStreaming
    ? state.messages[state.messages.length - 1]
    : state.messages.find(message => message.id === file.messageId)
  const {linesOfCode, isPreviewable, size} = useFileInfo(file)
  useHydrateReference(file, updateItem)

  const [viewMode, setViewMode] = useState<'code' | 'preview'>('code')
  const [selectedVersion, setSelectedVersion] = useState<string | undefined>(undefined)

  const handleVersionChange = useCallback((versionLabel: string) => {
    setSelectedVersion(versionLabel)
  }, [])

  useEffect(() => {
    if (fileMessage?.error?.type === 'publicCode' || fileMessage?.error?.type === 'filtered') {
      onClose()
    }
  }, [fileMessage?.error, onClose])

  return (
    <div className={styles.container}>
      <div className={styles.toolbar}>
        <div className={styles.toolbarLeft}>
          {isPreviewable && (
            <SegmentedControl
              aria-label="File view"
              onChange={i => {
                const newViewMode = i === 0 ? 'preview' : 'code'
                setViewMode(newViewMode)
                sendEvent('dotcom_chat.activate', {target: 'BROWSER_FILE_VIEW_OPTION', option: newViewMode})
              }}
            >
              <SegmentedControl.Button selected={viewMode === 'preview'}>Preview</SegmentedControl.Button>
              <SegmentedControl.Button selected={viewMode === 'code'}>Code</SegmentedControl.Button>
            </SegmentedControl>
          )}
          <VersionSelector item={file} onVersionSelect={handleVersionChange} />
          <p className={styles.toolbarLoC}>
            {linesOfCode} {linesOfCode === 1 ? 'line' : 'lines'} · {size}
          </p>
        </div>
        <div className={styles.toolbarActions}>
          <CopyToClipboardButton
            textToCopy={file.value}
            ariaLabel={'Copy code'}
            onCopy={() => sendEvent('dotcom_chat.activate', {target: 'BROWSER_FILE_COPY', mode: 'immersive'})}
          />
          <IconButton
            aria-label="Download code"
            icon={DownloadIcon}
            variant="invisible"
            onClick={() => {
              const fileName = (() => {
                const extensionIndex = file.name.lastIndexOf('.')
                if (extensionIndex > 0) {
                  const baseName = file.name.substring(0, extensionIndex)
                  const extension = file.name.substring(extensionIndex)
                  return selectedVersion !== undefined ? `${baseName}_${selectedVersion}${extension}` : file.name
                }
                return selectedVersion !== undefined ? `${file.name}_${selectedVersion}` : file.name
              })()
              downloadFile(new File([file.value], fileName))
              sendEvent('dotcom_chat.activate', {target: 'BROWSER_FILE_DOWNLOAD', mode: 'immersive'})
            }}
          />
        </div>
      </div>
      {isPreviewable && viewMode === 'preview' ? (
        <PreviewComponent file={file} />
      ) : (
        <CodeMirrorView file={file} isPreviewOpening={isPreviewOpening} />
      )}
    </div>
  )
}

const saveChanges = debounce(
  (file: File, fileValue: string, updateItem: (file: File) => void) => {
    const updatedFile = {...file, value: fileValue}
    updateItem(updatedFile)
  },
  500,
  {leading: false, trailing: true},
)

function CodeMirrorView({file, isPreviewOpening}: {file: File; isPreviewOpening: boolean}) {
  const {openItem, updateItem, versionedItems} = useContentPreview()
  const focusNextRenderRef = useRef<boolean>(false)
  const isLatest = isLatestVersion(versionedItems, file)
  const isEditableFileType = !file.reference || file.reference.type === 'thread-scoped-file'
  const isEditable = isEditableFileType && !file.isStreaming && isLatest
  const labelId = useId()
  const codeMirrorOptions = useGuessCodeMirrorSettings(file)
  const [editedValue, setEditedValue] = useState<{value: string; id: string}>()
  const fileValue = editedValue?.id === file.id ? editedValue.value : file.value

  const {messages} = useChatState()

  useEffect(() => {
    if (isPreviewOpening) {
      focusNextRenderRef.current = true
    }
  }, [isPreviewOpening])

  const onChange = useStableCallback(
    useCallback(
      (value: string) => {
        if (!isEditable || value === file.value) return
        if (!file.isUserEdited) {
          const newFile: File = {
            ...file,
            messageId: NullMessageId,
            id: `file:${file.name}#${messages.length}`,
            timestamp: new Date(),
            isUserEdited: true,
            value,
          }
          updateItem(newFile)
          openItem(newFile.id)
          setEditedValue({value, id: newFile.id})
        } else {
          // we want to re-render this component though, so as to keep CodeMirror in sync with its props
          setEditedValue({value, id: file.id})
          saveChanges(file, value, updateItem)
        }
      },
      [file, isEditable, messages.length, openItem, updateItem],
    ),
  )

  return (
    <>
      <span id={labelId} className="sr-only">
        {file.name} file contents
      </span>
      <CodeMirror
        ariaLabelledBy={labelId}
        containerClassName={styles.codeMirrorContainer}
        fileName={file.name}
        height="100%"
        isReadOnly={!isEditable}
        spacing={codeMirrorOptions}
        value={fileValue}
        onChange={onChange}
        focusNextRenderRef={focusNextRenderRef}
        placeholder="Loading..."
        hideHelp
      />
      {isEditableFileType && !isLatest && (
        <div className={styles.footer}>Switch to the latest version to edit this file.</div>
      )}
    </>
  )
}

function PreviewComponent({file}: {file: File}) {
  if (file.language === 'markdown') {
    return (
      <div className={styles.previewContainer}>
        <MarkdownPreview file={file} />
      </div>
    )
  } else if (file.language === 'html') {
    return (
      <div className={styles.previewContainer}>
        <HtmlPreview file={file} />
      </div>
    )
  } else {
    return null
  }
}

function isLatestVersion(versionedItems: VersionedItemsMap, file: PreviewableContent) {
  const versions = versionedItems.get(stripVersionFromId(file.id)) ?? []
  return versions[versions.length - 1] === file.id
}

/**
 * Returns a function reference that never changes but always calls the latest function passed in.
 */
export const useStableCallback = <A extends unknown[], R>(fn: (...args: A) => R): ((...args: A) => R | undefined) => {
  const trackingRef = useTrackingRef(fn)

  return useCallback((...args: A) => trackingRef.current?.(...args), [trackingRef])
}
