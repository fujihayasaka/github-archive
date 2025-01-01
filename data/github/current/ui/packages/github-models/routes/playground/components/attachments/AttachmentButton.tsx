import React from 'react'

import {IconButtonWithTooltip} from '@github-ui/icon-button-with-tooltip'
import {PaperclipIcon} from '@primer/octicons-react'

import {useChatAttachments} from './AttachmentsProvider'
import {ACCEPTED_MIME} from './constants'
import {FileReference} from './file-reference'

export function AttachmentButton(props: {disabled?: boolean}) {
  const [, api] = useChatAttachments()
  const inputRef = React.useRef<HTMLInputElement>(null)

  return (
    <>
      <input
        ref={inputRef}
        type="file"
        accept={ACCEPTED_MIME.join(',')}
        hidden
        onChange={e => {
          api.addFiles(Array.from(e.target.files || []).map(f => new FileReference(f)))
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
