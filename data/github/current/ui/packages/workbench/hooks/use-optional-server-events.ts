import {createContext, useContext} from 'react'

import type {ServerEventsContextType} from '../contexts/ServerEventsContext'
import {ConnectionStatus, ServerEventsContext} from '../contexts/ServerEventsContext'

const DEFAULT: ServerEventsContextType = {
  isServerConnected: false,
  connectionStatus: ConnectionStatus.CONNECTED,
  events: [],
  fetchFromCodespaceApi: async () => new Response(),
  errors: [],
  reconnect: () => {},
}

// fallback Context so that useContext never sees `undefined`
const FallbackServerEventsContext = createContext<ServerEventsContextType>(DEFAULT)

export function useOptionalServerEvents(): ServerEventsContextType {
  // pick the real Context if it exists, otherwise our fallback
  const Ctx = ServerEventsContext ?? FallbackServerEventsContext
  const ctx = useContext(Ctx)
  return ctx ?? DEFAULT
}
