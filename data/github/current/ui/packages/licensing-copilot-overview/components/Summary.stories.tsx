import type {Meta, StoryObj} from '@storybook/react'
import {NavigationContextProvider} from '@github-ui/licensing-common/contexts/NavigationContext'
import {Summary} from './Summary'
import {getSummaryProps} from '../test-utils/mock-data'
import {MemoryRouter} from 'react-router-dom'

const meta = {
  title: 'Apps/Licensing/Copilot/Summary',
  component: Summary,
  args: getSummaryProps(),
} satisfies Meta<typeof Summary>

export default meta

type Story = StoryObj<typeof Summary>

export const Default: Story = {
  name: 'Default',
  render: args => (
    <MemoryRouter future={{v7_relativeSplatPath: true, v7_startTransition: true}}>
      <Summary {...args} />
    </MemoryRouter>
  ),
}

export const NoCopilot: Story = {
  name: 'No Copilot',
  render: args => (
    <MemoryRouter future={{v7_relativeSplatPath: true, v7_startTransition: true}}>
      <Summary {...args} />
    </MemoryRouter>
  ),
  args: {
    isCopilotEnabled: false,
  },
}

export const NoCopilotStafftools: Story = {
  name: 'No Copilot in Stafftools',
  render: args => (
    <MemoryRouter future={{v7_relativeSplatPath: true, v7_startTransition: true}}>
      <NavigationContextProvider enterpriseContactUrl="https://example.com" isStafftools isTeams={false} slug="slug">
        <Summary {...args} />
      </NavigationContextProvider>
    </MemoryRouter>
  ),
  args: {
    isCopilotEnabled: false,
  },
}
