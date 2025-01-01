import {CopyToClipboardButton} from '@github-ui/copy-to-clipboard/Button'
import styles from './CodeBlock.module.css'
import {clsx} from 'clsx'
import {getLanguageInfo} from '@github-ui/copilot-chat/utils/language-info'
import type {ReactBlockAttributes} from '../../extension'
import hljs from 'highlight.js'
import {useMemo} from 'react'
import {SafeHTMLDiv} from '@github-ui/safe-html'
import {LanguageDot} from './LanguageDot'

export const languageAttribute = 'data-codeblock-lang'

export const codeBlockAttributes = [languageAttribute]

export function CodeBlock({[languageAttribute]: language = '', children}: ReactBlockAttributes) {
  const {color, name: displayName} = getLanguageInfo(language)

  const trimmedCode = children.trim()

  const highlighted = useMemo(() => {
    if (!language) return null

    try {
      return hljs.highlight(trimmedCode, {language}).value
    } catch {
      // unrecognized language ID; just render plain text
      return null
    }
  }, [trimmedCode, language])

  const multiline = trimmedCode.includes('\n')

  const code = (
    // eslint-disable-next-line jsx-a11y/no-noninteractive-tabindex
    <pre className={styles.code} tabIndex={0}>
      <code>{highlighted ? <SafeHTMLDiv unverifiedHTML={highlighted} /> : trimmedCode}</code>
    </pre>
  )

  const copyButton = (
    <CopyToClipboardButton textToCopy={trimmedCode} ariaLabel="Copy code" size="small" className={styles.copyButton} />
  )

  return multiline ? (
    <figure className={clsx(styles.container, styles.multiline)}>
      <figcaption className={styles.headerContainer}>
        <div className={styles.header}>
          <LanguageDot color={color} />
          <span className={styles.languageName}>{displayName || 'Code'}</span>
          {copyButton}
        </div>
      </figcaption>

      {code}
    </figure>
  ) : (
    <div className={clsx(styles.container, styles.singleLine)}>
      {code}
      {copyButton}
    </div>
  )
}
