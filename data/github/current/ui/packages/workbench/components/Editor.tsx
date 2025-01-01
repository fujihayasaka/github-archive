import {getLanguage, LspServerType, type RemoteProvider} from '@github/codespaces-lsp'
import {debounce} from '@github/mini-throttle'
import type {CopilotChatRepo} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {copyText} from '@github-ui/copy-to-clipboard'
import {useAppPayload} from '@github-ui/react-core/use-app-payload'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {useMonacoEditor} from '@github-ui/shared-workspace-components/useMonacoEditor'
import {useLayoutEffect} from '@github-ui/use-layout-effect'
import {EscapeEditorHint, escapeEditorHintAltText} from '@github-ui/workspace-editor/components/EscapeEditorHint'
import {MarkdownIndicator} from '@github-ui/workspace-editor/components/MarkdownIndicator'
import {useObjectWrapper} from '@github-ui/workspace-editor/hooks/use-object-wrapper'
import {enableLanguageFeatures} from '@github-ui/workspace-editor/lsp/monaco-lsp-connector'
import {useLsps} from '@github-ui/workspace-editor/lsp/use-lsps'
import {isMarkdown} from '@github-ui/workspace-editor/utilities/file-path-helpers'
import {configureMonaco} from '@github-ui/workspace-editor/utilities/monaco'
import {useUserPreference} from '@github-ui/workspace-editor/utilities/preferences'
import {initialPathQueryParam} from '@github-ui/workspace-editor/utilities/query-params'
import type {
  ConnectedCodespaceData,
  WorkspaceEditorAppPayload,
} from '@github-ui/workspace-editor/utilities/workspace-editor-types'
import type {Monaco} from '@monaco-editor/react'
import {useResizeObserver, useTheme} from '@primer/react'
import {clsx} from 'clsx'
import type {editor as editorTypes} from 'monaco-editor'
import {type PropsWithChildren, useCallback, useEffect, useMemo, useRef, useState} from 'react'
import {useSearchParams} from 'react-router-dom'
import {parseRawGrammar, Registry} from 'vscode-textmate'

import {useEditorContext} from '../contexts/EditorContext'
import {useErrors} from '../contexts/ErrorsContext'
import {useFileSyncerContext} from '../contexts/FileSyncerContext'
import {useTargetedEditsContext} from '../contexts/TargetedEditsContext'
import {useWorkbenchContext} from '../contexts/WorkbenchContext'
import {useSaveUserEdit} from '../hooks/use-after-user-edit'
import {useOnigurumaWasm} from '../hooks/use-oniguruma-wasm'
import TypeScriptReactTMLanguage from '../monaco/grammars/TypeScriptReact.tmLanguage.json'
import {wireTmGrammars} from '../monaco/wire-tm-grammers'
import {useAnalytics} from '../telemetry/use-analytics'
import type {WorkbenchRoutePayload} from '../types/workbench-types'
import {USER_EDIT_COMMIT_MESSAGE} from '../utilities/commit-messages'
import {createCancelableFunction} from '../utilities/create-cancellable-function'
import type {SparkError} from '../utilities/error'
import styles from './Editor.module.css'
import {EditorHeader, type EditorHeaderProps} from './EditorHeader/EditorHeader'
import {EditorHeaderSettings} from './EditorHeader/EditorHeaderSettings'
import {EditorLoadingSkeleton} from './EditorLoadingSkeleton'
import {MonacoEditor, type MonacoEditorProps} from './MonacoEditor'
import {SimpleFileTree} from './SimpleFileTree'

// Track min editor width to auto-collapse tree
const MIN_USEFUL_EDITOR_WIDTH = 480

function isImage(filename: string): boolean {
  const imageExtensions = ['.png', '.jpg', '.jpeg', '.gif', '.svg', '.webp']
  return imageExtensions.some(ext => filename.toLowerCase().endsWith(ext))
}

function enableLanguageFeaturesForEditorModel(
  editor: editorTypes.ICodeEditor,
  filePath: string,
  initialFileContent: string,
) {
  const newModel = editor.getModel()
  if (newModel) {
    enableLanguageFeatures(newModel, filePath, initialFileContent)
  }
}

function PlainTextStatus({children}: PropsWithChildren) {
  return <div className="d-flex flex-justify-center m-3 fgColor-muted height-full">{children}</div>
}

export type EditorProps = {
  copilotAccessAllowed?: boolean
  copilotCurrentTopic?: CopilotChatRepo
  codespaceData: ConnectedCodespaceData
  remoteProvider?: RemoteProvider
} & Pick<EditorHeaderProps, 'onTerminalClick'>

export function Editor({
  copilotAccessAllowed,
  copilotCurrentTopic,
  codespaceData,
  remoteProvider,
  ...editorHeaderProps
}: EditorProps) {
  const {beforeMount} = useMonacoEditor(true)
  const {markdownDocsUrl, monacoWorkerUrls} = useAppPayload<WorkspaceEditorAppPayload>()
  configureMonaco(monacoWorkerUrls)
  const {blobContents, large, isBinary, path, editorSettings, isNewFilePage, workbench} =
    useRoutePayload<WorkbenchRoutePayload>()
  const {selectedElement} = useTargetedEditsContext()
  const {refreshEditor, setPreviousPath, watchingPath, setWatchingPath, isNavigating, setRefreshEditor} =
    useEditorContext()
  const {resolvedColorScheme} = useTheme()
  const {isFetching} = useWorkbenchContext()
  const {setEditorErrors, setEditorWarnings} = useErrors()
  const {data: vscodeOnigurumaLib, isLoading: isLoadingOnigurumaWasm, isError} = useOnigurumaWasm()
  const {
    contentStateStamp,
    fileSyncerStarted,
    getFileSyncerV2,
    notifyEdited,
    syncerMode,
    fileContentsRef,
    forceContentRefresh,
    setFilesContentsRef,
  } = useFileSyncerContext()

  const [pathError, setPathError] = useState(false)
  const [isFileTreeExpanded, setIsFileTreeExpanded] = useState(false)
  const [initialBrowserWidth, setInitialBrowserWidth] = useState<number | null>(null)
  const [value, setValue] = useState<string | undefined>()
  const [isStaleContent, setIsStaleContent] = useState(false)
  const [shouldDiffChanges, setShouldDiffChanges] = useState(false)

  const editorRef = useRef<editorTypes.IStandaloneCodeEditor | null>(null)
  const editorPanelRef = useRef<HTMLDivElement | null>(null)
  const filenameInputRef = useRef<HTMLInputElement>(null)
  const moreOptionsButtonRef = useRef<HTMLButtonElement>(null)
  const previousContentStateStampRef = useRef<number | null>(null)
  const lastLspErrorTimestampRef = useRef<number>(0)
  const showingOriginalContentRef = useRef<boolean>(false)
  // use refs to ensure monaco editor callbacks that are subscribed in `onMount` always have the latest data
  const currentPath = useObjectWrapper(path)
  const currentBlobContents = useObjectWrapper(blobContents ?? '')
  const isMarkdownFile = isMarkdown(path)
  const isImageFile = isImage(path)

  const isDarkTheme = resolvedColorScheme && resolvedColorScheme.includes('dark')
  const theme = isDarkTheme ? 'github-dark' : 'github-light'

  const preferenceToString = useCallback((pref: boolean) => (pref ? 'true' : 'false'), [])
  const [isEditorNarrow, setEditorNarrow] = useState(false)

  useResizeObserver(
    () => {
      const isNarrow = (editorPanelRef.current && editorPanelRef.current.offsetWidth < MIN_USEFUL_EDITOR_WIDTH) ?? false
      if (isNarrow !== isEditorNarrow) setEditorNarrow(isNarrow)
    },
    editorPanelRef,
    [],
  )

  let language = getLanguage(path)
  // Fallback to typescript if wasm does not load or is unsupported
  if (isError && language === 'typescriptreact') {
    language = 'typescript'
  }

  // const {initialTaskId, initialTaskSource} = useFocusedTask()
  const [searchParams] = useSearchParams()

  const handlePathChange = useCallback(() => {
    setPathError(false)
  }, [])

  const initialPath = searchParams.get(initialPathQueryParam) || path || ''

  const checkAndCollapseFileTree = () => {
    if (isEditorNarrow && isFileTreeExpanded) {
      setIsFileTreeExpanded(false)
    }
  }

  useLayoutEffect(() => {
    setInitialBrowserWidth(document.body.offsetWidth || 0)
  }, [])

  useResizeObserver(() => {
    const currentBrowserWidth = document.body.offsetWidth
    if (initialBrowserWidth !== null && currentBrowserWidth < initialBrowserWidth) {
      checkAndCollapseFileTree()
    }
    setInitialBrowserWidth(currentBrowserWidth)
  }, editorPanelRef)

  const {preference: codeLineWrapEnabled, updatePreference: setCodeLineWrapEnabled} = useUserPreference(
    'code_line_wrap_enabled',
    editorSettings.codeLineWrapEnabled,
    preferenceToString,
    true,
  )

  // TODO: update styling???
  const {preference: whitespaceHidden, updatePreference: setWhitespaceHidden} = useUserPreference(
    'workbench_whitespace_hidden',
    editorSettings.whitespaceHidden,
    preferenceToString,
  )

  const {preference: problemsHidden, updatePreference: setProblemsHidden} = useUserPreference(
    'workbench_problems_hidden',
    editorSettings.problemsHidden,
    preferenceToString,
  )

  const options: MonacoEditorProps['options'] = useMemo(
    () => ({
      ariaLabel: `Content Editor. ${escapeEditorHintAltText}`,
      minimap: {enabled: false},
      readOnly: syncerMode === 'blobStorage' || !!isFetching,
      fixedOverflowWidgets: true,
      padding: {top: 8},
      wordWrap: codeLineWrapEnabled ? 'on' : 'off',
      'semanticHighlighting.enabled': false,
      stickyScroll: {enabled: false},
      isStaleContent,
      shouldDiffChanges,
    }),
    [codeLineWrapEnabled, isFetching, isStaleContent, shouldDiffChanges, syncerMode],
  )

  const fetchFileContent = useCallback(
    async (filePath: string): Promise<string | null> => {
      const fileSyncer = getFileSyncerV2()
      if (!fileSyncer) return null

      try {
        // Check if it's an image file, read as bytes for images
        if (isImage(filePath)) {
          const bytes = await fileSyncer.readFileBytes(filePath)
          let byteArray: Uint8Array
          if (bytes instanceof Uint8Array) {
            byteArray = bytes
          } else if (Array.isArray(bytes)) {
            byteArray = new Uint8Array(bytes)
          } else if (typeof bytes === 'object' && bytes !== null) {
            // Handle plain object with numeric keys
            const length = Math.max(...Object.keys(bytes).map(Number)) + 1
            const array = new Array(length)
            for (let i = 0; i < length; i++) {
              array[i] = bytes[i] || 0
            }
            byteArray = new Uint8Array(array)
          } else {
            throw new Error('Unexpected bytes format')
          }

          // Convert to base64
          let base64: string
          if (typeof Buffer !== 'undefined') {
            base64 = Buffer.from(byteArray).toString('base64')
          } else {
            // Browser environment - use btoa with chunking for large files
            const CHUNK_SIZE = 0x8000 // 32KB chunks
            const chunks: string[] = []

            for (let i = 0; i < byteArray.length; i += CHUNK_SIZE) {
              const chunk = byteArray.slice(i, i + CHUNK_SIZE)
              chunks.push(String.fromCharCode.apply(null, Array.from(chunk)))
            }

            base64 = btoa(chunks.join(''))
          }

          const extension = filePath.split('.').pop()?.toLowerCase()
          const mimeType =
            {
              png: 'image/png',
              jpg: 'image/jpeg',
              jpeg: 'image/jpeg',
              gif: 'image/gif',
              svg: 'image/svg+xml',
              webp: 'image/webp',
            }[extension!] || 'image/png'
          const dataUrl = `data:${mimeType};base64,${base64}`
          return dataUrl
        }

        // Read as string for non-image files
        return await fileSyncer.readFileString(filePath)
      } catch (e) {
        // eslint-disable-next-line no-console
        console.error('Editor:: Error reading file:', e)
        return null
      }
    },
    [getFileSyncerV2],
  )

  const loadContent = useCallback(async () => {
    const fileState = fileContentsRef.current?.[path]
    setShouldDiffChanges(false) // Reset diffing

    if (isFetching && fileState?.content && watchingPath === path && !showingOriginalContentRef.current) {
      // Only show original content on initial load when the path is changed
      setValue(fileState.content)
      showingOriginalContentRef.current = true
      setIsStaleContent(true)
      setWatchingPath(null)
      forceContentRefresh()
    } else {
      const content = await fetchFileContent(path)
      // Path changed during fetch, ignoring results
      if (path !== currentPath.current) return
      if (content !== null) {
        setValue(content)
      } else {
        setValue(undefined)
      }
      if (showingOriginalContentRef.current) {
        setShouldDiffChanges(true)
        showingOriginalContentRef.current = false
        if (content && fileState) {
          setFilesContentsRef({
            ...fileContentsRef.current,
            [path]: {
              ...fileState,
              content,
            },
          })
        }
      }
      setIsStaleContent(false)
    }

    // Always reset loading states
    setRefreshEditor(false)
  }, [
    currentPath,
    fetchFileContent,
    fileContentsRef,
    forceContentRefresh,
    isFetching,
    path,
    setFilesContentsRef,
    setRefreshEditor,
    setWatchingPath,
    watchingPath,
  ])

  // Used to refresh content when path or external content changes
  useEffect(() => {
    if (fileSyncerStarted && (isNavigating || previousContentStateStampRef.current !== contentStateStamp)) {
      loadContent()

      // Set previous path and content state stamp to current
      setPreviousPath(path)
      previousContentStateStampRef.current = contentStateStamp
    }
  }, [loadContent, contentStateStamp, path, fileSyncerStarted, setPreviousPath, isNavigating])

  const cancellableFileSync = useMemo(
    () =>
      createCancelableFunction(async (content: string, delayMs: number, signal: AbortSignal) => {
        const fileSyncer = getFileSyncerV2()
        if (!fileSyncer) {
          return
        }

        if (signal.aborted) {
          // Noop, syncing aborted
          return
        }

        await new Promise(resolve => {
          setTimeout(() => {
            resolve(true)
          }, delayMs ?? 0)
        })

        if (signal.aborted) {
          // Noop, syncing aborted
          return
        }

        await fileSyncer.writeFileString(currentPath.current, content ?? '')
        notifyEdited()
      }),
    [currentPath, getFileSyncerV2, notifyEdited],
  )

  const writeFileDebounced = useMemo(
    () =>
      // Create a debounced version of the writeFile function for future calls

      debounce(async (newValue: string) => {
        const timeSinceLastLspError = Date.now() - lastLspErrorTimestampRef.current

        // Debounce the file write if time since last lsp error is less than 5 seconds
        if (timeSinceLastLspError < 5000) {
          await cancellableFileSync(newValue, 5001)
          return
        }

        await cancellableFileSync(newValue, 0)
        setValue(newValue)
      }, 500),
    [cancellableFileSync],
  )

  const saveUserEdit = useSaveUserEdit()

  const onChange = useCallback(
    async (newValue: string | undefined) => {
      if (isFetching) {
        // While code is being generated, they are directly syned to the file system
        // So we don't want redundant writes
        return
      }

      writeFileDebounced(newValue ?? '')
      saveUserEdit(USER_EDIT_COMMIT_MESSAGE, currentPath.current)
    },
    [isFetching, writeFileDebounced, saveUserEdit, currentPath],
  )

  const sendEvent = useAnalytics()

  const {registerMonaco} = useLsps(codespaceData, sendEvent, remoteProvider, [LspServerType.Typescript])

  const registerLanguageFeatures = useCallback(
    (editor: editorTypes.IStandaloneCodeEditor) => {
      if (currentPath.current) {
        enableLanguageFeaturesForEditorModel(editor, currentPath.current, currentBlobContents.current)
      }
    },
    [currentPath, currentBlobContents],
  )

  const onMonacoMount = useCallback(
    async (editor: editorTypes.IStandaloneCodeEditor, monaco: Monaco) => {
      // Workaround since monaco does not support JSX syntax highlighting
      if (vscodeOnigurumaLib) {
        // Create a registry that can create a grammar from a scope name.
        const registry = new Registry({
          onigLib: Promise.resolve(vscodeOnigurumaLib),
          loadGrammar: async scopeName => {
            // From https://github.com/microsoft/TypeScript-TmLanguage/blob/master/TypeScriptReact.tmLanguage
            // or from https://github.com/microsoft/vscode-textmate/blob/main/test-cases/themes/syntaxes/TypeScriptReact.tmLanguage.json
            if (scopeName === 'source.tsx') {
              return parseRawGrammar(JSON.stringify(TypeScriptReactTMLanguage), 'TypeScriptReact.tmLanguage.json')
            }
            // Unknown scope name
            return null
          },
        })

        // Map of monaco "language id's" to TextMate scopeNames
        const grammars = new Map()
        grammars.set('typescriptreact', 'source.tsx')
        monaco.languages.register({id: 'typescriptreact'})
        await wireTmGrammars(monaco, registry, grammars, editor)
      }
      editorRef.current = editor

      registerMonaco(monaco)

      editor.onDidChangeModel(() => {
        registerLanguageFeatures(editor)
      })

      registerLanguageFeatures(editor)

      monaco.editor.onDidChangeMarkers(uris => {
        let hasErrors = false
        for (const uri of uris) {
          if (uri.scheme === 'file') {
            const markers = monaco.editor.getModelMarkers({resource: uri})
            const errorMarkers: SparkError[] = []
            const warningMarkers: SparkError[] = []

            for (const m of markers) {
              const common = {
                source: 'editor' as const,
                messageRaw: m.message,
                messagePretty: m.message,
                path: m.resource?.path,
                line: m.startLineNumber,
                column: m.startColumn,
              }
              if (m.severity >= monaco.MarkerSeverity.Error) {
                errorMarkers.push({...common})
              }
            }

            setEditorErrors(uri.path, errorMarkers)
            setEditorWarnings(warningMarkers)
            if (errorMarkers.length !== 0) {
              hasErrors = true
            }
          }
        }

        if (hasErrors) {
          if (lastLspErrorTimestampRef.current === 0) {
            lastLspErrorTimestampRef.current = Date.now()
          }
        } else {
          lastLspErrorTimestampRef.current = 0
        }
      })
    },
    [registerLanguageFeatures, registerMonaco, setEditorErrors, setEditorWarnings, vscodeOnigurumaLib],
  )

  /**
   * Highlight the selected code when user in targeted edits mode
   */
  useEffect(() => {
    if (!editorRef.current || !selectedElement) return

    const {start, end} = selectedElement.location ?? selectedElement.component.location!

    editorRef.current.setSelection({
      selectionStartColumn: start.column,
      selectionStartLineNumber: start.line,
      positionColumn: end.column,
      positionLineNumber: end.line,
    })

    // Scroll to the selection
    editorRef.current.revealLineInCenter(start.line)
  }, [selectedElement])

  const editorHeader = (
    <EditorHeader
      key={`header-${path}`}
      filenameInputRef={filenameInputRef}
      moreOptionsButtonRef={moreOptionsButtonRef}
      isFileTreeExpanded={isFileTreeExpanded}
      setIsFileTreeExpanded={setIsFileTreeExpanded}
      settings={
        <EditorHeaderSettings
          onCopyFileContents={useCallback(async () => await copyText(value || ''), [value])}
          codeLineWrapEnabled={!!codeLineWrapEnabled}
          whitespaceHidden={!!whitespaceHidden}
          problemsHidden={!!problemsHidden}
          setCodeLineWrapEnabled={setCodeLineWrapEnabled}
          setWhitespaceHidden={setWhitespaceHidden}
          setProblemsHidden={setProblemsHidden}
        />
      }
      initialPath={initialPath}
      path={path}
      pathError={pathError}
      onPathChange={handlePathChange}
      {...editorHeaderProps}
    />
  )

  // If the file is new, we don't show the editor since it complicates monaco model management,
  // and LSP features won't work.
  // Instead, we just show the header and let the user save the file then begin composing.
  if (isNewFilePage) return editorHeader

  const isLoadingEditor = (syncerMode === 'codespace' && !fileSyncerStarted) || isLoadingOnigurumaWasm
  const isLoadingFile = refreshEditor || isNavigating
  return (
    <>
      <div
        className={clsx(styles.editorContainer, {[styles.editorContainerNarrow]: isEditorNarrow})}
        ref={editorPanelRef}
      >
        <div
          className={styles.files}
          style={{
            transform: isFileTreeExpanded ? 'translateX(0)' : 'translateX(-100%)',
            width: isFileTreeExpanded ? '15rem' : '0',
            overflow: 'hidden',
            transition: 'transform 0.2s cubic-bezier(0.4, 0, 0.2, 1), width 0.2s cubic-bezier(0.4, 0, 0.2, 1)',
          }}
        >
          <div className="flex-1 py-2 px-3 overflow-y-auto">
            <SimpleFileTree workbenchId={workbench.id} isFetching={isFetching} />
          </div>
        </div>
        {!(isFileTreeExpanded && isEditorNarrow) && (
          <div className={clsx(styles.editorFileFrame, {[styles.fileTreeExpanded]: isFileTreeExpanded})}>
            {editorHeader}
            {isLoadingFile && <EditorLoadingSkeleton fadeIn />}
            <div className={clsx(styles.editorFileContainer, isLoadingFile && styles.hideEditorFile)}>
              {large ? (
                <PlainTextStatus>
                  <p>Sorry about that, but we cannot show files that are this big right now.</p>
                </PlainTextStatus>
              ) : isBinary ? (
                <PlainTextStatus>Binary file not shown.</PlainTextStatus>
              ) : isLoadingEditor ? (
                <EditorLoadingSkeleton fadeIn={isLoadingFile} />
              ) : isImageFile ? (
                <div className={styles.imgContainer}>
                  <img src={value} alt="Uploaded Asset Preview" className={styles.img} />
                </div>
              ) : (
                <MonacoEditor
                  className={problemsHidden ? styles.hideProblems : undefined}
                  height="100%"
                  onChange={onChange}
                  path={path}
                  beforeMount={beforeMount}
                  defaultLanguage={language || 'javascript'}
                  language={language}
                  loading={<EditorLoadingSkeleton />}
                  onMount={onMonacoMount}
                  options={options}
                  theme={theme}
                  value={value}
                />
              )}
            </div>
          </div>
        )}
      </div>
      <EscapeEditorHint />
      {isMarkdownFile && <MarkdownIndicator markdownDocsUrl={markdownDocsUrl} />}
    </>
  )
}
