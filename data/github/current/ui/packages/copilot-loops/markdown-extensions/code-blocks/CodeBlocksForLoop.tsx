import {CopyToClipboardButton} from '@github-ui/copy-to-clipboard/Button'
import styles from './CodeBlocks.module.css'
import {useContext, type PropsWithChildren, useId} from 'react'
import {ExtensionContext} from '@github-ui/copilot-markdown/ExtensionContext'
import {clsx} from 'clsx'
import {sendEvent} from '@github-ui/hydro-analytics'

export interface CodeBlocksForLoopProps {
  language?: string
  code: string
  startOffset: number
  endOffset: number
}

export function CodeBlocksForLoop({children, code}: PropsWithChildren<CodeBlocksForLoopProps>) {
  const codeBlockLabelId = useId()
  const {chatMode, wrapCodeLines} = useContext(ExtensionContext)

  return (
    <>
      <figure className={clsx(styles.container, styles.immersive)} aria-labelledby={codeBlockLabelId}>
        <div className={clsx(styles.copyContainer)}>
          <div className={clsx(styles.copyContent)}>
            <CopyToClipboardButton
              textToCopy={code}
              ariaLabel="Copy code"
              className={styles.copyButton}
              size="small"
              onCopy={() => {
                sendEvent('dotcom_chat.activate', {
                  target: 'CODE_BLOCK_COPY',
                  mode: chatMode,
                })
              }}
            />
          </div>
        </div>
        <div className={clsx(styles.codeContainer)}>
          {/* eslint-disable-next-line jsx-a11y/no-noninteractive-tabindex*/}
          <pre className={styles.code} tabIndex={0}>
            <code className={clsx(wrapCodeLines && styles.codeWrap)}>{children}</code>
          </pre>
        </div>
      </figure>
    </>
  )
}
