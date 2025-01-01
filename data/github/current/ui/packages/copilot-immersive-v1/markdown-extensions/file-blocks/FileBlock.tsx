import {useChatMessage} from '@github-ui/copilot-chat/components/ChatMessageContext'
import {VersionName} from '@github-ui/copilot-chat/components/VersionName'
import {useFilteredCopilotAnnotations} from '@github-ui/copilot-chat/hooks/use-filtered-copilot-annotations'
import {NullMessageId} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {docLanguages, getLanguageInfo} from '@github-ui/copilot-chat/utils/language-info'
import {disableStreamingFadeIn} from '@github-ui/copilot-markdown'
import {CodeInsightsDialog} from '@github-ui/copilot-markdown/extensions/code-blocks/CodeInsightsDialog'
import {sendEvent} from '@github-ui/hydro-analytics'
import {CodeIcon, MarkdownIcon, ShieldIcon} from '@primer/octicons-react'
import {IconButton, Spinner} from '@primer/react'
import {clsx} from 'clsx'
import {type PropsWithChildren, useCallback, useEffect, useState} from 'react'

import {useContentPreview} from '../../components/ContentPreview/ContentPreviewContext'
import {useContentPreviewBlockContext} from '../ContentPreviewBlockContext'
import {ExpandIcon} from './ExpandIcon'
import styles from './FileBlock.module.css'

export interface FileBlockProps {
  language: string
  /** Filename, with extension. */
  name: string
  /** Full contents of the file. */
  code: string
  line: number
  /** Is there more code than is visible in the preview? */
  isClipped: boolean
  /** Is this block currently streaming? */
  isStreaming: boolean
  /** The index of the file block in the message */
  index: number
  /** The start offset of the file block in the message. */
  startOffset: number
  /** The end offset of the file block in the message. */
  endOffset: number
}

export function FileBlock({
  language,
  name,
  code,
  line,
  children,
  isClipped,
  isStreaming,
  index,
  startOffset,
  endOffset,
}: PropsWithChildren<FileBlockProps>) {
  const {message} = useChatMessage()

  const {updateItem, openItem: openFileBlock, openPreviewPane, versionedItems, openItems} = useContentPreview()
  const {messageIndex, messageId, messageTimestamp, autoOpenPreviewPane, markdown, hasAutoOpenedPreviewPaneRef} =
    useContentPreviewBlockContext()

  const {name: languageName} = getLanguageInfo(language)

  // The message ID is not stable because message IDs change when the streaming finishes (insert :wat: face here)
  // so we have to use the index instead, which is stable for now (until we implement conversation branching)
  // This is just a stopgap until we can fix message IDs to be stable throughout the message lifecycle
  const baseId = `file:${name}` as const
  const id = `${baseId}#${messageIndex}.${line}` as const

  // If no code yet received, the name might still be streaming. This would add multiple instances of this file since
  // they are uniquely identified by name
  const readyToPreview = !!code

  const versions = versionedItems.get(baseId) ?? []
  const versionIndex = versions.indexOf(id)
  const version = versions.length > 1 && versionIndex !== -1 ? versionIndex + 1 : null

  const openItem = useCallback(
    (openPane: boolean, userInitiated: boolean = true) => {
      sendEvent('dotcom_chat.activate', {target: 'BROWSER_FILE_OPENED', mode: 'immersive'})
      openFileBlock(id, userInitiated || openItems.length < 1 || index === 0)

      if (openPane) openPreviewPane()
    },
    [openFileBlock, id, openItems.length, index, openPreviewPane],
  )

  useEffect(() => {
    // Check the contents are in the markdown to make sure the FileBlock
    // isn't trying to add a version for a different subthread message.
    const contents = code?.trimEnd()
    if (!readyToPreview || messageId === NullMessageId || markdown.indexOf(contents) === -1) return
    // don't auto-open here or the user wouldn't be able to close while streaming
    updateItem({
      messageId,
      id,
      language,
      name,
      value: code,
      type: 'file',
      timestamp: new Date(messageTimestamp),
      isStreaming,
      isUserEdited: false,
    })
  }, [code, language, messageId, name, updateItem, id, readyToPreview, messageTimestamp, isStreaming, markdown])

  // automatically open the pane only when this block starts streaming.
  // messageId may be NullMessageId if switching to a new subtread, and this fileblock existed in the old subthread.
  useEffect(() => {
    if (isStreaming && readyToPreview && messageId !== NullMessageId) {
      openItem(autoOpenPreviewPane && !hasAutoOpenedPreviewPaneRef.current, false)
      // only auto open the pane once per message.
      // suppress warning for ESLint bug that thinks refs defined in other files aren't refs.
      // eslint-disable-next-line react-hooks/react-compiler
      hasAutoOpenedPreviewPaneRef.current = true
    }
  }, [isStreaming, readyToPreview, openItem, autoOpenPreviewPane, messageId, hasAutoOpenedPreviewPaneRef])

  const [isDialogOpen, setIsDialogOpen] = useState(false)

  const {publicCodeReferences, codeVulnerabilities} = useFilteredCopilotAnnotations(
    message.copilotAnnotations,
    startOffset,
    endOffset,
  )

  return (
    <>
      <div className="position-relative">
        <button
          className={styles.container}
          onClick={() => openItem(true)}
          aria-label={`View file: ${name}`}
          data-testid={`chat-message-view-file-${name}`}
        >
          <div className={styles.header}>
            <div className={styles.language}>
              {/* The spinner's spinning is a CSS animation, so we have to disable the fade-in because it overrides the
          spin. We also disable it for the other icons so it doesn't look wierd when the spinner gets swapped out. */}
              {isStreaming ? (
                <Spinner size="small" className={disableStreamingFadeIn} />
              ) : docLanguages.has(languageName) ? (
                <MarkdownIcon className={disableStreamingFadeIn} />
              ) : (
                <CodeIcon className={disableStreamingFadeIn} />
              )}
              <span className={styles.name}>{name}</span>
              {version !== null && <VersionName version={version} />}
            </div>

            <div className={styles.expandIconContainer}>
              <ExpandIcon />
            </div>
          </div>

          <pre className={clsx(styles.previewCode, isClipped && styles.isClipped)} aria-hidden>
            <code>{children}</code>
          </pre>
        </button>

        {(publicCodeReferences.length > 0 || codeVulnerabilities.length > 0) && (
          <div className={styles.insightsButtonContainer}>
            <IconButton
              variant="invisible"
              size="small"
              icon={ShieldIcon}
              aria-label="Code insights"
              onClick={() => setIsDialogOpen(true)}
            />
          </div>
        )}
      </div>
      {isDialogOpen && (
        <CodeInsightsDialog
          publicCodeReferences={publicCodeReferences}
          codeVulnerabilities={codeVulnerabilities}
          onClose={() => setIsDialogOpen(false)}
        />
      )}
    </>
  )
}
