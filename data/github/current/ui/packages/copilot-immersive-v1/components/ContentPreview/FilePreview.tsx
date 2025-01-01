import CodeMirror from '@github-ui/code-mirror'
import {useChatState} from '@github-ui/copilot-chat/CopilotChatContext'
import {CopyToClipboardButton} from '@github-ui/copy-to-clipboard/Button'
import {sendEvent} from '@github-ui/hydro-analytics'
import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'
import {DownloadIcon} from '@primer/octicons-react'
import {Button, IconButton, SegmentedControl} from '@primer/react'
import {useCallback, useEffect, useId, useMemo, useState} from 'react'

import {guessCodeMirrorSettings} from '../../utils/code-mirror-config'
import {useHydrateReference} from '../../utils/use-hydrate-reference'
import {
  type File,
  type PreviewableContent,
  stripVersionFromId,
  type VersionedItemsMap,
  type VersionedPreviewableContentIdentifier,
} from './content-preview-types'
import {useContentPreview} from './ContentPreviewContext'
import {downloadFile} from './download-file'
import styles from './FilePreview.module.css'
import {HtmlPreview} from './HtmlPreview'
import {MarkdownPreview} from './MarkdownPreview'
import {VersionSelector} from './VersionSelector'

interface FilePreviewProps {
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
  const previewAdditionalFormats = useFeatureFlag('copilot_immersive_file_preview_additional_formats')

  const previewHtmlFiles = useFeatureFlag('copilot_immersive_preview_html_files')

  return useMemo(() => {
    const bytes = new Blob([file.value]).size
    const previewableLanguages = new Set<string>()
    if (previewAdditionalFormats) {
      previewableLanguages.add('markdown')
    }

    if (previewHtmlFiles) {
      previewableLanguages.add('html')
    }

    return {
      linesOfCode: file.value.split('\n').length,
      isPreviewable: previewableLanguages.has(file.language),
      size: prettySize(bytes),
    }
  }, [file.language, file.value, previewAdditionalFormats, previewHtmlFiles])
}

export function FilePreview({file, onClose}: FilePreviewProps) {
  const {openItem, removeItems, updateItem, versionedItems} = useContentPreview()
  const state = useChatState()
  const fileMessage = file.isStreaming
    ? state.messages[state.messages.length - 1]
    : state.messages.find(message => message.id === file.messageId)
  const {linesOfCode, isPreviewable, size} = useFileInfo(file)
  useHydrateReference(file, updateItem)

  const [viewMode, setViewMode] = useState<'code' | 'preview'>('code')

  const handleRevert = useCallback(() => {
    const previousVersionId = getPreviousVersionId(file.id, versionedItems)
    if (previousVersionId) {
      openItem(previousVersionId)
    }
    removeItems([file.id])
  }, [file.id, openItem, removeItems, versionedItems])

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
          <VersionSelector item={file} />
          <p className={styles.toolbarLoC}>
            {linesOfCode} {linesOfCode === 1 ? 'line' : 'lines'} · {size}
          </p>
        </div>
        <div className={styles.toolbarActions}>
          {file.isUserEdited && <Button onClick={handleRevert}>Revert</Button>}
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
              downloadFile(new File([file.value], file.name))
              sendEvent('dotcom_chat.activate', {target: 'BROWSER_FILE_DOWNLOAD', mode: 'immersive'})
            }}
          />
        </div>
      </div>
      <div className={styles.contentWrapper}>
        {isPreviewable && viewMode === 'preview' ? <PreviewComponent file={file} /> : <CodeMirrorView file={file} />}
      </div>
    </div>
  )
}

function CodeMirrorView({file}: {file: File}) {
  const {openItem, updateItem, versionedItems} = useContentPreview()
  const isLatest = isLatestVersion(versionedItems, file)
  const isEditable = useFeatureFlag('copilot_immersive_edit_file') && !file.isStreaming && isLatest && !file.reference
  const labelId = useId()
  const codeMirrorOptions = useMemo(() => guessCodeMirrorSettings(file), [file])
  const [editedValue, setEditedValue] = useState<{value: string; id: string}>()
  const fileValue = editedValue?.id === file.id ? editedValue.value : file.value

  const onChange = useCallback(
    (value: string) => {
      if (!isEditable || value === file.value) return
      if (!file.isUserEdited) {
        const newFile: File = {
          ...file,
          id: `file:${file.name}#${Date.now()}`,
          timestamp: new Date(),
          isUserEdited: true,
        }
        updateItem(newFile)
        openItem(newFile.id)
        setEditedValue({value, id: newFile.id})
      } else {
        // updateFile doesn't change the file object, so as not to cause everything that sees it from ContentPreviewContext to re-render on every keystroke
        updateFile(file, value)
        // we want to re-render this component though, so as to keep CodeMirror in sync with its props
        setEditedValue({value, id: file.id})
      }
    },
    [file, isEditable, openItem, updateItem],
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
        placeholder="Loading..."
      />
    </>
  )
}

function PreviewComponent({file}: {file: File}) {
  if (file.language === 'markdown') {
    return <MarkdownPreview file={file} />
  } else if (file.language === 'html') {
    return <HtmlPreview file={file} />
  } else {
    return null
  }
}

function getPreviousVersionId(id: VersionedPreviewableContentIdentifier, versionedItems: VersionedItemsMap) {
  const unversionedId = stripVersionFromId(id)
  const versions = versionedItems.get(unversionedId) ?? []
  const currentVersionIndex = versions.indexOf(id)
  const previousVersionId = versions[currentVersionIndex - 1]
  return previousVersionId
}

function isLatestVersion(versionedItems: VersionedItemsMap, file: PreviewableContent) {
  const versions = versionedItems.get(stripVersionFromId(file.id)) ?? []
  return versions[versions.length - 1] === file.id
}

function updateFile(file: File, value: string) {
  // we put this in a function to fool the react compiler
  // you really shouldn't be changing things like this without going through react updates
  // but CodeMirror doesn't live in react and by the time we get the change it's already visible and there's no need for react to get all excited about it
  file.value = value
}
