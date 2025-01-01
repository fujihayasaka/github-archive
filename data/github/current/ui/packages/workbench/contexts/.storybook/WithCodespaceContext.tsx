import {useMemo} from 'react'
import type {Decorator} from '@storybook/react'

import type {ConnectedCodespaceData} from '@github-ui/workspace-editor/utilities/workspace-editor-types'
import {CodespaceContext} from '../CodespaceContext'

const TUNNEL_PROPS = {
  tunnelId: 'tunnel id',
  clusterId: 'cluster id',
  connectAccessToken: 'connect access token',
  managePortsAccessToken: 'ports access token',
  serviceUri: 'service uri',
  domain: 'domain',
}

export const withCodespaceContext: Decorator = (Story, {args}) => {
  const contextValue = useMemo(
    () =>
      ({
        codespaceData: {
          codespaceInfo: {
            cloud_environment: {
              guid: '1234-5678-9012-3456',
            },
            environment_data: {
              state: args.codespaceState,
              connection: {
                sessionPath: '/path/to/session',
                tunnelProperties: TUNNEL_PROPS,
              },
              friendlyName: 'MyCodespace',
              skuDisplayName: 'Standard',
              skuName: 'standard',
              location: 'us-west',
              features: {
                feature1: 'enabled',
                feature2: 'disabled',
              },
              devcontainer_path: '/path/to/devcontainer',
            },
          },
          codespaceState: args.codespaceState,
          workspaceRoot: '/root',
          isRecoveryContainer: false,
          permissionsStatus: {
            accepted: true,
          },
          creationErrorMessage: undefined,
          remoteProvider: {
            tunnelProps: TUNNEL_PROPS,
          } as ConnectedCodespaceData['remoteProvider'],
          recreateCodespace: () => {},
          pollForPermissionsAccepted: () => {},
        },
      }) as CodespaceContext,
    [args.codespaceState],
  )

  return (
    <CodespaceContext.Provider value={contextValue}>
      <Story />
    </CodespaceContext.Provider>
  )
}

export const codespaceContextDecoratorArgTypes = {
  codespaceData: {table: {disable: true}},
  codespaceState: {
    control: 'select',
    description: 'Current state of the codespace',
    options: ['ready', 'failed', 'initializing', 'recreating', 'recovery'],
    table: {
      category: 'CodespaceContext',
    },
  },
}

export const codespaceContextDecoratorArgs = {
  codespaceState: 'ready',
}
