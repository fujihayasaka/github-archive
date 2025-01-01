import type {Meta, StoryObj} from '@storybook/react'

import {CopilotCodeReviewFeedback, type CopilotCodeReviewFeedbackProps} from './CopilotCodeReviewFeedback'

const meta = {
  title: 'Apps/Copilot/CopilotCodeReviewFeedback',
  component: CopilotCodeReviewFeedback,
  parameters: {},
  argTypes: {},
} satisfies Meta<typeof CopilotCodeReviewFeedback>

export default meta

const defaultArgs: CopilotCodeReviewFeedbackProps = {
  commentId: '1',
  commentUrl: 'https://example.com/comment/1',
} as const

export const Standalone: StoryObj<CopilotCodeReviewFeedbackProps> = {
  args: defaultArgs,
  render: args => <CopilotCodeReviewFeedback {...args} />,
}
