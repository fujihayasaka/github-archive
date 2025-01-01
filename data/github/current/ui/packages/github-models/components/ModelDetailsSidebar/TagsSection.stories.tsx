import type {Meta, StoryObj} from '@storybook/react'
import {TagsSection} from './TagsSection'
import type {Labels} from '../../routes/playground/components/types'
import {parametersConfig} from '../../utils/story-utils'

type StoryArgs = typeof TagsSection

const labels: Labels = {task: 'chat-completion', tags: ['reasoning', 'rag', 'agents', 'multilingual']}

const meta = {
  title: 'Apps/GitHub Models/TagsSection',
  component: TagsSection,
  args: {
    labels,
    headingLevel: 'h2',
  },
  argTypes: {
    labels: {control: 'object'},
    headingLevel: {control: 'radio', options: ['h2', 'h3']},
  },
  parameters: parametersConfig,
} satisfies Meta<StoryArgs>

export default meta

type Story = StoryObj<StoryArgs>

export const Example: Story = {
  render: args => <TagsSection {...args} />,
}
