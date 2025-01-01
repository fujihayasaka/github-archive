import {action} from '@storybook/addon-actions'
import type {Decorator} from '@storybook/react'

import {ServerEventsContext, type ServerEventsContextType, ConnectionStatus} from '../ServerEventsContext'

export const withServerEventsContext: Decorator = (Story, {args}) => {
  const contextValue = {
    isServerConnected: args.isServerConnected as boolean,
    connectionStatus: args.connectionStatus as ConnectionStatus,
    events: [],
    fetchFromCodespaceApi: action('fetchFromCodespaceApi') as ServerEventsContextType['fetchFromCodespaceApi'],
    errors: [],
    reconnect: action('reconnect'),
  } satisfies ServerEventsContextType

  return (
    <ServerEventsContext.Provider value={contextValue}>
      <Story />
    </ServerEventsContext.Provider>
  )
}

export const ServerEventsContextDecoratorArgs = {
  isServerConnected: true,
  connectionStatus: ConnectionStatus.CONNECTED,
}

export const ServerEventsContextDecoratorArgTypes = {
  isServerConnected: {
    control: 'boolean',
    description: 'Is the server connected?',
    table: {
      category: 'ServerEventsContext',
    },
  },
  connectionStatus: {
    control: 'select',
    options: Object.values(ConnectionStatus),
    description: 'The status of the connection',
    table: {
      category: 'ServerEventsContext',
    },
  },
}
