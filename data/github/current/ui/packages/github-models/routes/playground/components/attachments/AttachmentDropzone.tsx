import type {Attachment as FileElementAttachment} from '@github/file-attachment-element'
import React from 'react'

import {IS_SERVER} from '@github-ui/ssr-utils'
import {testIdProps} from '@github-ui/test-id-props'
import {useAnalytics} from '@github-ui/use-analytics'
import {useLayoutEffect} from '@github-ui/use-layout-effect'
import type FileAttachmentElement from '@github/file-attachment-element'
import invariant from 'tiny-invariant'
import {useAttachments} from '@github-ui/attachments'
import {useCreateAttachment} from './use-create-attachment'

if (!IS_SERVER) import('@github/file-attachment-element')

declare global {
  interface HTMLElementEventMap {
    'file-attachment-accept': CustomEvent<{attachments: FileElementAttachment[]}>
  }
}

export function AttachmentDropzone(props: React.PropsWithChildren<{enabled: boolean}>) {
  const {sendAnalyticsEvent} = useAnalytics()
  const [, api] = useAttachments()
  const createAttachment = useCreateAttachment()

  const attachmentRef = React.useRef<FileAttachmentElement>(null)

  useLayoutEffect(() => {
    const signal = new AbortController()

    if (attachmentRef?.current && props.enabled) {
      const el = attachmentRef.current

      el.addEventListener(
        'file-attachment-accept',
        event => {
          event.preventDefault()
          invariant(event.detail.attachments, 'Expected attachments')
          const files = event.detail.attachments.map(a => createAttachment(a.file))
          api.addFiles(files)
          sendAnalyticsEvent('attachment.add', 'DROPZONE', {fileCount: files.length})
        },
        {signal: signal.signal},
      )
    }

    if (!props.enabled) {
      signal.abort()
    }

    return () => signal.abort()
  }, [props.enabled, api])

  return props.enabled ? (
    <file-attachment
      ref={attachmentRef}
      style={{display: 'contents'}}
      {...testIdProps('playground-chat-attachment-dropzone')}
    >
      {props.children}
    </file-attachment>
  ) : (
    <>{props.children}</>
  )
}
