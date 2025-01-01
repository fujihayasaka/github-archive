import '@primer/react-brand/lib/css/main.css'

import type {Meta, StoryObj} from '@storybook/react'

import {ContentfulLabel} from './ContentfulLabel'

const meta: Meta<typeof ContentfulLabel> = {
  title: 'Mkt/Swp/Contentful/ContentfulLabel',
  component: ContentfulLabel,
}

export default meta

type Story = StoryObj<typeof ContentfulLabel>

export const Default: Story = {
  args: {
    component: {
      sys: {
        contentType: {
          sys: {
            id: 'primerComponentLabel',
          },
        },
        id: 'primer-label',
      },
      fields: {
        text: 'Hello World',
        size: 'medium',
        color: 'default',
      },
    },
  },
}

export const LargeWithIcon: Story = {
  args: {
    component: {
      sys: {
        contentType: {
          sys: {
            id: 'primerComponentLabel',
          },
        },
        id: 'primer-label',
      },
      fields: {
        text: 'Github Copilot',
        size: 'large',
        color: 'purple',
        icon: 'star',
      },
    },
  },
}
