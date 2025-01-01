import {action} from '@storybook/addon-actions'
import type {Decorator} from '@storybook/react'

import {WorkbenchPreviewContext} from '../WorkbenchPreviewContext'
import type {WorkbenchPreviewContextType} from '../WorkbenchPreviewContext'

export const withWorkbenchPreviewContext: Decorator = (Story, {args}) => {
  const contextValue = {
    state: {
      frameContentLoaded: args.frameContentLoaded as boolean,
      pingReceived: args.pingReceived as boolean,
      errorReceived: args.errorReceived as boolean,
      viteWsConnected: args.viteWsConnected as boolean,
      viteServerReady: args.viteServerReady as boolean,
      viteServerConnectionTimedOut: args.viteServerConnectionTimedOut as boolean,
      viteError: args.viteError as boolean,
      viteUpdated: args.viteUpdated as boolean,
      rootElementEmpty: args.rootElementEmpty as boolean
    },
    errorQueue: [],
    runtimeErrors: [],
    onIFrameLoaded: action('onIFrameLoaded'),
    addEmptyAppError: action('addEmptyAppError'),
    removeEmptyAppError: action('removeEmptyAppError'),
  } satisfies Partial<WorkbenchPreviewContextType>

  return (
    <WorkbenchPreviewContext.Provider value={contextValue}>
      <Story />
    </WorkbenchPreviewContext.Provider>
  )
}

export const WorkbenchPreviewDecoratorArgTypes = {
  frameContentLoaded: {
    control: 'boolean',
    description: 'Whether the frame content has loaded',
    table: {
      category: 'WorkbenchPreviewContext',
    },
  },
  pingReceived: {
    control: 'boolean',
    description: 'Whether a ping has been received from the preview',
    table: {
      category: 'WorkbenchPreviewContext',
    },
  },
  errorReceived: {
    control: 'boolean',
    description: 'Whether an error has been received from the preview',
    table: {
      category: 'WorkbenchPreviewContext',
    },
  },
  viteWsConnected: {
    control: 'boolean',
    description: 'Whether the Vite WebSocket connection is established',
    table: {
      category: 'WorkbenchPreviewContext',
    },
  },
  viteServerReady: {
    control: 'boolean',
    description: 'Whether the Vite server is ready',
    table: {
      category: 'WorkbenchPreviewContext',
    },
  },
  viteServerConnectionTimedOut: {
    control: 'boolean',
    description: 'Whether the Vite server connection timed out',
    table: {
      category: 'WorkbenchPreviewContext',
    },
  },
  viteError: {
    control: 'boolean',
    description: 'Whether there is a Vite error',
    table: {
      category: 'WorkbenchPreviewContext',
    },
  },
  viteUpdated: {
    control: 'boolean',
    description: 'Whether the Vite server has been updated',
    table: {
      category: 'WorkbenchPreviewContext',
    },
  },
  rootElementEmpty: {
    control: 'boolean',
    description: 'Whether the root element is empty in the preview',
    table: {
      category: 'WorkbenchPreviewContext',
    },
  },
}

export const WorkbenchPreviewDecoratorArgs = {
  frameContentLoaded: true,
  pingReceived: true,
  errorReceived: false,
  viteWsConnected: true,
  viteServerReady: true,
  viteServerConnectionTimedOut: false,
  viteError: false,
  viteUpdated: false,
  rootElementEmpty: false,
}
