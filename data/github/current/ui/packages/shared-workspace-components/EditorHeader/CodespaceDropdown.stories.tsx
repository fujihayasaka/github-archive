import {noop} from '@github-ui/noop'
import {CodespaceDropdown} from './CodespaceDropdown'
import type {Meta} from '@storybook/react'

const meta: Meta = {
  title: 'Recipes/CodespaceDropdown',
  component: CodespaceDropdown,
  args: {
    codespaceFriendlyName: 'test-friendly-goldfish',
    codespaceAllowUrl: 'https://test-codespace-allow-url',
    codespacePermissionAccepted: false,
    isCodespaceRecoveryContainer: false,
    pollForCodespacePermissionsAccepted: noop,
    recreateCodespace: noop,
    onDetailsClick: noop,
  },
}

export default meta

export const Example = {}
