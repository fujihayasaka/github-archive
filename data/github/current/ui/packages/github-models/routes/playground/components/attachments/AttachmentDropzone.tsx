import React from 'react'

import {IS_SERVER} from '@github-ui/ssr-utils'
import {testIdProps} from '@github-ui/test-id-props'
import {useLayoutEffect} from '@github-ui/use-layout-effect'
import type FileAttachmentElement from '@github/file-attachment-element'

import invariant from 'tiny-invariant'
import {useChatAttachments} from './AttachmentsProvider'
import {FileReference} from './file-reference'

if (!IS_SERVER) import('@github/file-attachment-element')

export function AttachmentDropzone(props: React.PropsWithChildren<{enabled: boolean}>) {
  const [, api] = useChatAttachments()

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
          const files = event.detail.attachments.map(a => new FileReference(a.file))
          api.addFiles(files)
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
