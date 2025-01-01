import {debounce} from '@github/mini-throttle'
import {useCurrentRepository} from '@github-ui/current-repository'
import {MarkdownViewer} from '@github-ui/markdown-viewer'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import type {EditorProps, OnChange} from '@monaco-editor/react'
import type {editor} from 'monaco-editor'
import {useCallback, useMemo, useRef} from 'react'

import {useMarkdownPreview} from '../hooks/use-markdown-preview'
import type {WorkbenchRoutePayload} from '../types/workbench-types'
import {EditorLoadingSkeleton} from './EditorLoadingSkeleton'
import {MonacoEditor, type MonacoEditorProps} from './MonacoEditor'

export const EditorMode = {
  Edit: 0,
  Preview: 1,
  Split: 2,
} as const

export type EditorMode = (typeof EditorMode)[keyof typeof EditorMode]

export type MarkdownEditorProps = {
  editorMode: EditorMode
  height: number | string
  saveChanges: OnChange
  editorSettings: EditorProps & {options: MonacoEditorProps['options']}
}

export function MarkdownEditor({editorMode, height, saveChanges, editorSettings}: MarkdownEditorProps) {
  const editorSplit = useRef<editor.IStandaloneCodeEditor | null>(null)
  const previewSplit = useRef<HTMLDivElement>(null)
  const {ownerLogin, name, id: repositoryId} = useCurrentRepository()
  const {path} = useRoutePayload<WorkbenchRoutePayload>()
  const valueToPreview = editorSettings.value
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
      saveChanges?.(val, ev)

      updatePreviewContent(val || '')
    },
    [saveChanges, updatePreviewContent],
  )

  const debouncedHandleLivePreviewChange = useMemo(
    () => debounce(handleLivePreviewChange, 1000),
    [handleLivePreviewChange],
  )

  const editor = useMemo(() => {
    const {language, value, theme, options, onMount, beforeMount} = editorSettings
    const loadSkeleton = <EditorLoadingSkeleton />

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
        loading={loadSkeleton}
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
    <div className="overflow-y-auto" style={{height, width: '100%'}}>
      {renderComponent()}
    </div>
  )
}
