import type {CustomCopilot} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {getCopilotSpaceEditPath} from '@github-ui/copilot-chat/utils/custom-copilots-helpers'
import type {
  CustomCopilotFreeTextResource,
  CustomCopilotUploadedTextFileResource,
} from '@github-ui/custom-copilots/types'
import {ArrowLeftIcon, PencilIcon} from '@primer/octicons-react'
import {IconButton} from '@primer/react'
import {Dialog} from '@primer/react/experimental'
import {clsx} from 'clsx'
import {useState} from 'react'
import {useNavigate} from 'react-router-dom'

import styles from './AllAttachmentsDialog.module.css'
import {AttachmentsList} from './AttachmentsList'

interface AllAttachmentsDialogProps {
  copilotSpace: CustomCopilot
  onClose: () => void
  returnFocusRef: React.RefObject<HTMLButtonElement>
  initialAttachment?: CustomCopilotFreeTextResource | CustomCopilotUploadedTextFileResource | null
}

export function AllAttachmentsDialog({
  copilotSpace,
  onClose,
  returnFocusRef,
  initialAttachment,
}: AllAttachmentsDialogProps) {
  const navigate = useNavigate()
  const [selectedAttachment, setSelectedAttachment] = useState<
    CustomCopilotFreeTextResource | CustomCopilotUploadedTextFileResource | null
  >(initialAttachment ?? null)

  return (
    <Dialog
      onClose={onClose}
      position={{narrow: 'fullscreen'}}
      returnFocusRef={returnFocusRef}
      footerButtons={
        copilotSpace.editable === true && selectedAttachment === null
          ? [
              {
                content: 'Edit',
                leadingVisual: PencilIcon,
                onClick: () => navigate(`${getCopilotSpaceEditPath(copilotSpace)}#attachments`),
              },
            ]
          : undefined
      }
      renderHeader={() => (
        <Dialog.Header>
          <div className="d-flex flex-items-center">
            {selectedAttachment ? (
              <>
                <IconButton
                  icon={ArrowLeftIcon}
                  variant="invisible"
                  onClick={() => setSelectedAttachment(null)}
                  aria-label="Back"
                  className="mr-1"
                />
                <Dialog.Title className={styles.dialogTitle}>{selectedAttachment?.name ?? 'Attachments'}</Dialog.Title>
              </>
            ) : (
              <Dialog.Title className={clsx(styles.dialogTitle, 'pl-2')}>Attachments</Dialog.Title>
            )}
            <Dialog.CloseButton onClose={onClose} />
          </div>
        </Dialog.Header>
      )}
    >
      {selectedAttachment ? (
        'text' in selectedAttachment ? (
          <p className={styles.attachmentText}>{selectedAttachment.text}</p>
        ) : (
          // TODO: Add support for viewing uploaded text file attachments - https://github.com/github/copilot-productivity/issues/6010
          <p>No preview available for this attachment.</p>
        )
      ) : (
        <AttachmentsList attachments={copilotSpace.resources} onTextFileClick={setSelectedAttachment} />
      )}
    </Dialog>
  )
}
