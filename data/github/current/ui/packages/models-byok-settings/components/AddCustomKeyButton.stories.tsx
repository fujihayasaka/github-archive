import type {Meta, StoryObj} from '@storybook/react'

import {CurrentOrgProvider} from '../contexts/CurrentOrgContext'
import {PageBannerOutlet} from '../contexts/PageBannerContext'
import {customModelsIndexRouteHandlers, getMockPublicKey} from '../test-utils/mocks'
import {AddCustomKeyButton} from './AddCustomKeyButton'

export default {
  title: 'Apps/Models BYOK settings/Components/AddCustomKeyButton',
  component: AddCustomKeyButton,
  decorators: [
    Story => (
      <CurrentOrgProvider value="my-org">
        <div id="js-flash-container" />
        <Story />
        <PageBannerOutlet />
      </CurrentOrgProvider>
    ),
  ],
  parameters: {
    msw: {
      handlers: customModelsIndexRouteHandlers,
    },
  },
  args: {
    publicKey: getMockPublicKey(),
  },
} satisfies Meta<typeof AddCustomKeyButton>

type Story = StoryObj<typeof AddCustomKeyButton>

export const Default: Story = {}
