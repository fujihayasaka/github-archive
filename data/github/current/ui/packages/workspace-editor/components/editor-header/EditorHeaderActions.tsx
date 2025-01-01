import {KebabHorizontalIcon} from '@primer/octicons-react'
import {ActionList, ActionMenu, ConfirmationDialog, IconButton, SegmentedControl} from '@primer/react'
import {memo, type RefObject} from 'react'

import {useConfirmationDialog} from '../../hooks/use-confirmation-dialog'
import {EditorMode} from '../MarkdownEditor'
import {CompareDropdown} from './CompareDropdown'

export const EditorHeaderActions = memo(function HeaderActions({
  buttonRef,
  isDeleted,
  onDelete,
  onRenameSelected,
  onResetSelected,
  fileBlobUrl,
  isPreviewable = false,
  updateEditorMode,
  codeLineWrapEnabled,
  whitespaceHidden,
  toggleCodeLineWrapEnabled,
  toggleWhitespaceHidden,
  editorMode,
  showReset,
  hideFileMoreOptions,
}: {
  buttonRef: RefObject<HTMLButtonElement>
  isDeleted: boolean
  onDelete?: () => void
  onRenameSelected: () => void
  onResetSelected: () => void
  fileBlobUrl: string
  isPreviewable?: boolean
  editorMode?: EditorMode
  updateEditorMode?: (index: number) => void
  codeLineWrapEnabled: boolean
  whitespaceHidden: boolean
  toggleCodeLineWrapEnabled?: () => void
  showReset?: boolean
  hideFileMoreOptions?: boolean
  toggleWhitespaceHidden?: () => void
}) {
  const {
    isDialogOpen: isDeleteDialogOpen,
    setIsDialogOpen: setIsDeleteDialogOpen,
    onDialogClose: onDeleteDialogClose,
  } = useConfirmationDialog(onDelete, buttonRef)
  const {
    isDialogOpen: isResetDialogOpen,
    setIsDialogOpen: setIsResetDialogOpen,
    onDialogClose: onResetDialogClose,
  } = useConfirmationDialog(onResetSelected, buttonRef)
  const isSelected = (mode: EditorMode) => editorMode === mode

  return (
    <>
      <div className="d-flex flex-items-center gap-2">
        {!isDeleted && isPreviewable && (
          <SegmentedControl aria-label="File view" onChange={updateEditorMode}>
            <SegmentedControl.Button selected={isSelected(EditorMode.Edit)}>Edit</SegmentedControl.Button>
            <SegmentedControl.Button selected={isSelected(EditorMode.Preview)}>Preview</SegmentedControl.Button>
            <SegmentedControl.Button selected={isSelected(EditorMode.Split)}>Split</SegmentedControl.Button>
          </SegmentedControl>
        )}
        <CompareDropdown />
        {!hideFileMoreOptions && (
          <ActionMenu anchorRef={buttonRef}>
            <ActionMenu.Anchor>
              <IconButton aria-label="More file options" icon={KebabHorizontalIcon} variant="invisible" />
            </ActionMenu.Anchor>
            <ActionMenu.Overlay width="auto">
              <ActionList>
                <ActionList.Group>
                  <ActionList.GroupHeading>File</ActionList.GroupHeading>
                  {!isDeleted && <ActionList.LinkItem href={fileBlobUrl}>View in repository</ActionList.LinkItem>}
                  {!isDeleted && <ActionList.Item onSelect={onRenameSelected}>Rename</ActionList.Item>}
                  {showReset && (
                    <ActionList.Item onSelect={() => setIsResetDialogOpen(true)}>Reset changes</ActionList.Item>
                  )}
                  {onDelete && !isDeleted && (
                    <ActionList.Item onSelect={() => setIsDeleteDialogOpen(true)} variant="danger">
                      Delete
                    </ActionList.Item>
                  )}
                </ActionList.Group>
                {(toggleCodeLineWrapEnabled || toggleWhitespaceHidden) && (
                  <>
                    <ActionList.Divider />
                    <ActionList.Group selectionVariant="multiple">
                      <ActionList.GroupHeading>View options</ActionList.GroupHeading>
                      {toggleCodeLineWrapEnabled && (
                        <ActionList.Item
                          role="menuitemcheckbox"
                          selected={codeLineWrapEnabled}
                          aria-checked={codeLineWrapEnabled}
                          onSelect={toggleCodeLineWrapEnabled}
                        >
                          Wrap lines
                        </ActionList.Item>
                      )}
                      {toggleWhitespaceHidden && (
                        <ActionList.Item
                          role="menuitemcheckbox"
                          selected={whitespaceHidden}
                          aria-checked={whitespaceHidden}
                          onSelect={toggleWhitespaceHidden}
                        >
                          Hide whitespace
                        </ActionList.Item>
                      )}
                    </ActionList.Group>
                  </>
                )}
              </ActionList>
            </ActionMenu.Overlay>
          </ActionMenu>
        )}
      </div>
      {isDeleteDialogOpen && (
        <ConfirmationDialog
          title="Delete file"
          cancelButtonContent="Never mind"
          confirmButtonContent="Yes, delete"
          confirmButtonType="danger"
          onClose={onDeleteDialogClose}
        >
          Are you sure you want to delete this file?
        </ConfirmationDialog>
      )}
      {isResetDialogOpen && (
        <ConfirmationDialog
          title="Reset file"
          cancelButtonContent="Never mind"
          confirmButtonContent="Yes, reset"
          confirmButtonType="danger"
          onClose={onResetDialogClose}
        >
          Are you sure you want to reset this file?
        </ConfirmationDialog>
      )}
    </>
  )
})
