import {CopyToClipboardButton} from '@github-ui/copy-to-clipboard/Button'
import {sendEvent} from '@github-ui/hydro-analytics'
import {useMonacoEditor} from '@github-ui/monaco-editor/hooks/useMonacoEditor'
import {Editor as MonacoEditor, type EditorProps as MonacoEditorProps, useMonaco} from '@monaco-editor/react'
import {useTheme} from '@primer/react'
import {useCallback} from 'react'

import type {File} from '../../utils/content-preview-types'
import styles from './FilePreview.module.css'

interface FilePreviewProps {
  file: File
}

export function FilePreview({file}: FilePreviewProps) {
  const monaco = useMonaco()
  const {resolvedColorMode} = useTheme()
  const {beforeMount} = useMonacoEditor()

  const getLinesOfCode = useCallback(() => {
    if (monaco && file.path) {
      const model = monaco.editor.getModels().find(nextModel => nextModel.uri.path.includes(file.path))
      return model?.getLineCount() || 0
    }
    return 0
  }, [monaco, file.path])

  const theme = resolvedColorMode === 'night' ? 'github-dark' : 'github-light'

  const options: MonacoEditorProps['options'] = {
    minimap: {enabled: false},
    overviewRulerLanes: 0,
    overviewRulerBorder: false,
    hideCursorInOverviewRuler: true,
    readOnly: true,
    fixedOverflowWidgets: true,
    padding: {top: 8},
    fontSize: 14,
    wordWrap: 'off',
    scrollbar: {
      vertical: 'hidden',
      horizontal: 'hidden',
    },
  }

  return (
    <>
      <div className={styles.toolbar}>
        <p className={styles.toolBarLoC}>{getLinesOfCode()} lines</p>
        <CopyToClipboardButton
          textToCopy={file.value}
          ariaLabel={'Copy code'}
          onCopy={() => sendEvent('dotcom_chat.activate', {target: 'BROWSER_FILE_COPY', mode: 'immersive'})}
        />
      </div>

      <MonacoEditor
        theme={theme}
        options={options}
        beforeMount={beforeMount}
        path={file.path}
        defaultLanguage={file.language}
        defaultValue={file.value}
      />
    </>
  )
}
