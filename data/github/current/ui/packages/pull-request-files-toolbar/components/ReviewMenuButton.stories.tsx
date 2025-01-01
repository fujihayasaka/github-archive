import type {Meta, StoryObj} from '@storybook/react'
import {expect, within, userEvent, waitFor} from '@storybook/test'
import {jest} from '@storybook/jest'
import {shouldInteractionPlay} from '@github-ui/storybook'
import {AnalyticsProvider} from '@github-ui/analytics-provider'
import {http, HttpResponse} from 'msw'
import {PageDataContextProvider} from '@github-ui/pull-request-page-data-tooling/page-data-context'

import {ReviewMenuButton, type ReviewMenuButtonProps} from './ReviewMenuButton'
import {buildPendingCommentPreview, buildPullRequest} from '../test-utils/mock-data'
import type {SafeHTMLString} from '@github-ui/safe-html'
import {PageData} from '@github-ui/pull-request-page-data-tooling/page-data'
import {PullRequestState} from '../page-data/payloads/toolbar'

const noPendingComments = {
  comments: [],
  id: 'test-id',
}

const onePendingComment = {
  comments: [buildPendingCommentPreview({bodyHTML: 'testHTML' as SafeHTMLString})],
  id: 'test-id',
}
const defaultProps: ReviewMenuButtonProps = {
  pullRequest: buildPullRequest(),
  repository: buildPullRequest().repository,
  currentUserLogin: 'currentUser',
  initialPendingReview: noPendingComments,
}

let successfulSubmission: boolean | null = null

const meta = {
  title: 'Pull Requests/FilesToolbar/ReviewMenuButton',
  component: ReviewMenuButton,
  async beforeEach() {
    successfulSubmission = null
  },
  args: {...defaultProps},
  parameters: {
    controls: {expanded: true, sort: 'alpha'},
    a11y: {
      config: {
        rules: [
          {
            // Validation errors have animation that causes false-positive results for known contrast check issue with AnchoredOverlay opening in Storybook
            id: 'color-contrast',
            enabled: false,
          },
        ],
      },
    },
    msw: {
      handlers: [
        http.get(`/test-user/test-repo/pull/1/page_data/${PageData.pendingReview}`, () => {
          return HttpResponse.json({id: undefined, comments: [noPendingComments]})
        }),
      ],
    },
  },
  decorators: [
    Story => (
      <AnalyticsProvider
        appName="pull_request"
        category="review_menu"
        metadata={{pull_request_id: defaultProps.pullRequest.id}}
      >
        <PageDataContextProvider basePageDataUrl={defaultProps.pullRequest.pathName}>
          <Story />
        </PageDataContextProvider>
      </AnalyticsProvider>
    ),
  ],
} satisfies Meta<typeof ReviewMenuButton>

type Story = StoryObj<typeof ReviewMenuButton>

export const Opening_Review_Dialog: Story = {
  render: () => {
    const pullRequest = buildPullRequest({author: {login: 'test-author'}})
    return (
      <ReviewMenuButton
        pullRequest={pullRequest}
        repository={pullRequest.repository}
        currentUserLogin="test-author"
        initialPendingReview={noPendingComments}
      />
    )
  },
  play: async ({canvasElement, step}) => {
    if (!shouldInteractionPlay()) return

    const canvas = within(canvasElement)

    await step('Clicking "Submit review" button to open modal', async () => {
      await userEvent.click(canvas.getByRole('button', {name: 'Submit review'}))
    })

    await step('Review modal should be open', async () => {
      const dialogBox = await canvas.findByRole('dialog')
      const submitReviewButton = within(dialogBox).getByRole('button', {name: 'Submit review'})
      expect(submitReviewButton).toBeInTheDocument()

      expect(within(dialogBox).queryByText('Review comments')).not.toBeInTheDocument()
    })
  },
}

export const Opening_Review_Dialog_With_Pending_Comments: Story = {
  parameters: {
    msw: {
      handlers: [
        http.get(`/test-user/test-repo/pull/1/page_data/${PageData.pendingReview}`, () => {
          return HttpResponse.json({id: 'test-id', comments: [onePendingComment]})
        }),
      ],
    },
  },
  render: () => {
    const pullRequest = buildPullRequest()
    return (
      <ReviewMenuButton
        pullRequest={pullRequest}
        repository={pullRequest.repository}
        currentUserLogin="test-reviewer"
        initialPendingReview={onePendingComment}
      />
    )
  },
  play: async ({canvasElement, step}) => {
    if (!shouldInteractionPlay()) return

    const canvas = within(canvasElement)

    await step('Clicking "Submit review" button to open modal', async () => {
      await userEvent.click(canvas.getByRole('button', {name: 'Submit review (1)'}))
    })

    await step('Review modal should be open', async () => {
      const dialogBox = await canvas.findByRole('dialog')
      const submitReviewButton = within(dialogBox).getByRole('button', {name: 'Submit review'})
      expect(submitReviewButton).toBeInTheDocument()

      expect(within(dialogBox).getByText('Review comments')).toBeInTheDocument()
      expect(within(dialogBox).getByText('testHTML')).toBeInTheDocument()
    })
  },
}

export const Closing_Review_Dialog: Story = {
  render: () => {
    const pullRequest = buildPullRequest({author: {login: 'test-author'}})
    return (
      <ReviewMenuButton
        pullRequest={pullRequest}
        repository={pullRequest.repository}
        currentUserLogin="test-author"
        initialPendingReview={noPendingComments}
      />
    )
  },
  play: async ({canvasElement, step}) => {
    if (!shouldInteractionPlay()) return

    const canvas = within(canvasElement)

    await step('Clicking "Submit review" button to open modal', async () => {
      await userEvent.click(canvas.getByRole('button', {name: 'Submit review'}))
    })

    await step('Clicking "Close" button to close review menu', async () => {
      await userEvent.click(await canvas.findByRole('button', {name: 'Close'}))
      await waitFor(() => expect(canvas.queryByRole('dialog')).not.toBeInTheDocument())
    })
  },
}

export const Submit_Review_With_No_Pending_Comments: Story = {
  parameters: {
    msw: {
      handlers: [
        http.put('/test-user/test-repo/pull/1/page_data/submit_review', () => {
          successfulSubmission = true
          return HttpResponse.json({
            message: 'Your review was submitted successfully.',
            redirectUrl: '/test-user/test-repo/pull/1#pullrequestreview-123',
          })
        }),
      ],
    },
  },
  render: () => {
    const pullRequest = buildPullRequest({author: {login: 'test-author'}})
    return (
      <ReviewMenuButton
        pullRequest={pullRequest}
        repository={pullRequest.repository}
        currentUserLogin="test-author"
        initialPendingReview={noPendingComments}
        // Disable redirect to avoid navigation breaking test
        redirectOnMutation={false}
      />
    )
  },
  play: async ({canvasElement, step}) => {
    if (!shouldInteractionPlay()) return

    const canvas = within(canvasElement)

    await step('Click "Submit review" button to open modal', async () => {
      await userEvent.click(canvas.getByRole('button', {name: 'Submit review'}))
    })

    const dialog = await canvas.findByRole('dialog')

    await step('Adding review comment', async () => {
      const reviewCommentInput = within(dialog).getByPlaceholderText('Leave a comment')
      await userEvent.type(reviewCommentInput, 'test comment')
    })

    await step('Submitting review is successful', async () => {
      await userEvent.click(within(dialog).getByRole('button', {name: 'Submit review'}))
      await waitFor(() => expect(successfulSubmission).toBe(true))
    })
  },
}

export const Submit_Review_As_Reviewer_With_Pending_Comments: Story = {
  parameters: {
    msw: {
      handlers: [
        http.get(`/test-user/test-repo/pull/1/page_data/${PageData.pendingReview}`, () => {
          return HttpResponse.json({id: 'test-id', comments: [onePendingComment]})
        }),
        http.put('/test-user/test-repo/pull/1/page_data/submit_review', () => {
          successfulSubmission = true
          return HttpResponse.json({
            message: 'Your review was submitted successfully.',
            redirectUrl: '/test-user/test-repo/pull/1#pullrequestreview-123',
          })
        }),
      ],
    },
  },
  render: () => {
    const pullRequest = buildPullRequest()
    return (
      <ReviewMenuButton
        pullRequest={pullRequest}
        repository={pullRequest.repository}
        currentUserLogin="test-reviewer"
        initialPendingReview={onePendingComment}
        // Disable redirect to avoid navigation breaking test
        redirectOnMutation={false}
      />
    )
  },
  play: async ({canvasElement, step}) => {
    if (!shouldInteractionPlay()) return

    const canvas = within(canvasElement)

    await step('Clicking "Submit review" button to open modal', async () => {
      await userEvent.click(canvas.getByRole('button', {name: 'Submit review (1)'}))
    })

    await step('Submitting review', async () => {
      const dialog = await canvas.findByRole('dialog')
      await userEvent.click(within(dialog).getByRole('button', {name: 'Submit review'}))
      await waitFor(() => expect(successfulSubmission).toBe(true))
    })
  },
}

export const Submit_Review_As_Author_With_Pending_Comments: Story = {
  parameters: {
    msw: {
      handlers: [
        http.get(`/test-user/test-repo/pull/1/page_data/${PageData.pendingReview}`, () => {
          return HttpResponse.json({id: 'test-id', comments: [onePendingComment]})
        }),
        http.put('/test-user/test-repo/pull/1/page_data/submit_review', () => {
          successfulSubmission = true
          return HttpResponse.json({
            message: 'Your review was submitted successfully.',
            redirectUrl: '/test-user/test-repo/pull/1#pullrequestreview-123',
          })
        }),
      ],
    },
  },
  render: () => {
    const pullRequest = buildPullRequest({author: {login: 'test-author'}})
    return (
      <ReviewMenuButton
        pullRequest={pullRequest}
        repository={pullRequest.repository}
        currentUserLogin="test-author"
        initialPendingReview={onePendingComment}
        // Disable redirect to avoid navigation breaking test
        redirectOnMutation={false}
      />
    )
  },
  play: async ({canvasElement, step}) => {
    if (!shouldInteractionPlay()) return

    const canvas = within(canvasElement)

    await step('Clicking "Submit review" button to open modal', async () => {
      await userEvent.click(canvas.getByRole('button', {name: 'Submit comments (1)'}))
    })

    await step('Submitting review comments', async () => {
      const dialog = await canvas.findByRole('dialog')
      await userEvent.click(within(dialog).getByRole('button', {name: 'Submit comments'}))
      await waitFor(() => expect(successfulSubmission).toBe(true))
    })
  },
}

export const Submit_Review_With_Failure: Story = {
  parameters: {
    msw: {
      handlers: [
        http.get(`/test-user/test-repo/pull/1/page_data/${PageData.pendingReview}`, () => {
          return HttpResponse.json({id: 'test-id', comments: [onePendingComment]})
        }),
        http.put('/test-user/test-repo/pull/1/page_data/submit_review', () => {
          successfulSubmission = false
          return HttpResponse.json({error: 'There was a problem submitting your review.'}, {status: 422})
        }),
      ],
    },
  },
  render: () => {
    const pullRequest = buildPullRequest()
    return (
      <ReviewMenuButton
        pullRequest={pullRequest}
        repository={pullRequest.repository}
        currentUserLogin="test-reviewer"
        initialPendingReview={onePendingComment}
      />
    )
  },
  play: async ({canvasElement, step}) => {
    if (!shouldInteractionPlay()) return

    const canvas = within(canvasElement)

    await step('Clicking "Submit review" button to open modal', async () => {
      await userEvent.click(canvas.getByRole('button', {name: 'Submit review (1)'}))
    })

    await step('Submitting review comments', async () => {
      const dialog = await canvas.findByRole('dialog')
      await userEvent.click(within(dialog).getByRole('button', {name: 'Submit review'}))
      await waitFor(() => expect(successfulSubmission).toBe(false))
      expect(await canvas.findByText('There was a problem submitting your review.')).toBeInTheDocument()
    })
  },
}

export const Author_Can_Leave_Review_On_Closed_Pull_Request_When_Pending_Comments_Exist: Story = {
  parameters: {
    msw: {
      handlers: [
        http.get(`/test-user/test-repo/pull/1/page_data/${PageData.pendingReview}`, () => {
          return HttpResponse.json({id: 'test-id', comments: [onePendingComment]})
        }),
      ],
    },
  },
  render: () => {
    const pullRequest = buildPullRequest({state: PullRequestState.Closed, author: {login: 'test-author'}})
    return (
      <ReviewMenuButton
        currentUserLogin="test-author"
        pullRequest={pullRequest}
        repository={pullRequest.repository}
        initialPendingReview={onePendingComment}
      />
    )
  },
  play: async ({canvasElement, step}) => {
    if (!shouldInteractionPlay()) return

    const canvas = within(canvasElement)

    await step('Clicking "Submit comments (1)" button to open modal', async () => {
      await userEvent.click(canvas.getByRole('button', {name: 'Submit comments (1)'}))
    })

    const dialog = await canvas.findByRole('dialog')

    await step('No event selections available', async () => {
      expect(within(dialog).queryAllByRole('radio')).toHaveLength(0)
    })

    await step('"Submit comments" button is enabled', async () => {
      expect(within(dialog).getByRole('button', {name: 'Submit comments'})).not.toBeDisabled()
    })
  },
}

export const Author_Cannot_Approve_Or_Request_Change_On_Their_Pull_Request_With_Comments: Story = {
  parameters: {
    msw: {
      handlers: [
        http.get(`/test-user/test-repo/pull/1/page_data/${PageData.pendingReview}`, () => {
          return HttpResponse.json({id: 'test-id', comments: [onePendingComment]})
        }),
      ],
    },
  },
  render: () => {
    const pullRequest = buildPullRequest({author: {login: 'test-author'}})
    return (
      <ReviewMenuButton
        pullRequest={{
          ...pullRequest,
          viewerCanLeaveNonCommentReviews: false,
        }}
        currentUserLogin="test-author"
        repository={pullRequest.repository}
        initialPendingReview={onePendingComment}
      />
    )
  },
  play: async ({canvasElement, step}) => {
    if (!shouldInteractionPlay()) return

    const canvas = within(canvasElement)

    await step('Clicking "Submit comments (1)" button to open modal', async () => {
      await userEvent.click(canvas.getByRole('button', {name: 'Submit comments (1)'}))
    })

    await step('Show why authors are unable to approve or request changes on their own pull request', async () => {
      const dialog = await canvas.findByRole('dialog')
      const approvalTooltip = await within(dialog).findByRole('tooltip', {
        name: `Pull request authors can't approve their own pull requests.`,
      })
      const requestedChangesTooltip = within(dialog).getByRole('tooltip', {
        name: `Pull request authors can't request changes on their own pull requests.`,
      })
      const approvalSelection = within(approvalTooltip).getByRole('radio', {
        name: 'Approve Submit feedback and approve merging these changes.',
      })
      expect(approvalSelection).toHaveAttribute('disabled')
      const requestedChangesSelection = within(requestedChangesTooltip).getByRole('radio', {
        name: 'Request changes Submit feedback that must be addressed before merging.',
      })
      expect(requestedChangesSelection).toHaveAttribute('disabled')
    })
  },
}

export const DiscardingReview: Story = {
  parameters: {
    msw: {
      handlers: [
        http.get(`/test-user/test-repo/pull/1/page_data/${PageData.pendingReview}`, () => {
          return HttpResponse.json({id: 'test-id', comments: [onePendingComment]})
        }),
        http.delete('/test-user/test-repo/pull/1/page_data/abandon_review', () => {
          successfulSubmission = true
          return HttpResponse.json({
            message: 'Your pending review comments have been discarded.',
            redirectUrl: '/test-user/test-repo/pull/1#pullrequestreview-123',
          })
        }),
      ],
    },
  },
  render: () => {
    const pullRequest = buildPullRequest()
    return (
      <ReviewMenuButton
        pullRequest={pullRequest}
        currentUserLogin="test-reviewer"
        repository={pullRequest.repository}
        initialPendingReview={onePendingComment}
        // Disable redirect to avoid navigation breaking test
        redirectOnMutation={false}
      />
    )
  },
  play: async ({canvasElement, step}) => {
    if (!shouldInteractionPlay()) return

    jest.spyOn(window, 'confirm').mockImplementation(() => true)

    const canvas = within(canvasElement)

    await step('Clicking "Submit review" button to open modal', async () => {
      await userEvent.click(canvas.getByRole('button', {name: 'Submit review (1)'}))
    })

    await step('Clicking "Discard review" button', async () => {
      const dialog = await canvas.findByRole('dialog')
      await userEvent.click(within(dialog).getByRole('button', {name: 'Discard review'}))
      await waitFor(() => expect(successfulSubmission).toBe(true))
    })
  },
}

export const DiscardingReviewWithFailure: Story = {
  parameters: {
    msw: {
      handlers: [
        http.get(`/test-user/test-repo/pull/1/page_data/${PageData.pendingReview}`, () => {
          return HttpResponse.json({id: 'test-id', comments: [onePendingComment]})
        }),
        http.delete('/test-user/test-repo/pull/1/page_data/abandon_review', () => {
          successfulSubmission = false
          return HttpResponse.json({error: 'Failed to delete pending comments for pending review.'}, {status: 422})
        }),
      ],
    },
  },
  render: () => {
    const pullRequest = buildPullRequest()
    return (
      <ReviewMenuButton
        pullRequest={pullRequest}
        currentUserLogin="test-reviewer"
        repository={pullRequest.repository}
        initialPendingReview={onePendingComment}
        // Disable redirect to avoid navigation breaking test
        redirectOnMutation={false}
      />
    )
  },
  play: async ({canvasElement, step}) => {
    if (!shouldInteractionPlay()) return

    jest.spyOn(window, 'confirm').mockImplementation(() => true)

    const canvas = within(canvasElement)

    await step('Clicking "Submit review" button to open modal', async () => {
      await userEvent.click(canvas.getByRole('button', {name: 'Submit review (1)'}))
    })

    await step('Clicking "Discard review" button shows failure banner', async () => {
      const dialog = await canvas.findByRole('dialog')
      await userEvent.click(within(dialog).getByRole('button', {name: 'Discard review'}))
      await waitFor(() => expect(successfulSubmission).toBe(false))
      expect(await canvas.findByText('Failed to delete pending comments for pending review.')).toBeInTheDocument()
    })
  },
}

export const Author_Has_Zero_Pending_Comments_And_No_Approval_Access: Story = {
  render: () => {
    const pullRequest = buildPullRequest({author: {login: 'test-author'}})
    return (
      <ReviewMenuButton
        pullRequest={{...pullRequest, viewerCanLeaveNonCommentReviews: false}}
        currentUserLogin="test-author"
        repository={pullRequest.repository}
        initialPendingReview={noPendingComments}
      />
    )
  },
  play: async ({canvasElement, step}) => {
    if (!shouldInteractionPlay()) return

    const canvas = within(canvasElement)

    await step('No button to open review dialog is rendered', async () => {
      expect(canvas.queryByRole('button')).not.toBeInTheDocument()
    })
  },
}

export const Author_Has_Zero_Pending_Comments_But_Has_Approval_Access: Story = {
  render: () => {
    const pullRequest = buildPullRequest({author: {login: 'test-author'}})
    return (
      <ReviewMenuButton
        pullRequest={{...pullRequest, viewerCanLeaveNonCommentReviews: true}}
        currentUserLogin="test-author"
        repository={pullRequest.repository}
        initialPendingReview={noPendingComments}
      />
    )
  },
  play: async ({canvasElement, step}) => {
    if (!shouldInteractionPlay()) return

    const canvas = within(canvasElement)

    await step('Has "Submit review" button to open review dialog', async () => {
      await userEvent.click(canvas.getByRole('button', {name: 'Submit review'}))
    })

    await step('all events are selectable', async () => {
      const dialog = await canvas.findByRole('dialog')
      const selectableEvents = within(dialog).getAllByRole('radio')
      expect(selectableEvents).toHaveLength(3)
      expect(selectableEvents[0]).not.toBeDisabled()
      expect(selectableEvents[1]).not.toBeDisabled()
      expect(selectableEvents[2]).not.toBeDisabled()
    })
  },
}

export const Default: Story = {}

export default meta
