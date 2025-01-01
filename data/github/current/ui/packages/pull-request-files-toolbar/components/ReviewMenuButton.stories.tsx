import type {Meta, StoryObj} from '@storybook/react'

import {ReviewMenuButton, type ReviewMenuButtonProps} from './ReviewMenuButton'
import {buildPullRequest} from '../test-utils/mock-data'

const defaultProps: ReviewMenuButtonProps = {
  pullRequest: buildPullRequest(),
  onAddReview: () => ({success: true}),
  onCancelReview: () => ({success: true}),
  onSumbitReview: () => ({success: true}),
  onUpdateReviewBody: () => {},
  onUpdateReviewEvent: () => {},
  redirectOnSubmit: false,
  reviewBody: 'Content',
  reviewEvent: 'COMMENT',
  currentUserLogin: 'currentUser',
}

const meta = {
  title: 'Apps/React Shared/Pull Requests/ReviewMenuButton',
  component: ReviewMenuButton,
  args: {...defaultProps},
  parameters: {
    controls: {expanded: true, sort: 'alpha'},
  },
} satisfies Meta<typeof ReviewMenuButton>

export default meta

type Story = StoryObj<typeof ReviewMenuButton>

export const Default: Story = {}
