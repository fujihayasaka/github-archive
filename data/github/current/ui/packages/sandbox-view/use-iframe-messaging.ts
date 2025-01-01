import {useState, useCallback, useEffect} from 'react'
import type {RenderCommand, RenderMessage, PreviewData} from './types'
import {RenderState} from './types'

function onMessage(
  event: MessageEvent,
  origin: string,
  iFrameRef: React.RefObject<HTMLIFrameElement>,
  containerRef: React.RefObject<HTMLDivElement>,
  setErrorMessage: (error: string) => void,
  setRenderState: (state: RenderState) => void,
) {
  const message = getMessage(event)
  if (!message) return

  const body = message.body

  const renderWindow = iFrameRef.current?.contentWindow

  switch (body) {
    case 'hello':
      {
        const ackmsg = {
          type: 'render:cmd',
          body: {
            cmd: 'ack',
            ack: true,
          },
        } as const

        const msg = {
          type: 'render:cmd',
          body: {
            cmd: 'branding',
            branding: false,
          },
        } as const

        sendRenderCommand(renderWindow, ackmsg)
        sendRenderCommand(renderWindow, msg)
      }
      break
    case 'error':
    case 'error:fatal':
    case 'error:invalid':
      setRenderState(RenderState.ERROR)
      if (message.payload?.error) {
        setErrorMessage(message.payload.error)
      }
      break
    case 'loading':
      setRenderState(RenderState.LOADING)
      break
    case 'loaded':
      setRenderState(RenderState.LOADED)
      break
    case 'ready':
      if (!iFrameRef.current || !containerRef.current) return

      setRenderState(RenderState.READY)
      break
    default:
      break
  }
}

function sendDataToIFrame(iframe: HTMLIFrameElement, container: HTMLDivElement, renderableData: PreviewData) {
  const msg = {
    type: 'render:cmd',
    body: {
      cmd: 'sandbox:data:ready',
      'sandbox:data:ready': {
        ...renderableData,
      },
    },
  } as const

  sendRenderCommand(iframe.contentWindow, msg)
}

function sendRenderCommand(renderWindow: Window | null | undefined, message: RenderCommand) {
  if (renderWindow && renderWindow.postMessage) {
    renderWindow.postMessage(JSON.stringify(message), '*')
  }
}

function getMessage(event: MessageEvent): RenderMessage | null {
  let data = event.data as unknown

  if (!data) return null

  if (typeof data === 'string') {
    try {
      data = JSON.parse(data) as unknown
    } catch {
      // Ignore parse errors
      return null
    }
  }

  if (!isRenderMessage(data)) return null

  return data
}

function isRenderMessage(data: unknown): data is RenderMessage {
  if (typeof data !== 'object' || !data) {
    return false
  }

  const messageData = data as RenderMessage
  return (
    messageData.type === 'render' && typeof messageData.body === 'string' && typeof messageData.payload === 'object'
  )
}

export function useIFrameMessaging(
  iFrameRef: React.RefObject<HTMLIFrameElement>,
  containerRef: React.RefObject<HTMLDivElement>,
  previewData: PreviewData,
  viewscreenOrigin: string,
) {
  const [renderState, setRenderState] = useState<RenderState>(RenderState.LOADING)
  const [errorMessage, setErrorMessage] = useState<string>()

  const messageListener = useCallback(
    (event: MessageEvent) =>
      onMessage(event, viewscreenOrigin, iFrameRef, containerRef, setErrorMessage, setRenderState),
    [containerRef, iFrameRef, viewscreenOrigin],
  )

  useEffect(() => {
    window.addEventListener('message', messageListener)
    return () => window.removeEventListener('message', messageListener)
  }, [messageListener])

  useEffect(() => {
    if (renderState !== RenderState.READY) return

    if (!iFrameRef.current || !containerRef.current) return
    sendDataToIFrame(iFrameRef.current, containerRef.current, previewData)
  }, [containerRef, iFrameRef, previewData, renderState])

  return {renderState, errorMessage}
}
