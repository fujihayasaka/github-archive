import {
  CopyIcon,
  KebabHorizontalIcon,
  LightBulbIcon,
  LinkExternalIcon,
  MentionIcon,
  PaperclipIcon,
  ReplyIcon,
  TrashIcon,
  TypographyIcon,
} from '@primer/octicons-react'
import {ActionList, ActionMenu, ConfirmationDialog, IconButton} from '@primer/react'
import {memo, useEffect, useState, type RefObject} from 'react'

import {useConfirmationDialog} from '../hooks/use-confirmation-dialog'

export const EditorHeaderActions = memo(function HeaderActions({
  buttonRef,
  isDeleted,
  isNewFile,
  onFileUpload,
  fileUploading = false,
  canUploadFiles = false,
  onBrainstorm,
  onCopyFileContents,
  onDelete,
  onRenameSelected,
  onResetSelected,
  fileBlobUrl,
  showReset,
  hideFileMoreOptions,
  onAddFileToChat,
  copilotAccessAllowed,
}: {
  buttonRef: RefObject<HTMLButtonElement>
  isDeleted: boolean
  isNewFile: boolean
  fileUploading?: boolean
  canUploadFiles?: boolean
  onFileUpload?: (e: React.MouseEvent<HTMLElement> | React.KeyboardEvent<HTMLElement>) => void
  onBrainstorm?: () => void
  onCopyFileContents?: () => void
  onDelete?: () => void
  onRenameSelected: () => void
  onResetSelected: () => void
  fileBlobUrl: string
  toggleCodeLineWrapEnabled?: () => void
  showReset?: boolean
  hideFileMoreOptions?: boolean
  onAddFileToChat?: (e: React.MouseEvent<HTMLElement> | React.KeyboardEvent<HTMLElement>) => void
  copilotAccessAllowed?: boolean
}) {
  const [open, setOpen] = useState(false)

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

  const allowAddFileToChat = onAddFileToChat && copilotAccessAllowed

  useEffect(() => {
    if (!fileUploading) setOpen(false)
  }, [fileUploading])

  return (
    <>
      <div className="d-flex flex-items-center gap-2">
        {!hideFileMoreOptions && (
          <ActionMenu anchorRef={buttonRef} open={open} onOpenChange={setOpen}>
            <ActionMenu.Anchor>
              <IconButton aria-label="More file options" icon={KebabHorizontalIcon} variant="invisible" />
            </ActionMenu.Anchor>
            <ActionMenu.Overlay width="small">
              <ActionList>
                {!isDeleted && (
                  <ActionList.Group>
                    {onBrainstorm && (
                      <ActionList.Item onSelect={onBrainstorm}>
                        <ActionList.LeadingVisual>
                          <LightBulbIcon />
                        </ActionList.LeadingVisual>
                        Brainstorm
                      </ActionList.Item>
                    )}
                    {allowAddFileToChat && (
                      <ActionList.Item onSelect={onAddFileToChat}>
                        <ActionList.LeadingVisual>
                          <MentionIcon />
                        </ActionList.LeadingVisual>
                        Add file to chat
                      </ActionList.Item>
                    )}
                    {onCopyFileContents && (
                      <ActionList.Item onSelect={onCopyFileContents}>
                        <ActionList.LeadingVisual>
                          <CopyIcon />
                        </ActionList.LeadingVisual>
                        Copy file contents
                      </ActionList.Item>
                    )}
                    {!isNewFile && (
                      <ActionList.LinkItem href={fileBlobUrl}>
                        <ActionList.LeadingVisual>
                          <LinkExternalIcon />
                        </ActionList.LeadingVisual>
                        Open file in GitHub
                      </ActionList.LinkItem>
                    )}
                  </ActionList.Group>
                )}
                {!isDeleted && showReset && <ActionList.Divider />}
                <ActionList.Group>
                  {!isDeleted && (
                    <ActionList.Item onSelect={onRenameSelected}>
                      <ActionList.LeadingVisual>
                        <TypographyIcon />
                      </ActionList.LeadingVisual>
                      Rename file
                    </ActionList.Item>
                  )}
                  {canUploadFiles && !!onFileUpload && (
                    <ActionList.Item loading={fileUploading} onSelect={onFileUpload}>
                      <ActionList.LeadingVisual>
                        <PaperclipIcon />
                      </ActionList.LeadingVisual>
                      Upload attachment
                    </ActionList.Item>
                  )}
                  {showReset && (
                    <ActionList.Item onSelect={() => setIsResetDialogOpen(true)}>
                      <ActionList.LeadingVisual>
                        <ReplyIcon />
                      </ActionList.LeadingVisual>
                      Discard changes
                    </ActionList.Item>
                  )}
                  {onDelete && !isDeleted && (
                    <ActionList.Item onSelect={() => setIsDeleteDialogOpen(true)} variant="danger">
                      <ActionList.LeadingVisual>
                        <TrashIcon />
                      </ActionList.LeadingVisual>
                      Delete file
                    </ActionList.Item>
                  )}
                </ActionList.Group>
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
