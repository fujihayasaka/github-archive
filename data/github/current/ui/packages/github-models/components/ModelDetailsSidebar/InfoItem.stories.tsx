import type {Meta, StoryObj} from '@storybook/react'
import {Link} from '@primer/react'
import {InfoItem} from './InfoItem'
import {parametersConfig} from '../../utils/story-utils'

type StoryArgs = typeof InfoItem

const meta = {
  title: 'Apps/GitHub Models/InfoItem',
  component: InfoItem,
  args: {
    label: 'Rate limit tier',
    isInline: true,
    children: (
      <Link inline href="https://docs.github.com/github-models/prototyping-with-ai-models#rate-limits">
        Medium
      </Link>
    ),
  },
  argTypes: {
    isInline: {control: 'boolean'},
    label: {control: 'text'},
    children: {control: 'object'},
  },
  parameters: parametersConfig,
} satisfies Meta<StoryArgs>

export default meta

type Story = StoryObj<StoryArgs>

export const Example: Story = {
  render: args => <InfoItem {...args} />,
}
