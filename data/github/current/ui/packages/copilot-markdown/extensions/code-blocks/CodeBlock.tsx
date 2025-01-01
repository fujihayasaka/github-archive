import {CopyToClipboardButton} from '@github-ui/copy-to-clipboard/Button'
import styles from './CodeBlock.module.css'
import {getLanguageInfo} from '@github-ui/copilot-chat/utils/language-info'
import {useContext, type PropsWithChildren, useState, useCallback, useId} from 'react'
import {LanguageDot} from './LanguageDot'
import {ExtensionContext} from '../ExtensionContext'
import {clsx} from 'clsx'
import {sendEvent} from '@github-ui/hydro-analytics'
import {useFilteredCopilotAnnotations} from '@github-ui/copilot-chat/hooks/use-filtered-copilot-annotations'
import {IconButton} from '@primer/react'
import {ShieldIcon} from '@primer/octicons-react'

import {CodeInsightsDialog} from './CodeInsightsDialog/CodeInsightsDialog'
import UnwrapIcon from './UnwrapIcon'
import WrapIcon from './WrapIcon'

export interface CodeBlockProps {
  language: string
  code: string
  startOffset: number
  endOffset: number
}

export function CodeBlock({language, children, code, startOffset, endOffset}: PropsWithChildren<CodeBlockProps>) {
  const {color, name: displayName} = getLanguageInfo(language)
  const codeBlockLabelId = useId()

  const {copilotAnnotations, chatMode, wrapCodeLines, onWrapCodeLinesChange} = useContext(ExtensionContext)

  const [isDialogOpen, setIsDialogOpen] = useState(false)

  const {publicCodeReferences, codeVulnerabilities} = useFilteredCopilotAnnotations(
    copilotAnnotations,
    startOffset,
    endOffset,
  )

  const onWrapToggle = useCallback(() => {
    onWrapCodeLinesChange?.(!wrapCodeLines)
    sendEvent('dotcom_chat.activate', {
      target: wrapCodeLines ? 'CODE_BLOCK_UNWRAP' : 'CODE_BLOCK_WRAP',
      mode: chatMode,
    })
  }, [onWrapCodeLinesChange, wrapCodeLines, chatMode])

  return (
    <>
      <figure
        className={clsx(styles.container, {
          [styles.immersive]: chatMode === 'immersive',
          [styles.assistive]: chatMode === 'assistive',
        })}
        aria-labelledby={codeBlockLabelId}
      >
        <div className={styles.header}>
          <LanguageDot color={color} />
          <span id={codeBlockLabelId} className={styles.languageName}>
            {displayName || 'Code'}
          </span>
          {onWrapCodeLinesChange && (
            <IconButton
              variant="invisible"
              icon={wrapCodeLines ? UnwrapIcon : WrapIcon}
              aria-label={wrapCodeLines ? 'Unwrap' : 'Wrap'}
              onClick={onWrapToggle}
            />
          )}
          {(publicCodeReferences.length > 0 || codeVulnerabilities.length > 0) && (
            <IconButton
              variant="invisible"
              icon={ShieldIcon}
              aria-label="Code insights"
              onClick={() => {
                setIsDialogOpen(true)
                sendEvent('dotcom_chat.activate', {
                  target: 'CODE_BLOCK_SHIELD',
                  mode: chatMode,
                })
              }}
            />
          )}
        </div>
        <div className={styles.copyContainer}>
          <div className={styles.copyContent}>
            <CopyToClipboardButton
              textToCopy={code}
              ariaLabel="Copy code"
              className={styles.copyButton}
              onCopy={() => {
                sendEvent('dotcom_chat.activate', {
                  target: 'CODE_BLOCK_COPY',
                  mode: chatMode,
                })
              }}
            />
          </div>
        </div>
        <div className={styles.codeContainer}>
          {/* eslint-disable-next-line jsx-a11y/no-noninteractive-tabindex*/}
          <pre className={styles.code} tabIndex={0}>
            <code className={clsx(wrapCodeLines && styles.codeWrap)}>{children}</code>
          </pre>
        </div>
      </figure>
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
