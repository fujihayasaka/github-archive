import {CopyToClipboardButton} from '@github-ui/copy-to-clipboard/Button'
import styles from './CodeBlock.module.css'
import {getLanguageInfo} from '@github-ui/copilot-chat/utils/language-info'
import {useContext, type PropsWithChildren} from 'react'
import {LanguageDot} from './LanguageDot'
import {ExtensionContext} from '../ExtensionContext'
import {clsx} from 'clsx'

import {sendEvent} from '@github-ui/hydro-analytics'

export interface CodeBlockProps {
  language: string
  code: string
}

export function CodeBlock({language, children, code}: PropsWithChildren<CodeBlockProps>) {
  const {color, name: displayName} = getLanguageInfo(language)

  const extensionContext = useContext(ExtensionContext)

  return (
    <figure
      className={clsx(styles.container, {
        [styles.immersive]: extensionContext.chatMode === 'immersive',
        [styles.assistive]: extensionContext.chatMode === 'assistive',
      })}
    >
      <figcaption className={styles.header}>
        <LanguageDot color={color} />
        <span className={styles.languageName}>{displayName || 'Code'}</span>
      </figcaption>
      <div className={styles.copyContainer}>
        <div className={styles.copyContent}>
          <CopyToClipboardButton
            textToCopy={code}
            ariaLabel="Copy code"
            className={styles.copyButton}
            size={extensionContext.chatMode === 'assistive' ? 'small' : 'medium'}
            onCopy={() => {
              sendEvent('dotcom_chat.activate', {
                target: 'CODE_BLOCK_COPY',
                mode: extensionContext.chatMode,
              })
            }}
          />
        </div>
      </div>
      <div className={styles.codeContainer}>
        {/* eslint-disable-next-line jsx-a11y/no-noninteractive-tabindex*/}
        <pre className={styles.code} tabIndex={0}>
          <code>{children}</code>
        </pre>
      </div>
    </figure>
  )
}
