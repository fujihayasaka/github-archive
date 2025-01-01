import type {Meta, StoryObj} from '@storybook/react'
import {ManageSeatsPaymentMethod} from './ManageSeatsPaymentMethod'
import {NavigationContextProvider} from '../contexts/NavigationContext'
import {getPaymentMethod} from '../test-utils/mock-data'

const meta = {
  title: 'Apps/LicensingCommon/ManageSeatsPaymentMethod',
  component: ManageSeatsPaymentMethod,
  args: {
    paymentMethod: getPaymentMethod(),
  },
  decorators: [
    Story => (
      <NavigationContextProvider enterpriseContactUrl="" isStafftools={false} slug={'test-slug'}>
        <Story />
      </NavigationContextProvider>
    ),
  ],
} satisfies Meta<typeof ManageSeatsPaymentMethod>

export default meta

type Story = StoryObj<typeof ManageSeatsPaymentMethod>

export const Default: Story = {}
