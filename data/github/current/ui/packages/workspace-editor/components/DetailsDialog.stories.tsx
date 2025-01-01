import type {Meta, StoryObj} from '@storybook/react'

import type {ConnectedCodespaceData} from '../utilities/workspace-editor-types'
import {DetailsDialog} from './DetailsDialog'

const mockCodespaceData: ConnectedCodespaceData = {
  isRecoveryContainer: false,
  creationErrorMessage: 'Failed to provision resources for the codespace.',
  recreateCodespace: () => {},
  remoteProvider: undefined,
  codespaceInfo: null,
  codespaceState: 'failed',
  workspaceRoot: '/workspace',
  pollForPermissionsAccepted: () => {},
}

const meta: Meta<typeof DetailsDialog> = {
  title: 'Apps/Workspace Editor/Components/DetailsDialog',
  component: DetailsDialog,
  parameters: {
    docs: {
      description: {
        component: 'Dialog that displays details about codespace creation errors.',
      },
    },
  },
  args: {
    detailsDialogVisibility: 'visible',
    onDetailsClick: () => {},
    codespaceData: mockCodespaceData,
  },
  argTypes: {
    detailsDialogVisibility: {
      control: 'radio',
      options: ['visible', 'hidden'],
      description: 'Controls the visibility of the dialog',
    },
    onDetailsClick: {
      action: 'clicked',
      description: 'Callback when the dialog is closed',
    },
    codespaceData: {
      control: 'object',
      description: 'Data related to the codespace',
    },
  },
}

export default meta

type Story = StoryObj<typeof DetailsDialog>

export const Default: Story = {
  name: 'Details Dialog',
  args: {},
}
