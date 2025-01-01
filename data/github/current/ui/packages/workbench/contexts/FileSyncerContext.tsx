import type {RemoteProvider} from '@github/codespaces-ssh-tunneling'
import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {useWorkspaceEditorUIDispatch} from '@github-ui/workspace-editor/contexts/WorkspaceEditorUIContext'
import {AggregateError} from '@github-ui/workspace-editor/errors/aggregate-error'
import {withRetries} from '@github-ui/workspace-editor/utilities/with-retries'
import {BannerType} from '@github-ui/workspace-editor/utilities/workspace-editor-types'
import {TunnelProtocol} from '@microsoft/dev-tunnels-contracts'
import {JSONRPCClient, JSONRPCServer, JSONRPCServerAndClient, type TypedJSONRPCServerAndClient} from 'json-rpc-2.0'
import {
  createContext,
  type PropsWithChildren,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
} from 'react'

import {useAnalytics} from '../telemetry/use-analytics'
import type {ClientRpcMethods, FileChange, IFileSyncer, ServerRpcMethods} from '../types/file-syncer-v2-types'
import type {FileDescription} from '../types/spark-history-types'
import type {WorkbenchRoutePayload} from '../types/workbench-types'
import {useCodespaceContext} from './CodespaceContext'
import {AzureBlobFileSyncerClient} from './fileSyncer/AzureBlobFileSyncerClient'
import {CodespaceFileSyncerClient} from './fileSyncer/CodespaceFileSyncerClient'
import {Service, useWorkbenchStore} from './WorkbenchStoreContext'

// We can't pull in the Node type that this is actually shaped like
// Just stub in what we use to keep the TS happy...
type OurDuplex = {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  write(chunk: any, cb?: (error: Error | null | undefined) => void): boolean
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  on(event: string | symbol, listener: (...args: any[]) => void): OurDuplex
}

type FileSyncerMode = 'blobStorage' | 'codespace'

export type FileSyncerContextData = {
  contentStateStamp: number
  fileSyncerStarted: boolean
  fileTreeStateStamp: number
  lastEditStateStamp: number
  notifyEdited: () => void
  forceContentRefresh: () => void
  forceFileTreeRefresh: () => void
  getFileSyncerV2: () => IFileSyncer | null
  syncerMode: FileSyncerMode
  setSyncerMode: (mode: FileSyncerMode) => void
  fileContentsRef: React.MutableRefObject<{[key: string]: FileDescription} | null>
  fileChangeStack: FileChange[]
  setFileChangeStack: React.Dispatch<React.SetStateAction<FileChange[]>>
  setFilesContentsRef: (files: {[key: string]: FileDescription} | null) => void
}

export const FileSyncerContext = createContext<FileSyncerContextData | undefined>(undefined)

export function FileSyncerContextProvider({children}: PropsWithChildren) {
  const {codespaceData: codespace} = useCodespaceContext()
  const sessionSnapshotEnabled = useFeatureFlag('copilot_workbench_session_snapshot')
  const {onConnected, onDisconnected} = useWorkbenchStore()
  const dispatch = useWorkspaceEditorUIDispatch()
  const sendEvent = useAnalytics()

  const [fileSyncerStarted, setFileSyncerStarted] = useState<boolean>(false)

  // These state variables are a little nuanced
  // contentStateStamp is used to communicate to the editor that it should re-render
  // fileTreeStateStamp is used for communicating overall file tree changes that should refresh
  // lastEditStateStamp notices file edits, but doesn't touch editor. It's for all other readers.
  const [contentStateStamp, setContentStateStamp] = useState(-1)
  const [fileTreeStateStamp, setFileTreeStateStamp] = useState(-1)
  const [lastEditStateStamp, setLastEditStateStamp] = useState(-1)
  const [fileChangeStack, setFileChangeStack] = useState<FileChange[]>([])
  const fileSyncerRef = useRef<IFileSyncer | null>(null)
  const fileContentsRef = useRef<{[key: string]: FileDescription} | null>(null)

  const getFileSyncerV2 = useCallback(() => {
    return fileSyncerRef.current
  }, [fileSyncerRef])

  const setFilesContentsRef = useCallback((files: {[key: string]: FileDescription} | null) => {
    fileContentsRef.current = files
  }, [])

  const [syncerMode, setSyncerMode] = useState<FileSyncerMode>(sessionSnapshotEnabled ? 'blobStorage' : 'codespace')

  const {snapshotUploadUri} = useRoutePayload<WorkbenchRoutePayload>()

  // Update a state property to force a re-render to the editor
  const forceContentRefresh = useCallback(() => {
    setContentStateStamp(Date.now())
  }, [])

  // Update a state property to force a re-render to the file tree
  const forceFileTreeRefresh = useCallback(() => {
    setFileTreeStateStamp(Date.now())
  }, [])

  // Update a state property to notify non-editor file readers of changes
  const notifyEdited = useCallback(() => {
    setLastEditStateStamp(Date.now())
  }, [])

  const startFileSyncer = useCallback(async (remoteProvider: RemoteProvider) => {
    const connection: OurDuplex = await withRetries(
      async () => {
        return await remoteProvider.getStreamFromPort(13000, TunnelProtocol.Http)
      },
      {
        retries: 12,
        retryDelayMs: 5000,
      },
    )

    const client = new JSONRPCClient(request => {
      try {
        // Send the request to the server
        const requestMessage = `${JSON.stringify(request)}\n`
        // console.log(`FileSyncer:: Sending content '${requestMessage}'`)
        connection.write(requestMessage)
        return Promise.resolve()
      } catch (error) {
        return Promise.reject(error)
      }
    })

    const fileSyncer = new CodespaceFileSyncerClient(client)
    const server = new JSONRPCServer()
    server.addMethod('notifyFileChanged', (rawChanges: FileChange[]) => {
      const changes: FileChange[] = rawChanges.map(change => {
        return {
          ...change,
          path: change.path.replace(/^\/workspaces\/[a-zA-Z0-9_-]+/, ''),
        } as FileChange
      })

      notifyEdited()
      forceFileTreeRefresh()
      setFileChangeStack(prevStack => {
        const newChanges = changes.filter(change => !prevStack.some(existing => existing.path === change.path))
        return [...prevStack, ...newChanges]
      })
    })

    const serverAndClient: TypedJSONRPCServerAndClient<ClientRpcMethods, ServerRpcMethods> = new JSONRPCServerAndClient(
      server,
      client,
    )

    let buffer = ''
    connection.on('data', data => {
      try {
        buffer += data.toString()
        // Split by newline and process each complete message
        const messages = buffer.split('\n')
        // Keep the last potentially incomplete message in the buffer
        buffer = messages.pop() || ''

        for (const message of messages) {
          if (message.trim()) {
            // Skip empty messages
            // eslint-disable-next-line no-console
            console.log(`FileSyncer:: Received message '${message}'`)
            const jsonData = JSON.parse(message)
            serverAndClient.receiveAndSend(jsonData)
          }
        }
      } catch (error) {
        // eslint-disable-next-line no-console
        console.log(`FileSyncer:: Error processing data: ${error}`)
      }
    })

    // On close, make sure to reject all the pending requests to prevent hanging.
    connection.on('close', () => {
      // eslint-disable-next-line no-console
      console.log('Connection closed')
      serverAndClient.rejectAllPendingRequests('Connection is closed')
      setFileSyncerStarted(false)
      onDisconnected({service: Service.FILE_SYNCER})
    })

    return fileSyncer

    // eslint-disable-next-line react-hooks/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  useEffect(() => {
    async function run() {
      if (syncerMode === 'blobStorage' && snapshotUploadUri && sessionSnapshotEnabled) {
        // Cut over to Codespaces file syncer if it's ready to use
        if (codespace?.codespaceState === 'ready') {
          await startCodespaceSyncerMode()
        } else {
          const blobSyncer = new AzureBlobFileSyncerClient(snapshotUploadUri)
          const hasContent = await blobSyncer.hasContent()
          if (!hasContent) {
            return
          }

          fileSyncerRef.current = blobSyncer
          setFileSyncerStarted(true)
          onConnected({service: Service.FILE_SYNCER})
        }
      } else if (!fileSyncerStarted && codespace?.codespaceState === 'ready') {
        await startCodespaceSyncerMode()
      }
    }

    async function startCodespaceSyncerMode() {
      if (codespace.remoteProvider) {
        try {
          fileSyncerRef.current = await startFileSyncer(codespace.remoteProvider)
          setSyncerMode('codespace')
          forceFileTreeRefresh()
          forceContentRefresh()
          setFileSyncerStarted(true)
          onConnected({service: Service.FILE_SYNCER})
        } catch (error) {
          if (error instanceof AggregateError) {
            sendEvent('file_syncer.connection_reload_banner.displayed', {
              timestamp: new Date().toISOString(),
              errorMessage: error?.message,
            })

            dispatch({type: 'SET_BANNER', banner: BannerType.CONNECTION_RELOAD})
          } else {
            throw error
          }
        }
      }
    }

    run()
  }, [
    codespace?.codespaceState,
    codespace.remoteProvider,
    startFileSyncer,
    fileSyncerStarted,
    syncerMode,
    snapshotUploadUri,
    sessionSnapshotEnabled,
    onConnected,
    onDisconnected,
    dispatch,
    forceFileTreeRefresh,
    forceContentRefresh,
    sendEvent,
  ])

  const value = useMemo(() => {
    return {
      contentStateStamp,
      fileSyncerStarted,
      fileTreeStateStamp,
      lastEditStateStamp,
      notifyEdited,
      forceContentRefresh,
      forceFileTreeRefresh,
      getFileSyncerV2,
      syncerMode,
      setSyncerMode,
      fileContentsRef,
      fileChangeStack,
      setFileChangeStack,
      setFilesContentsRef,
    }
  }, [
    contentStateStamp,
    fileSyncerStarted,
    fileTreeStateStamp,
    lastEditStateStamp,
    notifyEdited,
    forceContentRefresh,
    forceFileTreeRefresh,
    getFileSyncerV2,
    syncerMode,
    fileChangeStack,
    setFileChangeStack,
    setFilesContentsRef,
  ])

  return <FileSyncerContext.Provider value={value}>{children}</FileSyncerContext.Provider>
}

export function useFileSyncerContext() {
  const context = useContext(FileSyncerContext)
  if (!context) {
    throw new Error('useFileSyncerContext must be used within an FileSyncerContextProvider')
  }
  return context
}
