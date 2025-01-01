import type {Meta, StoryObj} from '@storybook/react'

import TrailingVisualComponent, {type TrailingVisualProps} from '../../ChartCard/TrailingVisual'
import {GitHubAvatar} from '@github-ui/github-avatar'

const meta: Meta<typeof TrailingVisualComponent> = {
  title: 'Recipes/ChartCard/SubComponents/TrailingVisual',
  component: TrailingVisualComponent,
}

export default meta

export const TrailingVisual: StoryObj<TrailingVisualProps> = {
  args: {
    children: <GitHubAvatar src="https://avatars.githubusercontent.com/u/90379286?s=60&amp;v=4" size={40} />,
  },
  render: (args: TrailingVisualProps) => <TrailingVisualComponent>{args.children}</TrailingVisualComponent>,
}
TrailingVisual.storyName = 'TrailingVisual'
