import React from 'react'

import {IconButtonWithTooltip} from '@github-ui/icon-button-with-tooltip'
import {useAnalytics} from '@github-ui/use-analytics'
import {PaperclipIcon} from '@primer/octicons-react'
import {useAttachments} from '@github-ui/attachments'
import {useCreateAttachment} from './use-create-attachment'

export function AttachmentButton(props: {disabled?: boolean}) {
  const {sendAnalyticsEvent} = useAnalytics()
  const [state, api] = useAttachments()
  const createAttachment = useCreateAttachment()

  const inputRef = React.useRef<HTMLInputElement>(null)

  return (
    <>
      <input
        ref={inputRef}
        type="file"
        multiple={state.attachLimit > 1}
        accept={state.acceptedMIME.join(',')}
        hidden
        onChange={e => {
          const files = Array.from(e.target.files || []).map(createAttachment)
          api.addFiles(files)
          sendAnalyticsEvent('attachment.add', 'BUTTON', {fileCount: files.length})
        }}
      />
      <IconButtonWithTooltip
        variant="invisible"
        size="small"
        icon={PaperclipIcon}
        aria-label="Attach an image"
        label="Attach an image"
        tooltipDirection="w"
        disabled={props.disabled}
        onClick={e => {
          e.preventDefault()
          inputRef.current?.click()
        }}
      />
    </>
  )
}
