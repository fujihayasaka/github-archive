import {Button, TextInput} from '@primer/react'
import {InlineMessage} from '@primer/react/experimental'
import type React from 'react'
import {type RefObject, useEffect, useState} from 'react'

import {rtlProofPath} from '../utilities/file-path-helpers'
import type {SharedCodespaceProps, TCodespaceState} from '../utilities/workspace-editor-types'
import styles from './EditorHeader.module.css'

export type EditorHeaderProps = SharedCodespaceProps & {
  viewControls?: React.ReactNode
  actions?: React.ReactNode
  fileIcon?: React.ReactNode
  settings?: React.ReactNode
  treeToggleElement?: React.ReactNode
  isEditing?: boolean
  isNewFilePage?: boolean
  isTreeExpanded: boolean
  onSaveFileName?: (newFileName: string) => void
  onTerminalClick: () => void
  onDetailsClick: () => void
  initialPath: string
  path: string
  pathError?: boolean
  onPathChange?: () => void
  setIsEditing?: (isEditing: boolean) => void
  filenameInputRef?: RefObject<HTMLInputElement>
  moreOptionsButtonRef?: RefObject<HTMLButtonElement>
  hasCodespaceInfo: boolean
  codespaceState: TCodespaceState
}

export function EditorHeader({
  viewControls,
  actions,
  fileIcon,
  settings,
  isEditing,
  setIsEditing,
  isNewFilePage,
  isTreeExpanded,
  onSaveFileName,
  onTerminalClick,
  initialPath,
  path,
  pathError,
  onPathChange,
  filenameInputRef,
  moreOptionsButtonRef,
  treeToggleElement,
  hasCodespaceInfo,
}: EditorHeaderProps) {
  const [pathInputValue, setPathInputValue] = useState(initialPath)
  const [terminalRequested, setTerminalRequested] = useState(false)

  const matchesPath = new RegExp(`^${initialPath}/?$`).test(pathInputValue)
  const isInputValueValid = pathInputValue && !matchesPath
  const showFileInput = isNewFilePage || isEditing

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
    // eslint-disable-next-line react-compiler/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  return (
    <div
      className={`d-flex flex-row flex-items-center flex-justify-between gap-3 p-2 border-bottom bgColor-default ${styles.container}`}
    >
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
          <>
            {fileIcon}
            <h1 className={styles.fileHeading}>{rtlProofPath(path)}</h1>
          </>
        )}
      </div>
      <div className="d-flex gap-2 flex-items-center">
        {viewControls}
        {settings}
        {actions}
      </div>
    </div>
  )
}
