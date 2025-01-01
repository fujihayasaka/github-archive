import React from 'react'

import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'
import type {FileAttachment} from '@github-ui/attachments/types'
import {Base64FileAttachment} from './base64-file-attachment'
import {UploadableFileAttachment} from './uploadable-file-attachment'

export function useCreateAttachment() {
  const shoulduseUploadableAttachments = useFeatureFlag('github_models_uploadable_attachments')

  const abortController = React.useRef<AbortController>()

  // If we unmount, abort any inflight uploads
  React.useEffect(
    () => () => {
      abortController.current?.abort()
    },
    [],
  )

  return React.useCallback(
    (file: File) => {
      const controller = (abortController.current ||= new AbortController())

      let attachment: FileAttachment

      if (shoulduseUploadableAttachments) {
        attachment = new UploadableFileAttachment(file, controller.signal)
      }

      attachment ||= new Base64FileAttachment(file)
      attachment.prefetch()

      return attachment
    },
    [shoulduseUploadableAttachments],
  )
}
