import {testIdProps} from '@github-ui/test-id-props'

import {useChatAttachments} from './AttachmentsProvider'
import {AttachmentItem} from './AttachmentItem'
import type {FileReference} from './file-reference'
import {AttachmentPreviewImage} from './AttachmentPreviewImage'

export function AttachmentPreviewOutlet() {
  const [state, api] = useChatAttachments()
  const attachments = state.attachments

  if (!attachments.length && !state.errorMessage) return null

  return (
    <div className="rounded-top-2 p-3" {...testIdProps('playground-chat-attachment-outlet')}>
      {state.errorMessage ? <span className="fgColor-danger">{state.errorMessage}</span> : null}
      <div className="d-flex flex-row gap-3">
        {attachments.map(attachment => (
          <AttachmentItem
            key={attachment.key}
            onRemove={() => {
              api.removeFile(attachment)
            }}
          >
            <AttachmentSlot file={attachment} />
          </AttachmentItem>
        ))}
      </div>
    </div>
  )
}

// NOTE: This component may suspend if the file has not loaded yet. Do you have a Suspense boundary near by?
function AttachmentSlot(props: {file: FileReference}) {
  return <AttachmentPreviewImage src={props.file.preview} />
}
