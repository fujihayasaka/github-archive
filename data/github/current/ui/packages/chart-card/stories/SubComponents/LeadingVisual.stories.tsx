import type {Meta, StoryObj} from '@storybook/react'

import LeadingVisualComponent, {type LeadingVisualProps} from '../../ChartCard/LeadingVisual'
import {GitHubAvatar} from '@github-ui/github-avatar'

const meta: Meta<typeof LeadingVisualComponent> = {
  title: 'Recipes/ChartCard/SubComponents/LeadingVisual',
  component: LeadingVisualComponent,
}

export default meta

export const LeadingVisual: StoryObj<LeadingVisualProps> = {
  args: {
    children: <GitHubAvatar src="https://avatars.githubusercontent.com/u/90379286?s=60&amp;v=4" size={40} />,
  },
  render: (args: LeadingVisualProps) => <LeadingVisualComponent>{args.children}</LeadingVisualComponent>,
}
LeadingVisual.storyName = 'LeadingVisual'
