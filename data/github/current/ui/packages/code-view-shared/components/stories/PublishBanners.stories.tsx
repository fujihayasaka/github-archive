import type {Meta, StoryObj} from '@storybook/react'

import PublishBanners from '../PublishBanners'

const meta = {
  title: 'Apps/Code View Shared/PublishBanners',
  component: PublishBanners,
  args: {
    dismissActionNoticePath: '/dissmiss/path',
    showPublishActionBanner: true,
    releasePath: '/test/path',
  },
  parameters: {
    controls: {expanded: true, sort: 'alpha'},
  },
} satisfies Meta<typeof PublishBanners>

export default meta

type Story = StoryObj<typeof PublishBanners>

export const Default: Story = {}
