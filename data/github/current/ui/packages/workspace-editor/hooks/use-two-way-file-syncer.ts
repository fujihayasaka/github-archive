import type {RemoteProvider} from '@github/codespaces-lsp'
import {JSONRPCServer, type TypedJSONRPCServer} from 'json-rpc-2.0'
import {useCallback, useEffect, useMemo, useRef, useState} from 'react'

import {TunnelProtocol} from '../../../../node_modules/@microsoft/dev-tunnels-contracts/tunnelProtocol'
import {useFilesContext} from '../contexts/FilesContext'
import type {
  FileSyncerStatus,
  IFileSyncerBridge,
  PushableDiffs,
  RpcMethods,
  SerializedDiffs,
} from '../utilities/file-syncer-types'
import type {ConnectedCodespaceData} from '../utilities/workspace-editor-types'

export function useTwoWayFileSyncer(codespace: ConnectedCodespaceData, twoWayFileSyncerEnabled: boolean) {
  const [lastCodespacePush, setLastCodespacePush] = useState(0)
  const fileSyncerStarted = useRef<boolean>(false)
  const {storeDiffs, retrieveDiffs} = useFilesContext()

  const bridge = useMemo<IFileSyncerBridge>(() => {
    return {
      async pushDiffs(_sessionId: string, pushableDiffs: PushableDiffs): Promise<number> {
        const storedDiffs = await storeDiffs(pushableDiffs)
        return storedDiffs.latestTimestamp
      },
      getDiffs(_sessionId: string): Promise<SerializedDiffs> {
        return Promise.resolve(retrieveDiffs())
      },
      reportStatus(status: FileSyncerStatus): Promise<void> {
        // eslint-disable-next-line no-console
        console.log(
          `Received status report from ${status.codespaceName}: ${status.status}, error if any: ${status.failureKinds}`,
        )
        return Promise.resolve()
      },
      getTimestamp(): Promise<number> {
        return Promise.resolve(retrieveDiffs().latestTimestamp)
      },
    }
  }, [retrieveDiffs, storeDiffs])

  const startFileSyncer = useCallback(
    async (remoteProvider: RemoteProvider) => {
      if (!twoWayFileSyncerEnabled) {
        return
      }

      const server: TypedJSONRPCServer<RpcMethods> = new JSONRPCServer()

      server.addMethod('pushDiffs', async ({sessionId, pushableDiffs}) => {
        const ts = await bridge.pushDiffs(sessionId, pushableDiffs)

        // Update the last push time.
        // This will cause the editor to re-render with the latest changes from codespace.
        setLastCodespacePush(ts)
        return ts
      })

      server.addMethod('getDiffs', ({sessionId}) => {
        return bridge.getDiffs(sessionId)
      })

      server.addMethod('reportStatus', ({status}) => {
        return bridge.reportStatus(status)
      })

      server.addMethod('getTimestamp', () => {
        return bridge.getTimestamp()
      })

      const stream = await remoteProvider.getStreamFromPort(33334, TunnelProtocol.Http)

      // Read from stdin and write to stdout
      stream.on('data', async data => {
        try {
          const request = JSON.parse(data.toString())
          const response = await server.receive(request)
          if (response) {
            stream.write(`${JSON.stringify(response)}\n`)
          }
        } catch (error) {
          // eslint-disable-next-line no-console
          console.error('Failed to parse JSON-RPC request', error)
        }
      })
    },
    [bridge, twoWayFileSyncerEnabled],
  )

  useEffect(() => {
    if (fileSyncerStarted.current) {
      return
    }

    if (twoWayFileSyncerEnabled && codespace.remoteProvider && codespace.codespaceState === 'ready') {
      startFileSyncer(codespace.remoteProvider)
      fileSyncerStarted.current = true
    }
  }, [
    codespace.codespaceState,
    codespace.remoteProvider,
    startFileSyncer,
    twoWayFileSyncerEnabled,
    fileSyncerStarted,
    lastCodespacePush,
  ])
}
