import {useCurrentRepository} from '@github-ui/current-repository'
import {blobPath} from '@github-ui/paths'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import type {TreePane} from '@github-ui/repos-file-tree-view'
import {TerminalIcon} from '@primer/octicons-react'
import {Button, IconButton, TextInput} from '@primer/react'
import {InlineMessage} from '@primer/react/experimental'
import {type RefObject, useCallback, useEffect, useRef, useState} from 'react'
import {useSearchParams} from 'react-router-dom'

import {useCurrentPullRequest} from '../../contexts/CurrentPullRequestProvider'
import {useFilesContext} from '../../contexts/FilesContext'
import {rtlProofPath} from '../../utilities/file-path-helpers'
import {initialPathQueryParam} from '../../utilities/query-params'
import type {ConnectedCodespaceData, WorkspaceEditorRoutePayload} from '../../utilities/workspace-editor-types'
import type {EditorMode} from '../MarkdownEditor'
import {CodespaceStatusIndicator} from './CodespaceStatusIndicator'
import styles from './EditorHeader.module.css'
import {EditorHeaderActions} from './EditorHeaderActions'

export type EditorHeaderProps = {
  isDeleted: boolean
  onDelete?: () => void
  onSaveFileName?: (newFileName: string) => void
  onTerminalClick: () => void
  onDetailsClick: () => void
  path: string
  pathError?: boolean
  onPathChange?: () => void
  isPreviewable?: boolean
  editorMode?: EditorMode
  updateEditorMode?: (index: number) => void
  terminalHeaderButtonRef: RefObject<HTMLButtonElement>
  codeLineWrapEnabled?: boolean
  whitespaceHidden?: boolean
  toggleCodeLineWrapEnabled?: () => void
  toggleWhitespaceHidden?: () => void
  codespaceData: ConnectedCodespaceData
} & Pick<TreePane, 'isTreeExpanded' | 'treeToggleElement'>

export function EditorHeader({
  isDeleted,
  isTreeExpanded,
  onDelete,
  onSaveFileName,
  onTerminalClick,
  onDetailsClick,
  path,
  pathError,
  onPathChange,
  terminalHeaderButtonRef,
  treeToggleElement,
  isPreviewable,
  updateEditorMode,
  codeLineWrapEnabled,
  whitespaceHidden,
  toggleCodeLineWrapEnabled,
  toggleWhitespaceHidden,
  editorMode,
  codespaceData,
}: EditorHeaderProps) {
  const [searchParams] = useSearchParams()
  const initialPath = searchParams.get(initialPathQueryParam) || path || ''
  const [pathInputValue, setPathInputValue] = useState(initialPath)
  const [isEditing, setIsEditing] = useState(false)
  const [terminalRequested, setTerminalRequested] = useState(false)
  const filenameInputRef = useRef<HTMLInputElement>(null)
  const moreOptionsButtonRef = useRef<HTMLButtonElement>(null)
  const {ownerLogin, name} = useCurrentRepository()
  const {isNewFilePage, showOverview} = useRoutePayload<WorkspaceEditorRoutePayload>()
  const {pullRequest} = useCurrentPullRequest()
  const {getChangedFiles, resetFile} = useFilesContext()
  const showReset = getChangedFiles().some(file => file.path === path)

  const matchesPath = new RegExp(`^${initialPath}/?$`).test(pathInputValue)
  const isInputValueValid = pathInputValue && !matchesPath

  const showFileInput = isNewFilePage || isEditing
  const blobViewUrl = blobPath({owner: ownerLogin, repo: name, filePath: path, commitish: pullRequest.headBranch})

  useEffect(() => {
    if (terminalRequested && codespaceData.codespaceInfo) {
      onTerminalClick()
      setTerminalRequested(false)
    }
  }, [codespaceData.codespaceInfo, onTerminalClick, terminalRequested])

  useEffect(() => {
    if (isNewFilePage) {
      filenameInputRef.current?.focus()
    }
    // eslint-disable-next-line react-compiler/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  const onRenameSelected = useCallback(() => {
    setIsEditing(true)
    setTimeout(() => filenameInputRef?.current?.focus())
  }, [])

  const onResetSelected = useCallback(() => {
    resetFile(path)
  }, [path, resetFile])

  let terminalButtonComponent = <></>
  if (codespaceData.codespaceState === 'ready') {
    terminalButtonComponent = (
      <IconButton
        ref={terminalHeaderButtonRef}
        aria-label="Toggle console panel"
        icon={TerminalIcon}
        onClick={() => {
          onTerminalClick()
        }}
        variant="invisible"
      />
    )
  }

  return (
    <div className="d-flex flex-row flex-items-center flex-justify-between gap-3 p-2 border-bottom bgColor-default">
      <div className="d-flex flex-row flex-items-center overflow-hidden">
        {!isTreeExpanded && treeToggleElement}
        {showFileInput ? (
          <div>
            <div className="d-flex flex-row flex-items-center gap-2">
              <h1 className="sr-only">
                {isNewFilePage ? 'Creating a new file in pull request editor' : 'Renaming file in pull request editor'}
              </h1>
              <TextInput
                ref={filenameInputRef}
                placeholder="Name your file..."
                value={pathInputValue}
                onChange={e => {
                  onPathChange?.()
                  setPathInputValue(e.target.value)
                }}
              />
              <Button
                aria-disabled={!isInputValueValid}
                inactive={!isInputValueValid}
                onClick={() => isInputValueValid && onSaveFileName?.(pathInputValue)}
                variant="primary"
              >
                Save
              </Button>
              {!isNewFilePage && (
                <Button
                  onClick={() => {
                    setIsEditing(false)
                    onPathChange?.()
                    setPathInputValue(path)

                    // return focus to the "more options" button
                    moreOptionsButtonRef.current?.focus()
                  }}
                >
                  Cancel
                </Button>
              )}
            </div>
            {pathError && (
              <InlineMessage className="mt-2" variant="critical">
                Filename conflicts with an existing file or directory
              </InlineMessage>
            )}
          </div>
        ) : (
          <h1 className={styles.fileHeading}>{rtlProofPath(path)}</h1>
        )}
      </div>
      <div className="d-flex gap-2 flex-items-center">
        <CodespaceStatusIndicator codespaceData={codespaceData} onDetailsClick={onDetailsClick} />
        {terminalButtonComponent}
        <EditorHeaderActions
          buttonRef={moreOptionsButtonRef}
          isDeleted={isDeleted}
          onDelete={onDelete}
          onRenameSelected={onRenameSelected}
          onResetSelected={onResetSelected}
          fileBlobUrl={blobViewUrl}
          editorMode={editorMode}
          updateEditorMode={updateEditorMode}
          isPreviewable={isPreviewable}
          codeLineWrapEnabled={!!codeLineWrapEnabled}
          whitespaceHidden={!!whitespaceHidden}
          toggleCodeLineWrapEnabled={toggleCodeLineWrapEnabled}
          showReset={showReset}
          hideFileMoreOptions={showOverview}
          toggleWhitespaceHidden={toggleWhitespaceHidden}
        />
      </div>
    </div>
  )
}
