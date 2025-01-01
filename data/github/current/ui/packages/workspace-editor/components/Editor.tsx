import {getLanguage, type RemoteProvider} from '@github/codespaces-lsp'
import {useChatDispatch, useChatState} from '@github-ui/copilot-chat/CopilotChatContext'
import {makeFileReference} from '@github-ui/copilot-chat/utils/copilot-chat-helpers'
import type {CopilotChatRepo} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {copyText} from '@github-ui/copy-to-clipboard'
import {type Repository, useCurrentRepository} from '@github-ui/current-repository'
import {blobPath} from '@github-ui/paths'
import {useAppPayload} from '@github-ui/react-core/use-app-payload'
import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {EditorHeader, type EditorHeaderProps} from '@github-ui/shared-workspace-components/EditorHeader'
import {EditorHeaderActions} from '@github-ui/shared-workspace-components/EditorHeaderActions'
import {EditorHeaderSettings} from '@github-ui/shared-workspace-components/EditorHeaderSettings'
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
import {Link, useTheme} from '@primer/react'
import type {editor as editorTypes} from 'monaco-editor'
import {type PropsWithChildren, useCallback, useRef, useState} from 'react'
import {useSearchParams} from 'react-router-dom'

import {useCurrentPullRequest} from '../contexts/CurrentPullRequestProvider'
import {useFilesContext} from '../contexts/FilesContext'
import {useFocus} from '../contexts/FocusContext'
import {useWorkspaceEditorUIDispatch, useWorkspaceEditorUIState} from '../contexts/WorkspaceEditorUIContext'
import {useFileUploader} from '../hooks/use-file-uploader'
import {useFocusedCommentDecorations} from '../hooks/use-focused-comment-decorations'
import {useFocusedTask} from '../hooks/use-focused-task'
import {useObjectWrapper} from '../hooks/use-object-wrapper'
import {enableLanguageFeatures, ORIGINAL_CONTENTS_URI_PREFIX} from '../lsp/monaco-lsp-connector'
import {useLsps} from '../lsp/use-lsps'
import {AnalyticsContext} from '../telemetry/AnalyticsContext'
import {UNKNOWN_VALUE, UNSET_VALUE} from '../telemetry/constants'
import {useAnalytics} from '../telemetry/use-analytics'
import {isMarkdown} from '../utilities/file-path-helpers'
import {getFileStatus, isAdded, isDeleted} from '../utilities/file-status-helpers'
import {configureMonaco} from '../utilities/monaco'
import {setPreferredDiffStyle, useUserPreference} from '../utilities/preferences'
import {initialPathQueryParam, removeQueryParam, setQueryParam} from '../utilities/query-params'
import {validFilename} from '../utilities/tree-helpers'
import {fileUrl} from '../utilities/urls'
import {uuid} from '../utilities/uuid'
import type {
  ConnectedCodespaceData,
  DiffStyle,
  PullRequestData,
  WorkspaceEditorAppPayload,
  WorkspaceEditorRoutePayload,
} from '../utilities/workspace-editor-types'
import {isCodespaceInitialState} from '../utilities/workspace-editor-types'
import {RightPanelType} from '../utilities/workspace-editor-ui-reducer'
import {ConflictDialog} from './ConflictDialog'
import styles from './Editor.module.css'
import {EditorLoadingSpinner} from './EditorLoadingSpinner'
import {EscapeEditorHint, escapeEditorHintAltText} from './EscapeEditorHint'
import {EditorMode, MarkdownEditor} from './MarkdownEditor'
import {MarkdownIndicator} from './MarkdownIndicator'

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

function getCompareState(repository: Repository, pullRequest: PullRequestData, compareRef: string | undefined) {
  // only show new changes against the head branch
  if (compareRef === pullRequest.headBranch) {
    return 'uncommitted'
  } else {
    // show all changes against the base branch
    return 'branch'
  }
}

// Editor session ID.
const EDITOR_SESSION_ID = uuid()

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
  const {markdownDocsUrl, monacoWorkerUrls} = useAppPayload<WorkspaceEditorAppPayload>()
  configureMonaco(monacoWorkerUrls)
  const {ownerLogin, name, id: repositoryId} = useCurrentRepository()
  const {
    addFile,
    deleteFile,
    editFile,
    getChangedFiles,
    getCurrentFileContent,
    getFileStatuses,
    renameFile,
    resetFile,
  } = useFilesContext()
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
    repo,
  } = useRoutePayload<WorkspaceEditorRoutePayload>()
  const {pullRequest} = useCurrentPullRequest()
  const {currentReferences} = useChatState()
  const blobViewUrl = blobPath({owner: ownerLogin, repo: name, filePath: path, commitish: pullRequest.headBranch})

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
  const {preference: whitespaceHidden, updatePreference: setWhitespaceHidden} = useUserPreference(
    'hadron_whitespace_hidden',
    editorSettings.whitespaceHidden,
    preferenceToString,
  )

  const {preference: problemsHidden, updatePreference: setProblemsHidden} = useUserPreference(
    'hadron_problems_hidden',
    editorSettings.problemsHidden,
    preferenceToString,
  )

  const localFileStatuses = getFileStatuses()

  const payload = useRoutePayload<WorkspaceEditorRoutePayload>()
  const {fileStatuses = {}} = payload

  const fileStatus = getFileStatus({
    path,
    localFileStatuses,
    prFileStatuses: fileStatuses,
    compareRef,
    headBranch: pullRequest.headBranch,
  })

  const fileIcon = <FileStatusIcon status={fileStatus} />

  const calculateIsDeleted = () =>
    path in localFileStatuses ? isDeleted(localFileStatuses[path]) : isDeleted(pullFileStatuses?.[path])

  // use refs to ensure monaco editor callbacks that are subscribed in `onMount` always have the latest data
  const isFileDeleted = useObjectWrapper(calculateIsDeleted())
  const currentPath = useObjectWrapper(path)
  const currentBlobContents = useObjectWrapper(blobContents ?? '')

  const canUploadFiles = useFeatureFlag('file_uploading_in_workspace_editor')

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
    // eslint-disable-next-line react-hooks/react-compiler
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

  const {registerMonaco} = useLsps(codespaceData, sendEvent, remoteProvider)
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
  const [searchParams, setSearchParams] = useSearchParams()

  const isMarkdownFile = isMarkdown(path)

  const handlePathChange = () => {
    setPathError(false)
  }

  const initialPath = searchParams.get(initialPathQueryParam) || path || ''

  const [isEditing, setIsEditing] = useState(false)
  const filenameInputRef = useRef<HTMLInputElement>(null)
  const moreOptionsButtonRef = useRef<HTMLButtonElement>(null)

  const dispatch = useWorkspaceEditorUIDispatch()

  const layoutState = showDiff ? diffStyle : 'hidden'
  const setLayoutState = useCallback(
    (newDiffStyle: DiffStyle | 'hidden') => {
      if (newDiffStyle === 'hidden') {
        dispatch({type: 'SET_SHOW_DIFF', showDiff: false})
      } else {
        dispatch({type: 'SET_DIFF_STYLE', diffStyle: newDiffStyle})
        setPreferredDiffStyle(newDiffStyle)
      }
    },
    [dispatch],
  )
  const showDiffState = getCompareState(repo, pullRequest, compareRef)
  const setShowDiffState = useCallback(
    (state: 'uncommitted' | 'branch' | 'latest') => {
      dispatch({type: 'SET_SHOW_DIFF', showDiff: true})

      if (state === 'uncommitted') {
        setQueryParam('compare_ref', pullRequest.headBranch, setSearchParams)
      } else if (state === 'branch') {
        setQueryParam('compare_ref', pullRequest.baseBranch, setSearchParams)
      } else if (state === 'latest') {
        setQueryParam('compare_ref', pullRequest.headSHA, setSearchParams)
      }
    },
    [dispatch, pullRequest, setSearchParams],
  )

  const fileReference = copilotCurrentTopic ? makeFileReference(path, copilotCurrentTopic) : null

  const {rightPanel} = useWorkspaceEditorUIState()
  const copilotChatDispatch = useChatDispatch()
  const {focusTarget} = useFocus()
  const onAddFileToChat = useCallback(
    (e: React.MouseEvent<HTMLElement> | React.KeyboardEvent<HTMLElement>) => {
      if (fileReference && !currentReferences.find(ref => 'url' in ref && ref.url === fileReference.url)) {
        copilotChatDispatch({
          type: 'ADD_REFERENCE',
          reference: fileReference,
          source: 'editorHeader',
        })
      }

      if (rightPanel !== RightPanelType.Chat) {
        dispatch({
          type: 'OPEN_RIGHT_PANEL',
          rightPanel: RightPanelType.Chat,
          rightPanelButton: e.currentTarget,
        })
      }

      setTimeout(() => focusTarget('copilotChatPanelInput'), 1)
    },
    [fileReference, currentReferences, rightPanel, copilotChatDispatch, dispatch, focusTarget],
  )

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
          isNewFile={isAdded(localFileStatuses[path])}
          onCopyFileContents={useCallback(async () => await copyText(value || ''), [value])}
          onFileUpload={onFileUpload}
          canUploadFiles={canUploadFiles && isMarkdownFile && !isFileDeleted.current && !!fileHandler}
          onDelete={useCallback(() => {
            deleteFile(path, blobContents)
          }, [blobContents, deleteFile, path])}
          onRenameSelected={useCallback(() => {
            setIsEditing(true)
            setTimeout(() => filenameInputRef?.current?.focus())
          }, [])}
          onResetSelected={useCallback(() => resetFile(path), [path, resetFile])}
          fileBlobUrl={blobViewUrl}
          showReset={getChangedFiles().some(file => file.path === path)}
          hideFileMoreOptions={showOverview}
          copilotAccessAllowed={copilotAccessAllowed}
          onAddFileToChat={onAddFileToChat}
        />
      }
      settings={
        <EditorHeaderSettings
          layout={layoutState}
          showDiff={showDiffState}
          setLayout={setLayoutState}
          setShowDiff={setShowDiffState}
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
          fileUrl({
            path: newFileName,
            owner: ownerLogin,
            repo: name,
            pullNumber: pullRequest.number,
            location: window.location,
          }),
        )
      }}
      {...codespaceDataProps}
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

  // Loading Spinner
  const loadSpinner = <EditorLoadingSpinner />

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
      {large ? (
        <PlainTextStatus>
          <p>
            Sorry about that, but we can’t show files that are this big right now. Go to{' '}
            <Link inline href={blobViewUrl}>
              file in the repository
            </Link>
            .
          </p>
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
    </AnalyticsContext>
  )
}
