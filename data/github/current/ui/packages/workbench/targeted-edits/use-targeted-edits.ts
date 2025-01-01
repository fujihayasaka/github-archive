import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {useNavigate} from '@github-ui/use-navigate'
import {useCallback, useEffect, useMemo, useRef, useState} from 'react'

import {useCodespaceContext} from '../contexts/CodespaceContext'
import {useWorkbenchContext} from '../contexts/WorkbenchContext'
import type {WorkbenchRoutePayload} from '../types/workbench-types'
import {
  useGetThemeVariables,
  useModifyGlobalCssVariable,
  useModifyJsxClassName,
  useModifyJsxText,
  useModifyThemeVariables,
} from './query'
import type {BridgeMessage, HostMessage} from './types'

function sendMessageToHost(message: BridgeMessage) {
  const iframe = document.getElementById('spark-preview-iframe') as HTMLIFrameElement

  if (!iframe || !iframe.contentWindow) {
    return
  }

  iframe.contentWindow.postMessage(message, '*')
}

export function useTargetedEdits() {
  const payload = useRoutePayload<WorkbenchRoutePayload>()
  const {sparkFileUrl, isFetching} = useWorkbenchContext()

  const {codespaceData} = useCodespaceContext()

  const {friendlyName} = codespaceData.codespaceInfo?.environment_data || {}
  const domain = codespaceData.remoteProvider?.tunnelProps.domain ?? 'app.github.dev'

  const designerServerUrl = useMemo(() => {
    if (!friendlyName || !domain) return ''
    return `https://${friendlyName}-4000.${domain}`
  }, [friendlyName, domain])

  const tunnelToken =
    codespaceData.codespaceInfo?.environment_data.connection.tunnelProperties?.connectAccessToken || ''

  const [isEnabled, setIsEnabled] = useState(false)
  const [selectedElement, setSelectedElement] = useState<HostMessage['element'] | null>(null)
  const prevElement = useRef<HostMessage['element'] | null>(null)

  const {mutateAsync: modifyJsxClassName} = useModifyJsxClassName(designerServerUrl, tunnelToken)
  const {mutateAsync: modifyJsxText} = useModifyJsxText(designerServerUrl, tunnelToken)
  const {mutateAsync: modifyGlobalCssVariable} = useModifyGlobalCssVariable(designerServerUrl, tunnelToken)
  const {mutateAsync: modifyThemeVariables} = useModifyThemeVariables(designerServerUrl, tunnelToken)
  const {data: themeVariables, refetch: refetchThemeVariables} = useGetThemeVariables(designerServerUrl, tunnelToken)

  const navigate = useNavigate()

  useEffect(() => {
    if (!designerServerUrl || !tunnelToken) return

    const handler = (event: MessageEvent<HostMessage>) => {
      // TODO: check origin of the event
      // if (event.origin !== designerServerUrl) return
      switch (event.data.type) {
        case 'spark:designer:host:element:selected': {
          setSelectedElement(event.data.element)
          const {location, component} = event.data.element
          const path = location?.start.filePath ?? component.location?.start.filePath

          if (path) {
            navigate(
              sparkFileUrl({
                sparkId: payload.workbench.id,
                path,
              }),
            )
          }
          return
        }
        case 'spark:designer:bridge:element:updated': {
          setSelectedElement(prev => {
            if (prev) {
              return event.data.element
            }
            return prev
          })
          return
        }

        case 'spark:designer:bridge:element:deselected': {
          setSelectedElement(null)
          return
        }
      }
    }

    window.addEventListener('message', handler)
    return () => {
      window.removeEventListener('message', handler)
    }
  }, [designerServerUrl, tunnelToken, navigate, payload.workbench.id, sparkFileUrl])

  const enableTargetedEdits = useCallback(async () => {
    setIsEnabled(true)
    sendMessageToHost({
      type: 'spark:designer:bridge:enable',
    })
  }, [])

  const disableTargetedEdits = useCallback(() => {
    setIsEnabled(false)
    setSelectedElement(null)
    sendMessageToHost({
      type: 'spark:designer:bridge:disable',
    })
  }, [])

  const toggleTargetedEdits = useCallback(() => {
    if (isEnabled) {
      disableTargetedEdits()
    } else {
      enableTargetedEdits()
    }
  }, [isEnabled, disableTargetedEdits, enableTargetedEdits])

  const deselectElement = useCallback(() => {
    setSelectedElement(null)
    sendMessageToHost({
      type: 'spark:designer:bridge:deselect',
    })
  }, [])

  useEffect(() => {
    if (isFetching) {
      disableTargetedEdits()
    }
  }, [isFetching, disableTargetedEdits])

  useEffect(() => {
    if (!selectedElement) return

    if (selectedElement.text !== null && selectedElement.text !== prevElement.current?.text) {
      const location = selectedElement.location ?? selectedElement.component.location!
      modifyJsxText({
        filePath: location.start.filePath,
        line: location.start.line,
        column: location.start.column,
        content: selectedElement.text,
      })
    }

    prevElement.current = selectedElement
  }, [modifyJsxText, selectedElement])

  return useMemo(
    () => ({
      targetedEditsEnabled: isEnabled,
      enableTargetedEdits,
      disableTargetedEdits,
      toggleTargetedEdits,
      selectedElement,
      deselectElement,
      modifyJsxClassName,
      modifyJsxText,
      modifyGlobalCssVariable,
      modifyThemeVariables,
      themeVariables,
      refetchThemeVariables,
    }),
    [
      isEnabled,
      selectedElement,
      disableTargetedEdits,
      enableTargetedEdits,
      toggleTargetedEdits,
      deselectElement,
      modifyJsxClassName,
      modifyJsxText,
      modifyGlobalCssVariable,
      modifyThemeVariables,
      themeVariables,
      refetchThemeVariables,
    ],
  )
}
