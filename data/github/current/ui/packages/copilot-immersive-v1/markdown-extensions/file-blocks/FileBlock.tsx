import {getLanguageInfo} from '@github-ui/copilot-chat/utils/language-info'
import type {ReactBlockAttributes} from '@github-ui/copilot-markdown/extension'
import {LanguageDot} from '@github-ui/copilot-markdown/extensions/code-blocks/LanguageDot'
import {CopyToClipboardButton} from '@github-ui/copy-to-clipboard/Button'
import {SafeHTMLDiv} from '@github-ui/safe-html'
import {IconButton} from '@primer/react'
import hljs from 'highlight.js'
import {useMemo} from 'react'

import {useContentPreview} from '../../hooks/use-content-preview'
import {useContentPreviewBlockContext} from '../ContentPreviewBlockContext'
import {ExpandIcon} from './ExpandIcon'
import styles from './FileBlock.module.css'
import {StateSpinner} from './StateSpinner'

export const languageAttribute = 'data-fileblock-lang'
export const nameAttribute = 'data-fileblock-name'
export const isCompleteAttribute = 'data-is-complete'

export const fileBlockAttributes = [languageAttribute, nameAttribute, isCompleteAttribute]

const previewLines = 4

export function FileBlock({
  [languageAttribute]: language = '',
  [nameAttribute]: name = '',
  [isCompleteAttribute]: isCompleteStr = '',
  children: code,
}: ReactBlockAttributes) {
  const {appendPreviewItem} = useContentPreview()
  const {messageId} = useContentPreviewBlockContext()
  const isComplete = Boolean(isCompleteStr)

  const {color} = getLanguageInfo(language)

  const previewCode = code.split('\n').slice(0, previewLines).join('\n')
  const highlighted = useMemo(() => {
    if (!language) return null

    try {
      return hljs.highlight(previewCode, {language}).value
    } catch {
      // unrecognized language ID; just render plain text
      return null
    }
  }, [previewCode, language])

  const emitOpenFile = () =>
    appendPreviewItem({
      messageId,
      path: `${messageId}/${name}`,
      language,
      name,
      value: code,
      type: 'file',
    })

  return (
    <figure className={styles.container}>
      <figcaption className={styles.header}>
        {isComplete ? <LanguageDot color={color} /> : <StateSpinner />}
        <span className={styles.name}>{name}</span>

        <span className={styles.actions}>
          <CopyToClipboardButton ariaLabel="Copy code" textToCopy={code} size="small" />
          <IconButton
            icon={ExpandIcon}
            aria-label="View file"
            size="small"
            onClick={emitOpenFile}
            variant="invisible"
          />
        </span>
      </figcaption>

      <pre className={styles.previewCode} aria-hidden>
        <code>{highlighted ? <SafeHTMLDiv unverifiedHTML={highlighted} /> : previewCode}</code>
      </pre>
    </figure>
  )
}
