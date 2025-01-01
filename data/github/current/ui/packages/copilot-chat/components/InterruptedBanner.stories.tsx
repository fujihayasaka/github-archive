import type {Meta} from '@storybook/react'

import {InterruptedBanner} from './InterruptedBanner'

const meta = {
  title: 'Apps/Copilot/InterruptedBanner',
  component: InterruptedBanner,
  parameters: {},
  argTypes: {},
} satisfies Meta<typeof InterruptedBanner>

export default meta

export const Default = {
  render: () => {
    return (
      <div>
        <InterruptedBanner />
      </div>
    )
  },
}
