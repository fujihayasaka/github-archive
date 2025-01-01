// eslint-disable-next-line @github-ui/github-monorepo/filename-convention
import {GitHubAvatar} from '@github-ui/github-avatar'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {usePreviousValue} from '@github-ui/use-previous-value'
import {clsx} from 'clsx'
import type {editor as editorTypes, IRange} from 'monaco-editor'
import {useCallback, useEffect, useRef} from 'react'
import {createRoot} from 'react-dom/client'

import styles from '../components/Editor.module.css'
import {useFilesContext} from '../contexts/FilesContext'
import {useSuggestionContext} from '../contexts/SuggestionContext'
import {isDeleted, isModified} from '../utilities/file-status-helpers'
import {getUniqueSuggestionRangesForTask, isSuggestionAlreadyApplied} from '../utilities/suggestion-helpers'
import {TaskTypes, type WorkspaceEditorRoutePayload} from '../utilities/workspace-editor-types'
import {useLocalSuggestionState} from './use-local-suggestion-state'

const COMMENT_TYPE_TO_DECORATION_TEXT = {
  [TaskTypes.Autofix]: 'Suggestion by',
  [TaskTypes.Generative]: 'Thread by',
  [TaskTypes.Suggestion]: 'Suggestion by',
}

const DEFAULT_DECORATION_TEXT = 'Suggestion by'

function registerCommentDecoration({
  editor,
  highlightedLinesDecoration,
  range,
  trailingLineDecoration,
}: {
  editor: editorTypes.IStandaloneCodeEditor
  highlightedLinesDecoration: {
    contentClassName: string
    marginClassName: string
  }
  range: Pick<IRange, 'startLineNumber' | 'endLineNumber'>
  trailingLineDecoration: {
    marginContent: JSX.Element | null
    lineContent: JSX.Element | null
    contentClassName: string
  }
}): {
  dispose: () => void
} {
  const {startLineNumber, endLineNumber} = range
  const {contentClassName, lineContent, marginContent} = trailingLineDecoration
  let viewZoneId: string | undefined

  // use a view zone to insert the comment widget at the bottom of the commented-on range
  editor.changeViewZones(changer => {
    const codeWidget = document.createElement('div')
    codeWidget.classList.add(contentClassName)
    codeWidget.classList.add(styles.commentWidgetLineContent ?? '')
    const codeWidgetRoot = createRoot(codeWidget)
    codeWidgetRoot.render(lineContent)

    const marginWidget = document.createElement('div')
    marginWidget.classList.add(contentClassName)
    marginWidget.classList.add(styles.commentWidgetLineNumber ?? '')
    const marginWidgetRoot = createRoot(marginWidget)
    marginWidgetRoot.render(marginContent)

    viewZoneId = changer.addZone({
      afterLineNumber: endLineNumber,
      domNode: codeWidget,
      heightInLines: 1,
      marginDomNode: marginWidget,
    })
  })

  const diposeViewZone = () => {
    editor.changeViewZones(changer => {
      if (!viewZoneId) return
      changer.removeZone(viewZoneId)
    })
  }

  // use a decoration to set the background of the commented-on range of lines
  const {contentClassName: highlightedLinesContentClassName, marginClassName: highlightedLinesMarginClassName} =
    highlightedLinesDecoration
  const collection: editorTypes.IModelDeltaDecoration[] = [
    {
      range: {
        startColumn: 1,
        endColumn: 1,
        startLineNumber,
        endLineNumber: startLineNumber,
      },
      options: {
        marginClassName: clsx(highlightedLinesMarginClassName, styles.firstHighlightedCommentLineNumber),
        isWholeLine: true,
        className: clsx(highlightedLinesContentClassName, styles.firstHighlightedCommentLineContent),
        shouldFillLineOnLineBreak: true,
      },
    },
  ]

  if (startLineNumber !== endLineNumber) {
    collection.push({
      range: {
        startColumn: 1,
        endColumn: 1,
        startLineNumber: startLineNumber + 1,
        endLineNumber,
      },
      options: {
        marginClassName: highlightedLinesMarginClassName,
        isWholeLine: true,
        className: highlightedLinesContentClassName,
        shouldFillLineOnLineBreak: true,
      },
    })
  }

  const decorationCollection = editor.createDecorationsCollection(collection)

  return {
    dispose: () => {
      diposeViewZone?.()
      decorationCollection.clear()
    },
  }
}

/**
 * Hook that manages adding and removing comment decorations for the focused task. The registration functions need
 * to be called when monaco mounts so it can get a reference to the editor object.
 *
 * @returns a function `registerCommentDecorations` that should be called whenever the editor changes.
 */
export function useFocusedCommentDecorations() {
  const {path} = useRoutePayload<WorkspaceEditorRoutePayload>()
  const disposeCollection = useRef<Array<() => void>>([])
  const currentEditor = useRef<editorTypes.IStandaloneCodeEditor | undefined>(undefined)
  const {getFileStatuses} = useFilesContext()
  const {getAppliedSuggestions} = useLocalSuggestionState()
  const prevPath = usePreviousValue(path)
  const {focusedTask} = useSuggestionContext()
  const prevTaskId = usePreviousValue(focusedTask?.sourceId)

  const currentFileStatus = getFileStatuses()[path]
  const appliedSuggestions = getAppliedSuggestions()
  const isCurrentTaskApplied = isSuggestionAlreadyApplied(appliedSuggestions, focusedTask?.sourceId ?? -1)

  const disposeDecorations = useCallback(() => {
    for (const dispose of disposeCollection.current) {
      dispose()
    }

    disposeCollection.current = []
  }, [])

  const registerCommentDecorations = useCallback(
    ({
      editor,
      scrollToFirstDecoration = true,
    }: {
      editor: editorTypes.IStandaloneCodeEditor
      scrollToFirstDecoration?: boolean
    }) => {
      currentEditor.current = editor

      // remove existing set of decorations
      disposeDecorations()

      const editorModel = editor.getModel()
      if (!editorModel || !focusedTask || focusedTask.outdated) return

      const comment = focusedTask
      const {avatarUrl, displayLogin} = focusedTask.author ?? {avatarUrl: '', displayLogin: ''}
      if (!comment || !comment.lineNumber) return

      const fileStatuses = getFileStatuses()
      const fileStatus = fileStatuses[path]
      if (isDeleted(fileStatus)) return

      let firstStartLineNumber: number | undefined

      // don't try to decorate modified files
      if (!isModified(fileStatus)) {
        const ranges = getUniqueSuggestionRangesForTask(path, focusedTask)
        firstStartLineNumber = ranges[0]?.startLineNumber

        for (const range of ranges) {
          const decorationText = COMMENT_TYPE_TO_DECORATION_TEXT[focusedTask.type] ?? DEFAULT_DECORATION_TEXT
          const {dispose} = registerCommentDecoration({
            editor,
            highlightedLinesDecoration: {
              marginClassName: styles.highlightedCommentLineNumber ?? '',
              contentClassName: styles.highlightedCommentLineContent ?? '',
            },
            range,
            trailingLineDecoration: {
              marginContent: (
                <GitHubAvatar className={styles.monacoCommentAvatar} src={avatarUrl} size={12} alt={displayLogin} />
              ),
              lineContent: (
                <code className={styles.commentWidgetContent}>
                  {decorationText} @{displayLogin}
                </code>
              ),
              contentClassName: styles.commentWidget ?? '',
            },
          })

          disposeCollection.current.push(dispose)
        }
      }

      // if the current task is applied, we override the scroll to first decoration
      // since the applied change will always be there to show the user
      if (scrollToFirstDecoration && firstStartLineNumber) {
        editor.revealLineNearTop(firstStartLineNumber)
      }
    },
    [disposeDecorations, focusedTask, getFileStatuses, path],
  )

  // re-register decorations when:
  // - the current file changes
  // - the focused task changes
  // - the list of modified file changes (if the target file is modified, we'll remove decorations)
  useEffect(() => {
    if (!currentEditor.current) return

    const pathChanged = prevPath !== path
    const taskChanged = prevTaskId !== focusedTask?.sourceId
    const scrollToAppliedChange = pathChanged && isCurrentTaskApplied
    const isFileModified = isModified(currentFileStatus)

    // if the file is modified, we don't want to show the decorations unless the user is navigating
    // to the file that contains the focused task and it is applied. In that case, we want to scroll the applied
    // change into view
    const scrollToFirstDecoration = scrollToAppliedChange || (!isFileModified && (pathChanged || taskChanged))
    registerCommentDecorations({editor: currentEditor.current, scrollToFirstDecoration})
    // only run the effect when the current file status changes, since previous value will be updated on the next render
    // eslint-disable-next-line react-hooks/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [currentFileStatus, registerCommentDecorations])

  return {registerCommentDecorations}
}
