import type {Meta, StoryObj} from '@storybook/react'

import {ConsentExperience} from './ConsentExperience'

const meta: Meta<typeof ConsentExperience> = {
  title: 'Mkt/Swp/ConsentExperience',
  component: ConsentExperience,
}

export default meta

type Story = StoryObj<typeof ConsentExperience>

export const Default: Story = {
  render: () => {
    return <ConsentExperience />
  },
}
