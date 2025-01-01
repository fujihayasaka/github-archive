import {getLanguage, type IFileSyncerClient, type RemoteProvider} from '@github/codespaces-lsp'
import {useCurrentRepository} from '@github-ui/current-repository'
import {useMonacoEditor} from '@github-ui/monaco-editor/hooks/useMonacoEditor'
import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {useNavigate} from '@github-ui/use-navigate'
import {
  DiffEditor,
  type DiffEditorProps,
  Editor as MonacoEditor,
  type EditorProps as MonacoEditorProps,
  type Monaco,
} from '@monaco-editor/react'
import {useTheme} from '@primer/react'
import type {editor as editorTypes} from 'monaco-editor'
import {type PropsWithChildren, useCallback, useState} from 'react'

import {useCurrentPullRequest} from '../contexts/CurrentPullRequestProvider'
import {useFilesContext} from '../contexts/FilesContext'
import {useWorkspaceEditorUIState} from '../contexts/WorkspaceEditorUIContext'
import {useFocusedCommentDecorations} from '../hooks/use-focused-comment-decorations'
import {useFocusedTask} from '../hooks/use-focused-task'
import {useObjectWrapper} from '../hooks/use-object-wrapper'
import {enableLanguageFeatures, ORIGINAL_CONTENTS_URI_PREFIX} from '../lsp/monaco-lsp-connector'
import {useLsps} from '../lsp/use-lsps'
import {AnalyticsContext} from '../telemetry/AnalyticsContext'
import {UNKNOWN_VALUE, UNSET_VALUE} from '../telemetry/constants'
import {useAnalytics} from '../telemetry/use-analytics'
import {isDeleted} from '../utilities/file-status-helpers'
import {useUserPreference} from '../utilities/preferences'
import {initialPathQueryParam, removeQueryParam} from '../utilities/query-params'
import {validFilename} from '../utilities/tree-helpers'
import {fileUrl} from '../utilities/urls'
import {uuid} from '../utilities/uuid'
import type {ConnectedCodespaceData, WorkspaceEditorRoutePayload} from '../utilities/workspace-editor-types'
import {ConflictDialog} from './ConflictDialog'
import {EditorHeader, type EditorHeaderProps} from './editor-header/EditorHeader'
import {EscapeEditorHint, escapeEditorHintAltText} from './EscapeEditorHint'
import {EditorMode, MarkdownEditor} from './MarkdownEditor'

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
  return <div className="d-flex flex-justify-center m-3 fgColor-muted">{children}</div>
}

// Editor session ID.
const EDITOR_SESSION_ID = uuid()

type EditorProps = {
  codespaceData: ConnectedCodespaceData
  remoteProvider?: RemoteProvider
  getFileSyncerClient: () => IFileSyncerClient | null
} & Pick<
  EditorHeaderProps,
  'isTreeExpanded' | 'onTerminalClick' | 'onDetailsClick' | 'treeToggleElement' | 'terminalHeaderButtonRef'
>

export function Editor({codespaceData, getFileSyncerClient, remoteProvider, ...editorHeaderProps}: EditorProps) {
  const {beforeMount} = useMonacoEditor()
  const {ownerLogin, name} = useCurrentRepository()
  const {addFile, deleteFile, editFile, getCurrentFileContent, getFileStatuses, renameFile} = useFilesContext()
  const {
    blobContents,
    isBinary,
    compareRef,
    compareBlobContents,
    diffPaths,
    fileStatuses: pullFileStatuses,
    path,
    editorSettings,
    fileTree,
    isNewFilePage,
  } = useRoutePayload<WorkspaceEditorRoutePayload>()
  const {pullRequest} = useCurrentPullRequest()

  const [pathError, setPathError] = useState(false)
  const [editorMode, setEditorMode] = useState(EditorMode.Edit)
  const preferenceToString = useCallback((value: boolean) => (value ? 'true' : 'false'), [])
  const {preference: codeLineWrapEnabled, updatePreference: setCodeLineWrapEnabled} = useUserPreference(
    'code_line_wrap_enabled',
    editorSettings.codeLineWrapEnabled,
    preferenceToString,
  )
  const {preference: whitespaceHidden, updatePreference: setWhitespaceHidden} = useUserPreference(
    'hadron_whitespace_hidden',
    editorSettings.whitespaceHidden,
    preferenceToString,
  )

  const localFileStatuses = getFileStatuses()
  const validatingFileNames = useFeatureFlag('validate_filename_on_editor_rename')

  const calculateIsDeleted = () =>
    path in localFileStatuses ? isDeleted(localFileStatuses[path]) : isDeleted(pullFileStatuses?.[path])

  // use refs to ensure monaco editor callbacks that are subscribed in `onMount` always have the latest data
  const isFileDeleted = useObjectWrapper(calculateIsDeleted())
  const currentPath = useObjectWrapper(path)
  const currentBlobContents = useObjectWrapper(blobContents ?? '')

  const {diffStyle, showDiff} = useWorkspaceEditorUIState()
  const showDeleted = isFileDeleted.current && !(showDiff && compareBlobContents)
  const {resolvedColorMode} = useTheme()

  const theme = resolvedColorMode === 'night' ? 'github-dark' : 'github-light'

  const navigate = useNavigate()

  const options: MonacoEditorProps['options'] = {
    ariaLabel: `Content Editor. ${escapeEditorHintAltText}`,
    minimap: {enabled: false},
    readOnly: isFileDeleted.current,
    fixedOverflowWidgets: true,
    padding: {top: 8},
    wordWrap: codeLineWrapEnabled ? 'on' : 'off',
  }
  const diffOptions: DiffEditorProps['options'] = {
    ariaLabel: `Diff Editor. ${escapeEditorHintAltText}`,
    modifiedAriaLabel: 'Modified Content Editor',
    originalAriaLabel: 'Original Content Editor',
    readOnly: isFileDeleted.current,
    renderSideBySide: diffStyle === 'split',
    renderGutterMenu: false, // setting false to prevent AbstractContextKeyService error. see https://github.com/microsoft/monaco-editor/issues/4581
    fixedOverflowWidgets: true,
    padding: {top: 8},
    useInlineViewWhenSpaceIsLimited: false,
    wordWrap: codeLineWrapEnabled ? 'on' : 'off',
    ignoreTrimWhitespace: !!whitespaceHidden,
  }

  const {content: value, patchIncluded, patch} = getCurrentFileContent(path, blobContents)

  const closeConflictDialog = () => {
    // remove conflict from local storage
    editFile({
      filePath: currentPath.current,
      originalContent: currentBlobContents.current,
      newFileContent: currentBlobContents.current,
    })
  }

  const sendEvent = useAnalytics()

  const onChange = useCallback(
    (newValue: string | undefined) => {
      if (isFileDeleted.current) {
        return
      }

      editFile({filePath: currentPath.current, originalContent: currentBlobContents.current, newFileContent: newValue})

      sendEvent('editor.file-edit', {
        file_extension: UNKNOWN_VALUE,
      })
    },
    // the `sendEvent()` function always changes so we don't want to include it into the dependencies list
    // eslint-disable-next-line react-compiler/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [editFile],
  )

  const toggleCodeLineWrapEnabled = useCallback(async () => {
    setCodeLineWrapEnabled(!codeLineWrapEnabled)
  }, [codeLineWrapEnabled, setCodeLineWrapEnabled])

  const toggleWhitespaceHidden = useCallback(async () => {
    setWhitespaceHidden(!whitespaceHidden)
  }, [setWhitespaceHidden, whitespaceHidden])

  const {registerMonaco} = useLsps(codespaceData, getFileSyncerClient, remoteProvider)
  const {registerCommentDecorations} = useFocusedCommentDecorations()

  const registerLanguageFeatures = (editor: editorTypes.IStandaloneCodeEditor) => {
    if (currentPath.current) {
      enableLanguageFeaturesForEditorModel(editor, currentPath.current, currentBlobContents.current)
    }
  }

  const onMonacoMount = (editor: editorTypes.IStandaloneCodeEditor, monaco: Monaco) => {
    registerMonaco(monaco)

    editor.onDidChangeModel(() => {
      registerLanguageFeatures(editor)
    })

    registerLanguageFeatures(editor)
    registerCommentDecorations({editor})
  }

  const onMonacoDiffMount = (diffEditor: editorTypes.IStandaloneDiffEditor, monaco: Monaco) => {
    const modifiedEditor = diffEditor.getModifiedEditor()

    // Handle changes to the modified editor
    modifiedEditor.onDidChangeModelContent(() => {
      onChange?.(modifiedEditor.getValue())
    })

    // Workaround for bug with `DiffEditor` component and setting original/modified paths.
    // Without this, the visual diff shown by the editor doesn't update correctly when switching between files.
    // This forces the editor to update the diff view whenever the model changes.
    modifiedEditor.onDidChangeModel(() => {
      const modifiedModel = diffEditor.getModifiedEditor().getModel()
      const originalModel = diffEditor.getOriginalEditor().getModel()
      if (!modifiedModel || !originalModel) return

      diffEditor.setModel({
        original: originalModel,
        modified: modifiedModel,
      })
    })

    onMonacoMount(modifiedEditor, monaco)
  }

  let language = getLanguage(path)
  if (language === 'typescriptreact') {
    language = 'typescript'
  }

  const {initialTaskId, initialTaskSource} = useFocusedTask()

  const isMarkdownFile = isMarkdown(path)

  const handlePathChange = () => {
    setPathError(false)
  }

  const editorHeader = (
    <EditorHeader
      key={`header-${path}`}
      isDeleted={isFileDeleted.current}
      path={path}
      pathError={pathError}
      isPreviewable={isMarkdownFile}
      editorMode={editorMode}
      updateEditorMode={(idx: number) => setEditorMode(idx)}
      onDelete={() => {
        deleteFile(path, blobContents)
        getFileSyncerClient()?.deleteFile(path)
      }}
      onPathChange={handlePathChange}
      onSaveFileName={newFileName => {
        if (validatingFileNames && !validFilename({...diffPaths, ...fileTree}, newFileName)) {
          setPathError(true)
          return
        }
        setPathError(false)

        if (isNewFilePage) {
          addFile(newFileName)
          removeQueryParam(initialPathQueryParam)
        } else {
          renameFile({newFilePath: newFileName, oldFilePath: path, originalContent: blobContents})
        }

        navigate(
          fileUrl({
            path: newFileName,
            owner: ownerLogin,
            repo: name,
            pullNumber: pullRequest.number,
            location: window.location,
          }),
        )
      }}
      codeLineWrapEnabled={codeLineWrapEnabled}
      toggleCodeLineWrapEnabled={toggleCodeLineWrapEnabled}
      toggleWhitespaceHidden={toggleWhitespaceHidden}
      whitespaceHidden={whitespaceHidden}
      codespaceData={codespaceData}
      {...editorHeaderProps}
    />
  )

  // Create telemetry context metadata.
  const metadata = useCallback(() => {
    return {
      session_id: EDITOR_SESSION_ID,
      version: UNKNOWN_VALUE,
    }
  }, [])

  // If the file is new, we don't show the editor since it complicates monaco model management,
  // and LSP features won't work.
  // Instead, we just show the header and let the user save the file then begin composing.
  if (isNewFilePage) return editorHeader

  return (
    <AnalyticsContext
      name="editor"
      metadata={metadata}
      onStart={sendTelemetryEvent => {
        sendTelemetryEvent('editor.start', {
          entry_point_id: initialTaskId ?? UNSET_VALUE,
          entry_point_type: initialTaskSource ?? UNSET_VALUE,
        })
      }}
    >
      {editorHeader}

      <ConflictDialog patchIncluded={patchIncluded} patch={patch} closeConflictDialog={closeConflictDialog} />
      {showDeleted ? (
        <PlainTextStatus>This file was deleted.</PlainTextStatus>
      ) : isMarkdownFile ? (
        <MarkdownEditor
          editorMode={editorMode}
          height="100%"
          showDiff={showDiff}
          saveChanges={onChange}
          editorSettings={{
            language,
            beforeMount,
            defaultLanguage: language || 'javascript',
            value,
            options,
            onMount: onMonacoMount,
            theme,
          }}
          diffEditorSettings={{
            original: compareRef ? compareBlobContents || '' : blobContents,
            modified: isFileDeleted.current ? '' : value,
            language: language || 'javascript',
            options: diffOptions,
            theme,
            beforeMount,
            onMount: onMonacoDiffMount,
          }}
        />
      ) : isBinary ? (
        <PlainTextStatus>Binary file not shown.</PlainTextStatus>
      ) : showDiff ? (
        <DiffEditor
          beforeMount={beforeMount}
          height="100%"
          original={compareRef ? compareBlobContents || '' : blobContents}
          modified={isFileDeleted.current ? '' : value}
          originalModelPath={`${ORIGINAL_CONTENTS_URI_PREFIX}-${path}`}
          modifiedModelPath={path}
          language={language || 'javascript'}
          theme={theme}
          options={diffOptions}
          onMount={onMonacoDiffMount}
        />
      ) : (
        <MonacoEditor
          beforeMount={beforeMount}
          height="100%"
          defaultLanguage={language || 'javascript'}
          value={value}
          language={language}
          path={path}
          theme={theme}
          options={options}
          onChange={onChange}
          onMount={(editor, monaco) => {
            onMonacoMount(editor, monaco)
          }}
        />
      )}
      <EscapeEditorHint />
    </AnalyticsContext>
  )
}

function isMarkdown(filename: string): boolean {
  const mdExtensions = ['.md', '.mkdn', '.mkd', '.mdown', '.markdown']
  return mdExtensions.some(ext => filename.endsWith(ext))
}
