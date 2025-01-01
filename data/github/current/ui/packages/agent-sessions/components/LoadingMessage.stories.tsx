import type {Meta} from '@storybook/react'
import {LoadingMessage, BootingUpMessage} from './LoadingMessage'

const loadingMessageMeta = {
  title: 'Apps/Copilot Coding Agent/LoadingMessage',
  component: LoadingMessage,
  parameters: {
    controls: {expanded: true},
  },
  argTypes: {
    message: {
      control: 'text',
      defaultValue: 'Loading…',
    },
  },
} satisfies Meta<typeof LoadingMessage>

export default loadingMessageMeta

export const Default = {
  name: 'LoadingMessage - Default',
  args: {
    message: 'Loading…',
  },
}

export const CustomMessage = {
  name: 'LoadingMessage - Custom Message',
  args: {
    message: 'Copilot is working…',
  },
}

const bootingUpMeta = {
  title: 'Apps/Copilot Coding Agent/BootingUpMessage',
  component: BootingUpMessage,
  parameters: {
    controls: {expanded: true},
  },
} satisfies Meta<typeof BootingUpMessage>

export const BootingUp = {
  name: 'BootingUpMessage - Rotating Messages',
  meta: bootingUpMeta,
  render: () => <BootingUpMessage />,
}
