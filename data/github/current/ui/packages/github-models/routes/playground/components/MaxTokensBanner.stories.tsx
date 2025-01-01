import type {Meta, StoryObj} from '@storybook/react'
import {parametersConfig} from '../../../utils/story-utils'
import {mockModel, mockTokenUsage} from '../__tests__/mocks'
import {MaxTokensBanner} from './MaxTokensBanner'
import {mockModelState} from './__tests__/mocks'

type StoryArgs = typeof MaxTokensBanner

const catalogData = Object.assign({}, mockModel, {max_output_tokens: 10000})
const tokenUsage = Object.assign({}, mockTokenUsage, {totalOutputTokens: 10001})
const modelState = mockModelState({catalogData, tokenUsage})

const meta = {
  title: 'Apps/GitHub Models/MaxTokensBanner',
  component: MaxTokensBanner,
  args: {modelState},
  argTypes: {modelState: {control: 'object'}},
  parameters: parametersConfig,
} satisfies Meta<StoryArgs>

export default meta

type Story = StoryObj<StoryArgs>

export const Example: Story = {
  render: args => <MaxTokensBanner {...args} />,
}
