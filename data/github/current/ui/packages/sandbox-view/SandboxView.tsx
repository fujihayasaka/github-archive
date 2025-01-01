import {useMemo, useRef} from 'react'
import {RenderState, type PreviewData} from './types'
import {useIFrameMessaging} from './use-iframe-messaging'
import {ssrSafeLocation} from '@github-ui/ssr-utils'
import {isFeatureEnabled} from '@github-ui/feature-flags'

import sandboxStyles from './SandboxView.module.css'
import {ErrorMessage} from './ErrorMessage'

function sandboxUrl(viewscreenUrl: string) {
  return new URL('view/sandbox?url=client://sandbox', viewscreenUrl).toString()
}

export interface SandboxProps extends PreviewData {
  viewscreenUrl: string
}

export function SandboxView({content, scripts, styles, viewscreenUrl}: SandboxProps) {
  const sandboxEnabled = isFeatureEnabled('viewscreen_sandbox')
  const url = sandboxUrl(viewscreenUrl)
  const origin = new URL(url, ssrSafeLocation.origin).origin

  const iFrameRef = useRef<HTMLIFrameElement>(null)
  const containerRef = useRef<HTMLDivElement>(null)

  const previewData = useMemo<PreviewData>(
    () => ({
      content,
      scripts,
      styles,
    }),
    [content, scripts, styles],
  )

  const {renderState, errorMessage} = useIFrameMessaging(iFrameRef, containerRef, previewData, origin)

  if (!sandboxEnabled) return null

  return (
    <div ref={containerRef} className={sandboxStyles.container}>
      {renderState === RenderState.ERROR ? (
        <ErrorMessage error={errorMessage} />
      ) : (
        <iframe
          ref={iFrameRef}
          className={sandboxStyles.iframe}
          sandbox="allow-scripts"
          title="Preview page for the user provided code"
          src={url}
        />
      )}
    </div>
  )
}
