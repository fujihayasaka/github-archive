import type {Meta, StoryObj} from '@storybook/react'

import {ConsentExperienceControl} from './ConsentExperienceControl'

const meta: Meta<typeof ConsentExperienceControl> = {
  title: 'Mkt/Swp/ConsentExperienceControl',
  component: ConsentExperienceControl,
}

export default meta

type Story = StoryObj<typeof ConsentExperienceControl>

export const Default: Story = {
  render: () => {
    return <ConsentExperienceControl />
  },
}
