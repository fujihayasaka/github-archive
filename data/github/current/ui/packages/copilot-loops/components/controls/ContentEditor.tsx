import CodeMirror from '@github-ui/code-mirror'
import styles from './ContentEditor.module.css'
import {clsx} from 'clsx'
import type {Extension} from '@codemirror/state'
import {EditorView} from '@codemirror/view'

/**
 * Custom extension to set a smaller font size
 */
const smallFontSizeTheme = EditorView.theme({
  '.cm-content': {
    fontSize: 'var(--text-body-size-small, 12px) !important',
    lineHeight: '18px !important',
  },
  '.cm-gutterElement': {
    fontSize: 'var(--text-body-size-small, 12px) !important',
  },
  '.cm-scroller': {
    scrollbarWidth: 'thin',
  },
})

export const ContentEditor = ({
  className,
  content,
  onUpdate,
  placeholder = 'Enter a prompt',
  extensions,
  inputLabelId,
}: {
  className?: string
  content: string
  onUpdate?: (content: string) => void
  placeholder?: string
  extensions?: Extension[]
  inputLabelId: string
}) => {
  return (
    <form className={clsx(styles.container, className)}>
      <CodeMirror
        ariaLabelledBy={inputLabelId}
        containerClassName={styles.cmContainer}
        extensions={[smallFontSizeTheme, ...(extensions ?? [])]}
        height="100%"
        hideHelp
        onChange={value => onUpdate?.(value)}
        placeholder={placeholder}
        spacing={{
          indentUnit: 2,
          indentWithTabs: false,
          lineWrapping: true,
        }}
        value={content}
      />
    </form>
  )
}
