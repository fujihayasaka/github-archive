import {testIdProps} from '@github-ui/test-id-props'

import {useAttachments} from '@github-ui/attachments'
import {AttachmentItem} from './AttachmentItem'
import type {Attachment} from '@github-ui/attachments/types'
import {AttachmentPreviewImage} from './AttachmentPreviewImage'

export function AttachmentPreviewOutlet() {
  const [state, api] = useAttachments()
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
              api.remove(attachment)
            }}
          >
            <AttachmentSlot attachment={attachment} />
          </AttachmentItem>
        ))}
      </div>
    </div>
  )
}

// NOTE: This component may suspend if the file has not loaded yet. Do you have a Suspense boundary near by?
function AttachmentSlot(props: {attachment: Attachment}) {
  return <AttachmentPreviewImage src={props.attachment.previewUrl} />
}
