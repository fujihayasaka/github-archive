import type {Meta, StoryObj} from '@storybook/react'
import {ModelSuggestionMenu} from './ModelSuggestionMenu'
import {parametersConfig} from '../../../utils/story-utils'
import {mockModel} from '../__tests__/mocks'
import {mockShowModelPayload} from '../../show/components/__tests__/mocks'
import {storyWrapper} from '@github-ui/react-core/test-utils'

type StoryArgs = typeof ModelSuggestionMenu

const meta = {
  title: 'Apps/GitHub Models/ModelSuggestionMenu',
  component: ModelSuggestionMenu,
  args: {
    task: 'text',
    suggestedModels: [mockModel],
  },
  parameters: parametersConfig,
  decorators: [
    storyWrapper({
      routePayload: mockShowModelPayload(),
    }),
  ],
} satisfies Meta<StoryArgs>

export default meta

type Story = StoryObj<StoryArgs>

export const Example: Story = {
  render: args => (
    <ul>
      <ModelSuggestionMenu {...args} />
    </ul>
  ),
}
