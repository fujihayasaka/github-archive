import {debounce} from '@github/mini-throttle'
import {useCurrentRepository} from '@github-ui/current-repository'
import {MarkdownViewer} from '@github-ui/markdown-viewer'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {
  DiffEditor,
  type DiffEditorProps,
  Editor as MonacoEditor,
  type EditorProps,
  type OnChange,
} from '@monaco-editor/react'
import type {editor} from 'monaco-editor'
import {useCallback, useMemo, useRef} from 'react'

import {EditorLoadingSpinner} from '../../workspace-editor/components/EditorLoadingSpinner'
import type {WorkspaceEditorRoutePayload} from '../../workspace-editor/utilities/workspace-editor-types'
import {useMarkdownPreview} from '../hooks/use-markdown-preview'

export const EditorMode = {
  Edit: 0,
  Preview: 1,
  Split: 2,
} as const

export type EditorMode = (typeof EditorMode)[keyof typeof EditorMode]

export type MarkdownEditorProps = {
  editorMode: EditorMode
  showDiff: boolean
  height: number | string
  saveChanges: OnChange
  diffEditorSettings: DiffEditorProps
  editorSettings: EditorProps
}

export function MarkdownEditor({
  editorMode,
  showDiff,
  height,
  saveChanges,
  editorSettings,
  diffEditorSettings,
}: MarkdownEditorProps) {
  const editorSplit = useRef<editor.IStandaloneCodeEditor | null>(null)
  const previewSplit = useRef<HTMLDivElement>(null)
  const {ownerLogin, name, id: repositoryId} = useCurrentRepository()
  const {path} = useRoutePayload<WorkspaceEditorRoutePayload>()
  const valueToPreview = showDiff ? diffEditorSettings.modified : editorSettings.value
  const {previewContent, updatePreviewContent} = useMarkdownPreview(
    valueToPreview || '',
    ownerLogin,
    name,
    repositoryId,
  )

  const handleRightScroll = useCallback(() => {
    if (!editorSplit.current || !previewSplit.current) return
    editorSplit.current.setScrollTop(previewSplit.current.scrollTop)
  }, [])

  const handleLivePreviewChange = useCallback(
    (val: string | undefined, ev: editor.IModelContentChangedEvent) => {
      if (!showDiff) saveChanges?.(val, ev)

      updatePreviewContent(val || '')
    },
    [saveChanges, showDiff, updatePreviewContent],
  )

  const debouncedHandleLivePreviewChange = useMemo(
    () => debounce(handleLivePreviewChange, 1000),
    [handleLivePreviewChange],
  )

  const traditionalEditor = useMemo(() => {
    const {language, value, theme, options, onMount, beforeMount} = editorSettings
    const loadSpinner = <EditorLoadingSpinner />

    return (
      <MonacoEditor
        defaultLanguage={editorSettings.language || 'javascript'}
        value={value}
        language={language}
        path={path}
        theme={theme}
        options={options}
        onChange={debouncedHandleLivePreviewChange}
        beforeMount={beforeMount}
        loading={loadSpinner}
        onMount={(etr, monaco) => {
          onMount?.(etr, monaco)

          if (editorMode === EditorMode.Split) {
            editorSplit.current = etr

            etr.onDidScrollChange(() => {
              previewSplit.current?.scrollTo(etr.getScrollLeft(), etr.getScrollTop())
            })
          }
        }}
      />
    )
  }, [debouncedHandleLivePreviewChange, editorMode, editorSettings, path])

  const diffEditor = useMemo(() => {
    const {original, modified, language, theme, options, onMount, beforeMount} = diffEditorSettings
    const loadSpinner = <EditorLoadingSpinner />

    return (
      <DiffEditor
        original={original}
        modified={modified}
        key={path} // forces re-render of component, for correct Diffing on file change
        language={language || 'javascript'}
        theme={theme}
        options={options}
        beforeMount={beforeMount}
        loading={loadSpinner}
        onMount={(etr, monaco) => {
          onMount?.(etr, monaco)

          const modifiedEditor = etr.getModifiedEditor()
          modifiedEditor.onDidChangeModelContent((e: editor.IModelContentChangedEvent) => {
            saveChanges?.(modifiedEditor.getValue(), e)
            debouncedHandleLivePreviewChange(modifiedEditor.getValue(), e)
          })

          if (editorMode === EditorMode.Split) {
            editorSplit.current = modifiedEditor

            modifiedEditor.onDidScrollChange(() => {
              previewSplit.current?.scrollTo(modifiedEditor.getScrollLeft(), modifiedEditor.getScrollTop())
            })
          }
        }}
      />
    )
  }, [debouncedHandleLivePreviewChange, diffEditorSettings, editorMode, path, saveChanges])

  const editor = useMemo(() => {
    return showDiff ? diffEditor : traditionalEditor
  }, [diffEditor, showDiff, traditionalEditor])

  function renderComponent() {
    switch (editorMode) {
      case EditorMode.Edit:
        return editor
      case EditorMode.Preview:
        return (
          <div className="p-4">
            <MarkdownViewer verifiedHTML={previewContent} />
          </div>
        )
      case EditorMode.Split:
        return (
          <div className="d-flex height-full">
            <div style={{width: '50%'}}>{editor}</div>
            <div style={{width: '50%'}} className="p-4 overflow-y-auto" ref={previewSplit} onScroll={handleRightScroll}>
              <MarkdownViewer verifiedHTML={previewContent} />
            </div>
          </div>
        )
    }
  }

  return (
    <div className="overflow-y-auto" style={{height}}>
      {renderComponent()}
    </div>
  )
}
