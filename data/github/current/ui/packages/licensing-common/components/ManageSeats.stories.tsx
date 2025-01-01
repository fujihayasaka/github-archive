import type {Meta, StoryObj} from '@storybook/react'
import {ManageSeats} from './ManageSeats'
import {NavigationContextProvider} from '../contexts/NavigationContext'
import {getPaymentMethod} from '../test-utils/mock-data'

const meta = {
  title: 'Apps/LicensingCommon/ManageSeats',
  component: ManageSeats,
  args: {
    analyticsEventCategory: 'test_category',
    currentPrice: '$0.00',
    isMonthlyPlan: true,
    isTrial: false,
    paymentMethod: getPaymentMethod(),
    onCancelClick: () => {},
    onSaveClick: () => {},
    licensesPurchased: 20,
    seatsConsumed: 10,
    seatsPath: '/billing/settings',
  },
  decorators: [
    Story => (
      <NavigationContextProvider enterpriseContactUrl="" isStafftools={false} slug={'test-slug'}>
        <Story />
      </NavigationContextProvider>
    ),
  ],
} satisfies Meta<typeof ManageSeats>

export default meta

type Story = StoryObj<typeof ManageSeats>

export const Default: Story = {}
