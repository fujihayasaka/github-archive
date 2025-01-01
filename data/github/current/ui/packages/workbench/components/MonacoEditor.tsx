/* Based on https://github.com/suren-atoyan/monaco-react/blob/master/src/Editor/Editor.tsx
 * Split from package to apply edits instead of setting value
 *
 * @monaco-editor/react
 * Copyright (c) 2018 Suren Atoyan
 * MIT License: https://github.com/suren-atoyan/monaco-react?tab=MIT-1-ov-file
 */
import type {EditorProps, Monaco} from '@monaco-editor/react'
import {loader} from '@monaco-editor/react'
import {clsx} from 'clsx'
import type {editor, IDisposable, Selection} from 'monaco-editor'
import {useCallback, useEffect, useRef, useState} from 'react'

import {useEditorContext} from '../contexts/EditorContext'
import {getOrCreateModel, noop} from '../monaco/get-or-create-model'
import {type EditorEdit, getDiffLines, getEditorEdits} from '../utilities/get-diff-lines'
import styles from './MonacoEditor.module.css'

const viewStates = new Map()

const DEFAULT_OPTIONS = {}
const DEFAULT_OVERRIDE_SERVICES = {}
const DEFAULT_WRAPPER_PROPS = {}

const FADED_OUT_TO_EDITS_DELAY = 1000
const LINE_BY_LINE_ANIMATION_DELAY = 30

export type MonacoEditorProps = EditorProps & {
  options?: editor.IStandaloneEditorConstructionOptions & {
    /*
     * shouldDiffChanges: Compare current value with the value in the editor
     * and highlight the changes
     * @default false
     */
    shouldDiffChanges?: boolean
    /*
     * isStaleContent: Fades out the content of the editor when the file is stale
     */
    isStaleContent?: boolean
  }
}
export function MonacoEditor({
  defaultValue,
  defaultLanguage,
  defaultPath,
  value,
  language,
  path,
  /* === */
  theme = 'light',
  line,
  loading = 'Loading...',
  options: {shouldDiffChanges, isStaleContent, ...options} = DEFAULT_OPTIONS,
  overrideServices = DEFAULT_OVERRIDE_SERVICES,
  saveViewState = true,
  // keepCurrentModel = false,
  /* === */
  width = '100%',
  height = '100%',
  className,
  wrapperProps = DEFAULT_WRAPPER_PROPS,
  /* === */
  beforeMount = noop,
  onMount = noop,
  onChange,
  onValidate = noop,
}: MonacoEditorProps) {
  const [isEditorReady, setIsEditorReady] = useState(false)
  const [isMonacoMounting, setIsMonacoMounting] = useState(true)
  const monacoRef = useRef<Monaco | null>(null)
  const editorRef = useRef<editor.IStandaloneCodeEditor | null>(null)
  const containerRef = useRef<HTMLDivElement>(null)
  const onMountRef = useRef(onMount)
  const beforeMountRef = useRef(beforeMount)
  const subscriptionRef = useRef<IDisposable | undefined>(undefined)
  const preventCreation = useRef(false)
  const preventTriggerChangeEvent = useRef<boolean>(false)
  const animationTimeoutsRef = useRef<number[]>([])
  const fadedDecorationCollectionRef = useRef<Map<number, editor.IEditorDecorationsCollection[]> | null>(null)
  const {setIsAnimating, previousPath} = useEditorContext()

  // Run initializeMonaco only on mount and dispose only for cleanup
  useEffect(() => {
    const cancelable = loader.init()

    const initializeMonaco = async () => {
      try {
        const monaco = await cancelable
        monacoRef.current = monaco
        setIsMonacoMounting(false)
      } catch {
        // no action
      }
    }

    initializeMonaco()

    return () => {
      // Cancel load if still in progress
      if (!editorRef.current) {
        cancelable.cancel()
        return
      }

      // Dispose editor if it exists
      subscriptionRef.current?.dispose()
      editorRef.current.getModel()?.dispose()
      editorRef.current.dispose()
    }
  }, [])

  const resetAnimations = useCallback(
    (animationTimeouts: number[]) => {
      for (const timeoutId of animationTimeouts) {
        window.clearTimeout(timeoutId)
        setIsAnimating(false)
      }
    },
    [setIsAnimating],
  )

  useEffect(() => {
    const animationTimeouts = animationTimeoutsRef.current
    return () => {
      // Clear any pending animation timeouts on unmount
      for (const timeoutId of animationTimeouts) {
        window.clearTimeout(timeoutId)
        setIsAnimating(false)
      }
    }
  }, [setIsAnimating])

  const fadeContent = useCallback(() => {
    if (!editorRef.current || !monacoRef.current) return null

    const model = editorRef.current.getModel()
    if (!model) return null

    // Create a map of startLineNumber to an array of decoration collections
    const collection = fadedDecorationCollectionRef.current || new Map<number, editor.IEditorDecorationsCollection[]>()
    // Grey out entire page
    const lineCount = model.getLineCount() || 0
    for (let i = 1; i <= lineCount; i++) {
      const editCollection = editorRef.current.createDecorationsCollection([
        {
          range: new monacoRef.current.Range(i, 1, i, 1),
          options: {
            isWholeLine: true,
            className: styles.editFaded,
            marginClassName: styles.editFaded,
          },
        },
      ])

      // Get existing collections for this line or create a new array
      const existingCollections = collection.get(i) || []
      existingCollections.push(editCollection)
      collection.set(i, existingCollections)
    }
    fadedDecorationCollectionRef.current = collection
  }, [])

  const highlightEditedLines = useCallback((lineNumbers: number[]) => {
    if (!editorRef.current || !monacoRef.current) return null

    const model = editorRef.current.getModel()
    if (!model) return null
    const currentTheme = (editorRef.current as unknown as {_themeService: {_theme: {themeName: string}}})?._themeService
      ?._theme?.themeName
    const decorations = lineNumbers.map(lineNumber => ({
      range: new monacoRef.current!.Range(lineNumber, 1, lineNumber, 1),
      options: {
        isWholeLine: true,
        className: currentTheme === 'github-dark' ? styles.editHighlightDark : styles.editHighlightLight,
        marginClassName: currentTheme === 'github-dark' ? styles.editHighlightDark : styles.editHighlightLight,
      },
    }))

    const decorationCollection = editorRef.current.createDecorationsCollection(decorations)

    // Automatically remove the decorations after animation completes
    const timeoutId = window.setTimeout(() => {
      if (editorRef.current) {
        decorationCollection.clear()
      }
    }, LINE_BY_LINE_ANIMATION_DELAY)

    animationTimeoutsRef.current.push(timeoutId)

    return decorationCollection
  }, [])

  // Function to apply edits one by one with animation
  const applyEditSequentially = useCallback(
    (updatedValue: string, edits: EditorEdit[], cursor: number) => {
      if (!editorRef.current) return
      // No edits or finished all edits
      const [nextEdit, ...remainingEdits] = edits
      if (edits.length === 0 || !nextEdit) {
        preventTriggerChangeEvent.current = false

        // Iterate through all remaining decoration collections and clear them
        if (fadedDecorationCollectionRef.current) {
          for (const [_, decorationCollections] of fadedDecorationCollectionRef.current) {
            for (const collection of decorationCollections) {
              collection.clear()
            }
          }
          fadedDecorationCollectionRef.current.clear()
          fadedDecorationCollectionRef.current = null
        }
        setIsAnimating(false)

        return
      }

      const timeoutId = window.setTimeout(() => {
        if (!editorRef.current) return
        const groupedEdits: EditorEdit[] = [nextEdit]
        const affectedLines = new Set<number>()

        // Move the cursor line by line if there is no edit
        if (nextEdit.range.startLineNumber > cursor) {
          editorRef.current.revealRangeInCenter(new monacoRef.current!.Range(cursor, 1, cursor, 1))
          const decorationCollections = fadedDecorationCollectionRef.current?.get(cursor) || []
          for (const collection of decorationCollections) {
            collection.clear()
          }
          fadedDecorationCollectionRef.current?.delete(cursor)
          highlightEditedLines([cursor])
          affectedLines.add(cursor)
        } else {
          // Reveal the edited range to make it visible
          if (nextEdit.range) {
            editorRef.current.revealRangeInCenter(nextEdit.range)
          }

          // Get all affected line numbers for this nextEdit
          for (let aLine = nextEdit.range.startLineNumber; aLine <= nextEdit.range.endLineNumber; aLine++) {
            affectedLines.add(aLine)
          }

          if (nextEdit.operation === 'DELETION') {
            // Get the next edits that are on the same line
            for (const edit of remainingEdits) {
              if (!affectedLines.has(edit.range.startLineNumber)) break
              groupedEdits.push(edit)
            }
          }

          // Clear faded decorations
          for (const aLine of affectedLines) {
            const decorationCollections = fadedDecorationCollectionRef.current?.get(aLine) || []
            for (const collection of decorationCollections) {
              collection.clear()
            }
            fadedDecorationCollectionRef.current?.delete(aLine)
          }

          highlightEditedLines(Array.from(affectedLines))

          // Apply all edits in the current group
          executeEdits(editorRef.current, groupedEdits)
        }

        // Because we apply edit sequentially, we re-diff the editor and value to get the new range
        const remainingEditsToApply = getEditorEdits(getDiffLines(editorRef.current.getValue(), updatedValue))
        applyEditSequentially(updatedValue, remainingEditsToApply, cursor + Array.from(affectedLines).length)
      }, LINE_BY_LINE_ANIMATION_DELAY)

      animationTimeoutsRef.current.push(timeoutId)
    },
    [highlightEditedLines, setIsAnimating],
  )

  useEffect(() => {
    if (!isEditorReady || !editorRef.current || value === undefined) return
    if (value === editorRef.current.getValue()) {
      // Monaco caches content for its models, so show faded content even when value is the same
      if (isStaleContent) fadeContent()
      return
    }

    const model = editorRef.current.getModel()
    if (!model) return

    if (shouldDiffChanges) {
      const diffLines = getDiffLines(editorRef.current.getValue(), value)
      const editsToApply = getEditorEdits(diffLines)
      if (editsToApply.length === 0) return

      preventTriggerChangeEvent.current = true

      resetAnimations(animationTimeoutsRef.current)
      fadeContent()
      // Briefly display fade before beginning edits
      const timeoutId = window.setTimeout(() => {
        applyEditSequentially(value, editsToApply, 1)
      }, FADED_OUT_TO_EDITS_DELAY)
      animationTimeoutsRef.current.push(timeoutId)
      return
    }

    preventTriggerChangeEvent.current = true
    executeEdits(editorRef.current, [
      {
        range: model.getFullModelRange(),
        text: value,
        forceMoveMarkers: true,
      },
    ])
    tokenizeFile(model)
    if (isStaleContent) fadeContent()

    editorRef.current.pushUndoStop()
    preventTriggerChangeEvent.current = false
  }, [applyEditSequentially, fadeContent, isEditorReady, isStaleContent, resetAnimations, shouldDiffChanges, value])

  // Jump to line number
  useEffect(() => {
    if (!isEditorReady) return

    // reason for undefined check: https://github.com/suren-atoyan/monaco-react/pull/188
    if (line !== undefined) {
      editorRef.current?.revealLine(line)
    }
  }, [line, isEditorReady])

  // Change path
  useEffect(() => {
    if (!isEditorReady) return

    const model = getOrCreateModel(
      monacoRef.current!,
      defaultValue || value || '',
      defaultLanguage || language || '',
      path || defaultPath || '',
    )

    if (model !== editorRef.current?.getModel()) {
      if (saveViewState) viewStates.set(previousPath, editorRef.current?.saveViewState())
      editorRef.current?.setModel(model)
      if (saveViewState) editorRef.current?.restoreViewState(viewStates.get(path))
    }
  }, [defaultLanguage, defaultPath, defaultValue, isEditorReady, language, path, previousPath, saveViewState, value])

  // Change options
  useEffect(() => {
    if (!isEditorReady) return
    editorRef.current?.updateOptions(options)
  }, [isEditorReady, options])

  // Change language
  useEffect(() => {
    if (!isEditorReady) return
    const model = editorRef.current?.getModel()
    if (model && language) monacoRef.current?.editor.setModelLanguage(model, language)
  }, [isEditorReady, language])

  // Change theme
  useEffect(() => {
    if (!isEditorReady) return
    monacoRef.current?.editor.setTheme(theme)
  }, [isEditorReady, theme])

  // onMount
  useEffect(() => {
    if (!isEditorReady) return
    onMountRef.current(editorRef.current!, monacoRef.current!)
  }, [isEditorReady])

  // onChange
  useEffect(() => {
    if (isEditorReady && onChange) {
      subscriptionRef.current?.dispose()
      subscriptionRef.current = editorRef.current?.onDidChangeModelContent(event => {
        if (!preventTriggerChangeEvent.current) {
          onChange(editorRef.current!.getValue(), event)
        }
      })
    }
  }, [isEditorReady, onChange])

  // onValidate
  useEffect(() => {
    if (!isEditorReady) return () => {}

    const changeMarkersListener = monacoRef.current!.editor.onDidChangeMarkers(uris => {
      const editorUri = editorRef.current!.getModel()?.uri

      if (editorUri) {
        const currentEditorHasMarkerChanges = uris.find(uri => uri.path === editorUri.path)
        if (currentEditorHasMarkerChanges) {
          const markers = monacoRef.current!.editor.getModelMarkers({
            resource: editorUri,
          })
          onValidate?.(markers)
        }
      }
    })

    return () => {
      changeMarkersListener?.dispose()
    }
  }, [isEditorReady, onValidate])

  const createEditor = useCallback(() => {
    if (!containerRef.current || !monacoRef.current) return
    if (!preventCreation.current) {
      beforeMountRef.current(monacoRef.current)
      const autoCreatedModelPath = path || defaultPath
      const defaultModel = getOrCreateModel(
        monacoRef.current,
        value || defaultValue || '',
        defaultLanguage || language || '',
        autoCreatedModelPath || '',
      )

      editorRef.current = monacoRef.current?.editor.create(
        containerRef.current,
        {
          model: defaultModel,
          automaticLayout: true,
          ...options,
        },
        overrideServices,
      )

      if (saveViewState) {
        editorRef.current.restoreViewState(viewStates.get(autoCreatedModelPath))
      }

      monacoRef.current.editor.setTheme(theme)

      if (line !== undefined) {
        editorRef.current.revealLine(line)
      }

      const model = editorRef.current.getModel()
      if (model) tokenizeFile(model)

      setIsEditorReady(true)
      preventCreation.current = true
    }
  }, [
    path,
    defaultPath,
    value,
    defaultValue,
    defaultLanguage,
    language,
    options,
    overrideServices,
    saveViewState,
    theme,
    line,
  ])

  useEffect(() => {
    if (!isMonacoMounting && !isEditorReady) {
      createEditor()
    }
  }, [isMonacoMounting, isEditorReady, createEditor])

  return (
    <section className={styles.wrapper} style={{width, height}} data-testid="monaco-editor-section" {...wrapperProps}>
      {!isEditorReady && <div className={styles.loadingContainer}>{loading}</div>}
      <div
        ref={containerRef}
        className={clsx(className, styles.fullWidth, !isEditorReady && styles.hide)}
        data-testid="monaco-editor-container"
      />
    </section>
  )
}

// Custom executeEdits to workaround readOnly on the Editor and update the text buffer
function executeEdits(
  editor: editor.IStandaloneCodeEditor,
  edits: editor.IIdentifiedSingleEditOperation[],
  endCursorState?: editor.ICursorStateComputer | Selection[],
) {
  let cursorStateComputer
  if (!endCursorState) {
    cursorStateComputer = () => null
  } else if (Array.isArray(endCursorState)) {
    cursorStateComputer = () => endCursorState
  } else {
    cursorStateComputer = endCursorState
  }
  editor.getModel()?.pushEditOperations(editor.getSelections(), edits, cursorStateComputer)
}

// Force tokenization to get colors first before making file viewable, reducing flicker of colors
type TokenizationTextModelPart = {forceTokenization: (lineNumber: number) => void}
function tokenizeFile(model: editor.ITextModel) {
  if (!model) return
  const lineCount = model.getLineCount()
  for (let i = 1; i <= lineCount; i++) {
    ;(model as unknown as {tokenization: TokenizationTextModelPart}).tokenization.forceTokenization(i)
  }
}
