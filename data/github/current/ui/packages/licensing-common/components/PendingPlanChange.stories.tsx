import type {Meta, StoryObj} from '@storybook/react'
import {NavigationContextProvider} from '../contexts/NavigationContext'
import {getPendingPlanChange} from '../test-utils/mock-data'
import {PendingPlanChange} from './PendingPlanChange'

const meta = {
  title: 'Apps/Licensing/Common/PendingPlanChange',
  component: PendingPlanChange,
  args: {
    pendingChange: getPendingPlanChange(),
    onCancelConfirmed: () => {},
  },
  decorators: [
    Story => (
      <NavigationContextProvider enterpriseContactUrl="" isTeams={false} isStafftools={false} slug={'test-slug'}>
        <Story />
      </NavigationContextProvider>
    ),
  ],
} satisfies Meta<typeof PendingPlanChange>

export default meta

type Story = StoryObj<typeof PendingPlanChange>

export const Default: Story = {}
