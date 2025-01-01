import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {FileDirectoryIcon, SidebarExpandIcon} from '@primer/octicons-react'
import {Button, IconButton, Label, TextInput} from '@primer/react'
import {InlineMessage} from '@primer/react/experimental'
import type React from 'react'
import {type RefObject, useEffect, useState} from 'react'

import {rtlProofPath} from '../../../shared-workspace-components/utilities/file-path-helpers'
import {useTerminalContext} from '../../contexts/TerminalContext'
import {Region, RegionState, useRegionState} from '../../hooks/use-region-state'
import type {WorkbenchRoutePayload} from '../../types/workbench-types'
import styles from './EditorHeader.module.css'

export type EditorHeaderProps = {
  viewControls?: React.ReactNode
  actions?: React.ReactNode
  settings?: React.ReactNode
  isFileTreeExpanded: boolean
  setIsFileTreeExpanded: (isExpanded: boolean) => void
  onSaveFileName?: (newFileName: string) => void
  onTerminalClick: () => void
  initialPath: string
  path: string
  pathError?: boolean
  onPathChange?: () => void
  filenameInputRef?: RefObject<HTMLInputElement>
  moreOptionsButtonRef?: RefObject<HTMLButtonElement>
}

export function EditorHeader({
  viewControls,
  actions,
  settings,
  onSaveFileName,
  onTerminalClick,
  initialPath,
  path,
  pathError,
  onPathChange,
  filenameInputRef,
  moreOptionsButtonRef,
  isFileTreeExpanded,
  setIsFileTreeExpanded,
}: EditorHeaderProps) {
  const {isNewFilePage} = useRoutePayload<WorkbenchRoutePayload>()
  const {
    state: {codespaceData},
  } = useTerminalContext()

  const [pathInputValue, setPathInputValue] = useState(initialPath)
  const [terminalRequested, setTerminalRequested] = useState(false)
  const [isEditing, setIsEditing] = useState(false)

  const matchesPath = new RegExp(`^${initialPath}/?$`).test(pathInputValue)
  const isInputValueValid = pathInputValue && !matchesPath
  const showFileInput = isNewFilePage || isEditing
  const hasCodespaceInfo = !!codespaceData.codespaceInfo

  const editorState = useRegionState(Region.EDITOR)
  const readOnly = editorState === RegionState.READ_ONLY

  useEffect(() => {
    if (terminalRequested && hasCodespaceInfo) {
      onTerminalClick()
      setTerminalRequested(false)
    }
  }, [hasCodespaceInfo, onTerminalClick, terminalRequested])

  useEffect(() => {
    if (isNewFilePage) {
      filenameInputRef?.current?.focus()
    }
    // eslint-disable-next-line react-hooks/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  return (
    <div
      className={`d-flex flex-row flex-items-center flex-justify-between gap-3 px-2 color-border-muted bgColor-default ${styles.container}`}
    >
      <div className="d-flex flex-row flex-items-center overflow-hidden">
        <div className={styles.treeToggleContainer}>
          <IconButton
            aria-label={isFileTreeExpanded ? 'Collapse file tree' : 'Expand file tree'}
            icon={isFileTreeExpanded ? SidebarExpandIcon : FileDirectoryIcon}
            onClick={() => setIsFileTreeExpanded(!isFileTreeExpanded)}
            variant="invisible"
          />
        </div>
        {showFileInput ? (
          <div>
            <div className="d-flex flex-row flex-items-center gap-2">
              <h1 className="sr-only">
                {isNewFilePage ? 'Creating a new file in the editor' : 'Renaming file in the editor'}
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
                    setIsEditing?.(false)
                    onPathChange?.()
                    setPathInputValue(path)

                    // return focus to the "more options" button
                    moreOptionsButtonRef?.current?.focus()
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
          <div className="ml-2 d-flex flex-items-center gap-2">
            <h1 className={styles.fileHeading}>{rtlProofPath(path)}</h1>
            {readOnly && <Label variant="secondary">Read-only</Label>}
          </div>
        )}
      </div>
      <div className="d-flex gap-2 mr-2 flex-items-center">
        {viewControls}
        {actions}
        {settings}
      </div>
    </div>
  )
}
