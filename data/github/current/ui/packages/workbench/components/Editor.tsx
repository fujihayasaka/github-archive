import {getLanguage, type RemoteProvider} from '@github/codespaces-lsp'
import type {CopilotChatRepo} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {copyText} from '@github-ui/copy-to-clipboard'
import {useCurrentRepository} from '@github-ui/current-repository'
import {blobPath} from '@github-ui/paths'
import {useAppPayload} from '@github-ui/react-core/use-app-payload'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {EditorHeader, type EditorHeaderProps} from '@github-ui/shared-workspace-components/EditorHeader'
import {EditorHeaderActions} from '@github-ui/shared-workspace-components/EditorHeaderActions'
import {EditorHeaderViewControls} from '@github-ui/shared-workspace-components/EditorHeaderViewControls'
import {useMonacoEditor} from '@github-ui/shared-workspace-components/useMonacoEditor'
import {useNavigate} from '@github-ui/use-navigate'
import {FileStatusIcon} from '@github-ui/web-commit-dialog/FileStatusIcon'
import {
  DiffEditor,
  type DiffEditorProps,
  Editor as MonacoEditor,
  type EditorProps as MonacoEditorProps,
  type Monaco,
} from '@monaco-editor/react'
import {useTheme} from '@primer/react'
import type {editor as editorTypes} from 'monaco-editor'
import {type PropsWithChildren, useCallback, useRef, useState} from 'react'
import {useSearchParams} from 'react-router-dom'

import {EditorLoadingSpinner} from '../../workspace-editor/components/EditorLoadingSpinner'
import {EscapeEditorHint, escapeEditorHintAltText} from '../../workspace-editor/components/EscapeEditorHint'
import {EditorMode, MarkdownEditor} from '../../workspace-editor/components/MarkdownEditor'
import {MarkdownIndicator} from '../../workspace-editor/components/MarkdownIndicator'
import {useWorkspaceEditorUIState} from '../../workspace-editor/contexts/WorkspaceEditorUIContext'
import {useObjectWrapper} from '../../workspace-editor/hooks/use-object-wrapper'
import {enableLanguageFeatures, ORIGINAL_CONTENTS_URI_PREFIX} from '../../workspace-editor/lsp/monaco-lsp-connector'
import {useLsps} from '../../workspace-editor/lsp/use-lsps'
import {isMarkdown} from '../../workspace-editor/utilities/file-path-helpers'
import {getFileStatus, isDeleted} from '../../workspace-editor/utilities/file-status-helpers'
import {configureMonaco} from '../../workspace-editor/utilities/monaco'
import {useUserPreference} from '../../workspace-editor/utilities/preferences'
import {initialPathQueryParam, removeQueryParam} from '../../workspace-editor/utilities/query-params'
import {validFilename} from '../../workspace-editor/utilities/tree-helpers'
import {fileUrl} from '../../workspace-editor/utilities/urls'
import type {
  ConnectedCodespaceData,
  WorkspaceEditorAppPayload,
  WorkspaceEditorRoutePayload,
} from '../../workspace-editor/utilities/workspace-editor-types'
import {isCodespaceInitialState} from '../../workspace-editor/utilities/workspace-editor-types'
import {useFilesContext} from '../contexts/FilesContext'
import {useFileUploader} from '../hooks/use-file-uploader'
import styles from './Editor.module.css'
import {EditorHeaderSettings} from './EditorHeader/EditorHeaderSettings'

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

type EditorProps = {
  copilotAccessAllowed?: boolean
  copilotCurrentTopic?: CopilotChatRepo
  codespaceData: ConnectedCodespaceData
  remoteProvider?: RemoteProvider
} & Pick<EditorHeaderProps, 'isTreeExpanded' | 'onTerminalClick' | 'onDetailsClick' | 'treeToggleElement'>

function isValidEditorMode(value: number): value is EditorMode {
  return new Set<number>(Object.values(EditorMode)).has(value)
}

export function Editor({
  copilotAccessAllowed,
  copilotCurrentTopic,
  codespaceData,
  remoteProvider,
  ...editorHeaderProps
}: EditorProps) {
  const {beforeMount} = useMonacoEditor()
  configureMonaco()
  const {ownerLogin, name, id: repositoryId} = useCurrentRepository()
  const {addFile, deleteFile, editFile, getCurrentFileContent, getFileStatuses, renameFile, resetFile} =
    useFilesContext()
  const {
    blobContents,
    large,
    isBinary,
    compareRef,
    compareBlobContents,
    diffPaths,
    fileStatuses: pullFileStatuses,
    path,
    editorSettings,
    fileTree,
    isNewFilePage,
    showOverview,
  } = useRoutePayload<WorkspaceEditorRoutePayload>()
  const {markdownDocsUrl} = useAppPayload<WorkspaceEditorAppPayload>()

  // TODO: update commitish with a valid string
  const blobViewUrl = blobPath({owner: ownerLogin, repo: name, filePath: path, commitish: ''})

  const [fileUploading, setFileUploading] = useState(false)
  const codespaceLoading = isCodespaceInitialState(codespaceData.codespaceState)

  const [pathError, setPathError] = useState(false)
  const [editorMode, setEditorMode] = useState<EditorMode>(EditorMode.Edit)
  const preferenceToString = useCallback((value: boolean) => (value ? 'true' : 'false'), [])

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

  const localFileStatuses = getFileStatuses()

  const payload = useRoutePayload<WorkspaceEditorRoutePayload>()
  const {fileStatuses = {}} = payload

  // TODO: double check this
  const fileStatus = getFileStatus({
    path,
    localFileStatuses,
    prFileStatuses: fileStatuses,
    compareRef,
  })

  const fileIcon = <FileStatusIcon status={fileStatus} />

  const calculateIsDeleted = () =>
    path in localFileStatuses ? isDeleted(localFileStatuses[path]) : isDeleted(pullFileStatuses?.[path])

  // use refs to ensure monaco editor callbacks that are subscribed in `onMount` always have the latest data
  const isFileDeleted = useObjectWrapper(calculateIsDeleted())
  const currentPath = useObjectWrapper(path)
  const currentBlobContents = useObjectWrapper(blobContents ?? '')

  const {onFileUpload, fileHandler} = useFileUploader({
    fileUploading,
    repositoryId,
    blobContents,
    currentBlobContents: currentBlobContents.current,
    currentPath: currentPath.current,
    setFileUploading,
  })

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
    'semanticHighlighting.enabled': false,
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

  const {content: value} = getCurrentFileContent(path, blobContents)

  const onChange = useCallback(
    (newValue: string | undefined) => {
      if (isFileDeleted.current) {
        return
      }

      editFile({filePath: currentPath.current, originalContent: currentBlobContents.current, newFileContent: newValue})
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

  const toggleProblemsHidden = useCallback(async () => {
    setProblemsHidden(!problemsHidden)
  }, [problemsHidden, setProblemsHidden])

  const {registerMonaco} = useLsps(codespaceData, remoteProvider)

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

  // const {initialTaskId, initialTaskSource} = useFocusedTask()
  const [searchParams] = useSearchParams()

  const isMarkdownFile = isMarkdown(path)

  const handlePathChange = () => {
    setPathError(false)
  }

  const initialPath = searchParams.get(initialPathQueryParam) || path || ''

  const [isEditing, setIsEditing] = useState(false)
  const filenameInputRef = useRef<HTMLInputElement>(null)
  const moreOptionsButtonRef = useRef<HTMLButtonElement>(null)

  const codespaceDataProps = {
    hasCodespaceInfo: !!codespaceData.codespaceInfo,
    codespaceState: codespaceData?.codespaceState,
    codespaceFriendlyName: codespaceData?.codespaceInfo?.environment_data.friendlyName,
    codespaceSkuDisplayName: codespaceData?.codespaceInfo?.environment_data.skuDisplayName,
    codespacePermissionAccepted: !!codespaceData?.permissionsStatus?.accepted,
    codespaceAllowUrl: codespaceData?.permissionsStatus?.allowPermissionsUrl,
    isCodespaceRecoveryContainer: codespaceData.isRecoveryContainer,
    pollForCodespacePermissionsAccepted: codespaceData.pollForPermissionsAccepted,
    recreateCodespace: codespaceData.recreateCodespace,
  }

  const editorHeader = (
    <EditorHeader
      fileIcon={fileIcon}
      key={`header-${path}`}
      filenameInputRef={filenameInputRef}
      moreOptionsButtonRef={moreOptionsButtonRef}
      viewControls={
        <EditorHeaderViewControls
          isDeleted={isFileDeleted.current}
          editorMode={editorMode}
          updateEditorMode={(idx: number) => {
            if (isValidEditorMode(idx)) {
              setEditorMode(idx)
            }
          }}
          isPreviewable={isMarkdownFile}
        />
      }
      actions={
        <EditorHeaderActions
          fileUploading={fileUploading || codespaceLoading}
          buttonRef={moreOptionsButtonRef}
          isDeleted={isFileDeleted.current}
          isNewFile
          onCopyFileContents={useCallback(async () => await copyText(value || ''), [value])}
          onFileUpload={onFileUpload}
          canUploadFiles={isMarkdownFile && !isFileDeleted.current && !!fileHandler}
          onDelete={useCallback(() => {
            deleteFile(path, blobContents)
          }, [blobContents, deleteFile, path])}
          onRenameSelected={useCallback(() => {
            setIsEditing(true)
            setTimeout(() => filenameInputRef?.current?.focus())
          }, [])}
          onResetSelected={useCallback(() => resetFile(path), [path, resetFile])}
          fileBlobUrl={blobViewUrl}
          showReset={false}
          hideFileMoreOptions={showOverview}
          copilotAccessAllowed={copilotAccessAllowed}
        />
      }
      settings={
        <EditorHeaderSettings
          codeLineWrapEnabled={!!codeLineWrapEnabled}
          whitespaceHidden={!!whitespaceHidden}
          problemsHidden={!!problemsHidden}
          toggleCodeLineWrapEnabled={toggleCodeLineWrapEnabled}
          toggleWhitespaceHidden={toggleWhitespaceHidden}
          toggleProblemsHidden={toggleProblemsHidden}
        />
      }
      isEditing={isEditing}
      setIsEditing={setIsEditing}
      isNewFilePage={isNewFilePage}
      initialPath={initialPath}
      path={path}
      pathError={pathError}
      onPathChange={handlePathChange}
      onSaveFileName={newFileName => {
        if (!validFilename({...diffPaths, ...fileTree}, newFileName)) {
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
          // TODO: remove with Workbench urls.ts
          fileUrl({
            path: newFileName,
            owner: ownerLogin,
            repo: name,
            pullNumber: '',
            location: window.location,
          }),
        )
      }}
      {...codespaceDataProps}
      {...editorHeaderProps}
    />
  )

  // Loading Spinner
  const loadSpinner = <EditorLoadingSpinner />

  // If the file is new, we don't show the editor since it complicates monaco model management,
  // and LSP features won't work.
  // Instead, we just show the header and let the user save the file then begin composing.
  if (isNewFilePage) return editorHeader

  return (
    <div style={{height: '100%', width: '100%'}}>
      {editorHeader}
      {large ? (
        // TODO: What do we do in cases where a file is too large and a user wants to reference it via a repo? There's
        // cases in Spark where a user won't have one yet

        // <PlainTextStatus>
        //   <p>
        //     Sorry about that, but we can’t show files that are this big right now. Go to{' '}
        //     <Link inline href={blobViewUrl}>
        //       file in the repository
        //     </Link>
        //     .
        //   </p>
        // </PlainTextStatus>
        <PlainTextStatus>
          <p>Sorry about that, but we can’t show files that are this big right now.</p>
        </PlainTextStatus>
      ) : showDeleted ? (
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
          className={problemsHidden ? styles.hideProblems : undefined}
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
          loading={loadSpinner}
        />
      ) : (
        <MonacoEditor
          className={problemsHidden ? styles.hideProblems : undefined}
          beforeMount={beforeMount}
          height="100%"
          defaultLanguage={language || 'javascript'}
          value={value}
          language={language}
          path={path}
          theme={theme}
          options={options}
          onChange={onChange}
          loading={loadSpinner}
          onMount={(editor, monaco) => {
            onMonacoMount(editor, monaco)
          }}
        />
      )}
      <EscapeEditorHint />
      {isMarkdownFile && !isFileDeleted.current && <MarkdownIndicator markdownDocsUrl={markdownDocsUrl} />}
    </div>
  )
}
