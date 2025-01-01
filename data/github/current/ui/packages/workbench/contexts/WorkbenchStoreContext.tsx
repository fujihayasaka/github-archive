import {useCopilotChatEntitlement} from '@github-ui/copilot-chat/utils/copilot-chat-entitlement'
import type {CopilotChatPayload} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {isFeatureEnabled} from '@github-ui/feature-flags'
import {useAppPayload} from '@github-ui/react-core/use-app-payload'
import {useQuery} from '@github-ui/react-query'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'
import React, {useContext, useMemo, useReducer} from 'react'

import {useStableCallback} from '../hooks/use-stable-callback'
import type {TCodespaceState} from '../types/codespace-types'
import {
  CodespaceStatus,
  type ConnectionEvent,
  type Entitlements,
  type ErrorEvent,
  initialState,
  Service,
  Status,
  type StatusEvent,
  workbenchStoreReducer,
  type WorkbenchStoreState,
} from '../utilities/workbench-store-reducer'

export {
  AcaStatus,
  AgentStatus,
  CodespaceStatus,
  CopilotLicenseType,
  CopilotPlan,
  initialState,
  Service,
  Status,
} from '../utilities/workbench-store-reducer'

const mapCodespaceStatus = (status: TCodespaceState): CodespaceStatus => {
  let mappedStatus: CodespaceStatus = CodespaceStatus.DISCONNECTED
  switch (status) {
    case 'none': {
      mappedStatus = Status.DISCONNECTED
      break
    }
    case 'creating':
    case 'starting': {
      mappedStatus = CodespaceStatus.STARTING
      break
    }
    case 'failed': {
      mappedStatus = Status.ERROR
      break
    }
    case 'ready': {
      mappedStatus = Status.CONNECTED
      break
    }
  }
  return mappedStatus
}

export type WorkbenchStoreContext = WorkbenchStoreState & {
  hasServiceErrors: boolean
  setReadOnly: (readOnly: boolean) => void
  onError(event: ErrorEvent): void
  onConnected(event: ConnectionEvent): void
  onDisconnected(event: ConnectionEvent): void
  onIdle(event: ConnectionEvent): void
  onStatus(event: StatusEvent): void
  onCodespaceStatus(event: TCodespaceState): void
  onSuccess(event: ConnectionEvent): void
  reloadQuota(): void
}

export const WorkbenchStoreContext = React.createContext<WorkbenchStoreContext | undefined>(undefined)

export function WorkbenchStoreProvider({children}: React.PropsWithChildren) {
  const [state, dispatch] = useReducer(workbenchStoreReducer, initialState)
  const {licenseType, plan} = useAppPayload<CopilotChatPayload>()

  const [, reloadQuota] = useCopilotChatEntitlement(licenseType, plan)

  const {data: entitlement} = useQuery<Entitlements>({
    queryKey: ['spark', 'entitlement'],
    queryFn: async () => {
      const response = await verifiedFetchJSON('/spark/entitlement')

      if (!response.ok) {
        throw new Error(`Failed to retrieve entitlements (${response.status} on ${response.url})`)
      }

      return (await response.json()) as Entitlements
    },
    placeholderData: initialState.entitlement,
    staleTime: 1000 * 60 * 5, // 5 minutes
    refetchOnWindowFocus: 'always',
  })

  const setReadOnly = useStableCallback((readOnly: boolean) => {
    dispatch({type: readOnly ? 'LOCK_READS' : 'UNLOCK_READS'})
  })

  const onError = useStableCallback((event: ErrorEvent) => {
    dispatch({type: 'ERROR', payload: event})
  })

  const onConnected = useStableCallback((event: ConnectionEvent) => {
    dispatch({type: 'CONNECTED', payload: event})
  })

  const onDisconnected = useStableCallback((event: ConnectionEvent) => {
    dispatch({type: 'DISCONNECTED', payload: event})
  })

  const onIdle = useStableCallback((event: ConnectionEvent) => {
    dispatch({type: 'IDLE', payload: event})
  })

  const onStatus = useStableCallback((event: StatusEvent) => {
    dispatch({type: 'STATUS', payload: event})
  })

  const onCodespaceStatus = useStableCallback((event: TCodespaceState) => {
    dispatch({
      type: 'STATUS',
      payload: {
        service: Service.CODESPACE,
        status: mapCodespaceStatus(event),
      },
    })
  })

  const onSuccess = useStableCallback((event: ConnectionEvent) => {
    dispatch({type: 'CONNECTED', payload: event})
    dispatch({type: 'CLEAR_ERRORS', payload: event.service})
  })

  // do quota checks and other global readOnly stuff here later
  const readOnly = isFeatureEnabled('workbench_store_readonly') ? state.readOnly : false // || copilot.quotaExceeded || codespace.concurrencyLimitExceeded || etc

  const hasServiceErrors = useMemo(() => {
    return Object.values(state.status).some(s => s === Status.ERROR)
  }, [state.status])

  const value = useMemo<WorkbenchStoreContext>(
    () => ({
      ...state,
      hasServiceErrors,
      entitlement: entitlement ?? state.entitlement,
      readOnly,
      setReadOnly,
      onError,
      onConnected,
      onDisconnected,
      onIdle,
      onStatus,
      onCodespaceStatus,
      onSuccess,
      reloadQuota,
    }),
    [
      state,
      hasServiceErrors,
      entitlement,
      readOnly,
      setReadOnly,
      onError,
      onConnected,
      onDisconnected,
      onIdle,
      onStatus,
      onCodespaceStatus,
      onSuccess,
      reloadQuota,
    ],
  )
  return <WorkbenchStoreContext.Provider value={value}>{children}</WorkbenchStoreContext.Provider>
}

export function useWorkbenchStore() {
  const context = useContext(WorkbenchStoreContext)
  if (!context) {
    throw new Error('useWorkbenchStore must be used within a WorkbenchStoreProvider')
  }
  return context
}

export function useGlobalReadOnly(): boolean {
  const {readOnly} = useWorkbenchStore()
  const value = useMemo(() => readOnly, [readOnly])
  return value
}
