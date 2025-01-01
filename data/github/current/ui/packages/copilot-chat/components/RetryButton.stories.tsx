import type {Meta, StoryObj} from '@storybook/react'

import {RetryButton, type RetryButtonProps} from './RetryButton'

const meta = {
  title: 'Apps/Copilot/RetryButton',
  component: RetryButton,
  parameters: {},
  argTypes: {},
} satisfies Meta<RetryButtonProps>

export default meta

export const Standalone: StoryObj<RetryButtonProps> = {
  render: () => (
    <RetryButton
      handleRetryMessage={function (): void {
        alert('Clicked!')
      }}
    />
  ),
}

export const RetryModel: StoryObj<RetryButtonProps> = {
  render: () => (
    <RetryButton
      handleRetryMessage={function (): void {
        alert('Clicked!')
      }}
      showModelPicker
      modelName={'gpt-4'}
    />
  ),
}
