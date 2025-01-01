import {createFileSyncerClient, type IFileSyncerClient, type RemoteProvider} from '@github/codespaces-lsp'
import {useCallback, useEffect, useRef} from 'react'

import type {ConnectedCodespaceData} from '../utilities/workspace-editor-types'

export function useFileSyncerClient(codespaceData: ConnectedCodespaceData, remoteProvider?: RemoteProvider) {
  const fileSyncerRef = useRef<IFileSyncerClient | null>(null)
  const {codespaceInfo, codespaceState} = codespaceData

  /**
   * Create File Syncer client once codespace is ready
   */
  useEffect(() => {
    if (codespaceState !== 'ready' || !remoteProvider) {
      return
    }

    if (fileSyncerRef.current) {
      return
    }

    const createFileSyncerClientInner = async () => {
      try {
        fileSyncerRef.current = await createFileSyncerClient(remoteProvider)
      } catch {
        // TODO: consider adding retry logic in the future
      }
    }

    createFileSyncerClientInner()
  }, [codespaceInfo, codespaceState, remoteProvider])

  const getFileSyncerClient = useCallback(() => {
    return fileSyncerRef.current
  }, [fileSyncerRef])

  return {getFileSyncerClient}
}
