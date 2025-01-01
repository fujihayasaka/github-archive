import {sendEvent} from '@github-ui/hydro-analytics'

import type {PreviewableContent} from './content-preview-types'

export function sendContentPreviewEvent(
  eventName: string,
  contentPreview: PreviewableContent,
  additionalData: Record<string, string | number | boolean | undefined | null> = {},
) {
  sendEvent(eventName, {
    contentPreviewType: contentPreview.type,
    mode: 'immersive',
    path: contentPreview.id,
    ...additionalData,
  })
}
