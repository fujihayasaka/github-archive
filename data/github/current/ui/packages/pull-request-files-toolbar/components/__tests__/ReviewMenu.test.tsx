import {expectAnalyticsEvents} from '@github-ui/analytics-test-utils'
import {render} from '@github-ui/react-core/test-utils'
import useSafeState from '@github-ui/use-safe-state'
import {screen, waitFor, within} from '@testing-library/react'
import {useState} from 'react'

import {buildPullRequest} from '../../test-utils/mock-data'
import type {PullRequestsTargetType} from '../../types/analytics-events-types'
import type {
  AddReviewCallback,
  CancelReviewCallback,
  PendingViewerReview,
  PullRequestData,
  SubmitReviewCallback,
} from '../ReviewMenuButton'
import {ReviewMenuButton} from '../ReviewMenuButton'
import {AnalyticsProvider} from '@github-ui/analytics-provider'

function TestComponent({
  addReview,
  cancelReview,
  sumbitReview,
  viewerPendingReview,
  pullRequest,
  viewerLogin,
}: {
  addReview?: AddReviewCallback
  cancelReview?: CancelReviewCallback
  sumbitReview?: SubmitReviewCallback
  viewerPendingReview?: PendingViewerReview
  pullRequest: PullRequestData
  viewerLogin: string
}) {
  const [reviewBody, setReviewBody] = useSafeState('')
  const [reviewEvent, setReviewEvent] = useState('COMMENT')
  const [pendingReview, setPendingReview] = useState<PendingViewerReview | undefined>(viewerPendingReview)

  const onAddReview = addReview ? addReview : () => ({success: true})
  const onCancelReview = cancelReview
    ? cancelReview
    : () => {
        setPendingReview(undefined)
        return {success: true}
      }
  const onSumbitReview = sumbitReview
    ? sumbitReview
    : () => {
        setPendingReview(undefined)
        return {success: true}
      }

  return (
    <AnalyticsProvider appName="pull_request" category="review_menu" metadata={{pull_request_id: pullRequest.id}}>
      <ReviewMenuButton
        redirectOnSubmit
        currentUserLogin={viewerLogin}
        pullRequest={pullRequest}
        reviewBody={reviewBody}
        reviewEvent={reviewEvent}
        viewerPendingReview={pendingReview}
        onAddReview={onAddReview}
        onCancelReview={onCancelReview}
        onSumbitReview={onSumbitReview}
        onUpdateReviewBody={setReviewBody}
        onUpdateReviewEvent={setReviewEvent}
      />
    </AnalyticsProvider>
  )
}

const noPendingComments = {
  comments: {
    totalCount: 0,
  },
  id: 'test-id',
}

const onePendingComment = {
  id: 'test-id',
  comments: {
    totalCount: 1,
  },
}

/*
 * Spy on window.location.href to test upgrade navigation
 */
// @ts-expect-error overriding window.location in test
delete window.location
window.location = {hash: ''} as Location
const setHrefSpy = jest.fn()
Object.defineProperty(window.location, 'href', {
  set: setHrefSpy,
  get: () => 'test',
})

describe('basic open/close functionality', () => {
  test('clicking on "Submit review" opens review menu', async () => {
    const {user} = render(
      <TestComponent
        pullRequest={buildPullRequest({author: {login: 'test-author'}})}
        viewerLogin="test-author"
        viewerPendingReview={noPendingComments}
      />,
    )

    const reviewButton = await screen.findByRole('button', {name: 'Submit review'})
    await user.click(reviewButton)

    const dialogBox = await screen.findByRole('none')
    const submitButton = await within(dialogBox).findByRole('button', {name: 'Submit review'})

    expect(submitButton).toBeInTheDocument()

    expectAnalyticsEvents<PullRequestsTargetType>({
      type: 'submit_review_dialog.open',
      target: 'REVIEW_CHANGES_BUTTON',
      data: {
        app_name: 'pull_request',
      },
    })
  })

  test('clicking close button closes review menu', async () => {
    const {user} = render(
      <TestComponent
        pullRequest={buildPullRequest({author: {login: 'test-author'}})}
        viewerLogin="test-author"
        viewerPendingReview={noPendingComments}
      />,
    )

    const reviewButton = await screen.findByRole('button', {name: 'Submit review'})
    await user.click(reviewButton)

    expect(screen.getByText('Finish your review')).toBeInTheDocument()

    const closeButton = screen.getByLabelText('Close')
    expect(closeButton).toBeInTheDocument()

    await user.click(closeButton)
    await waitFor(() => expect(screen.queryByText('Finish your review')).not.toBeInTheDocument())
  })
})

describe('basic submitting a review, regardless of role, kind, and state', () => {
  test('can submit review via "Submit review" menu', async () => {
    const onSubmit = jest.fn(() => ({success: true}))

    const {user} = render(
      <TestComponent
        pullRequest={buildPullRequest({author: {login: 'test-author'}})}
        sumbitReview={onSubmit}
        viewerLogin="test-author"
        viewerPendingReview={noPendingComments}
      />,
    )

    const reviewButton = await screen.findByRole('button', {name: 'Submit review'})
    await user.click(reviewButton)

    expect(screen.getByText('Finish your review')).toBeInTheDocument()
    const reviewCommentInput = screen.getByPlaceholderText('Leave a comment')
    await user.type(reviewCommentInput, 'test comment')

    const dialogBox = await screen.findByRole('none')
    const submitButton = await within(dialogBox).findByRole('button', {name: 'Submit review'})
    expect(submitButton).toBeInTheDocument()

    await user.click(submitButton)

    await waitFor(() =>
      expect(onSubmit).toHaveBeenCalledWith('test comment', 'COMMENT', 'fakeId', 'test-id', 'mock-head-oid'),
    )

    expectAnalyticsEvents<PullRequestsTargetType>(
      {
        type: 'submit_review_dialog.open',
        target: 'REVIEW_CHANGES_BUTTON',
        data: {
          app_name: 'pull_request',
        },
      },
      {
        type: 'submit_review_dialog.submit',
        target: 'SUBMIT_REVIEW_BUTTON',
        data: {
          app_name: 'pull_request',
        },
      },
    )
    // Menu closes after submitting review
    expect(screen.queryByText('Finish your review')).not.toBeInTheDocument()
  })

  test('can submit pending review via "Submit review" menu', async () => {
    const {user} = render(
      <TestComponent
        pullRequest={buildPullRequest()}
        viewerLogin="test-author"
        viewerPendingReview={{id: 'test-id', comments: {totalCount: 27}}}
      />,
    )

    const reviewButton = await screen.findByRole('button', {name: 'Submit review (27)'})
    await user.click(reviewButton)

    const reviewCommentInput = await screen.findByPlaceholderText('Leave a comment')
    await user.type(reviewCommentInput, 'test comment')

    const dialogBox = await screen.findByRole('none')
    const submitButton = await within(dialogBox).findByRole('button', {name: 'Submit review'})
    expect(submitButton).toBeInTheDocument()

    await user.click(submitButton)

    await waitFor(() => expect(screen.queryByText('27')).not.toBeInTheDocument())
  })

  test('PR review submission failure shows a banner', async () => {
    const {user} = render(
      <TestComponent
        sumbitReview={() => ({success: false, errorMessage: 'test-error'})}
        viewerLogin="test-viewer"
        viewerPendingReview={onePendingComment}
        pullRequest={{
          ...buildPullRequest({author: {login: 'test-author'}}),

          viewerCanLeaveNonCommentReviews: true,
        }}
      />,
    )

    const reviewButton = await screen.findByRole('button', {name: 'Submit review (1)'})
    await user.click(reviewButton)

    const reviewCommentInput = await screen.findByPlaceholderText('Leave a comment')
    await user.type(reviewCommentInput, 'test comment')

    const dialogBox = await screen.findByRole('none')
    const submitButton = await within(dialogBox).findByRole('button', {name: 'Submit review'})
    expect(submitButton).toBeInTheDocument()

    await user.click(submitButton)

    const errorBanner = await screen.findByText('Failed to submit review: test-error')
    expect(errorBanner).toBeInTheDocument()
  })
})

describe('submitting a review, by role, kind, and state', () => {
  test('can submit review via "Submit review" menu with approval', async () => {
    const onSubmit = jest.fn(() => ({success: true}))
    const {user} = render(
      <TestComponent
        pullRequest={buildPullRequest({author: {login: 'test-author'}})}
        sumbitReview={onSubmit}
        viewerLogin="test-author"
        viewerPendingReview={noPendingComments}
      />,
    )

    const reviewButton = await screen.findByRole('button', {name: 'Submit review'})
    await user.click(reviewButton)

    const approvalMessageBox = await screen.findByPlaceholderText('Leave a comment')
    const approvalRadio = (await screen.findAllByRole('radio'))[1]!
    await user.type(approvalMessageBox, 'aaa')
    await user.click(approvalRadio)

    const dialogBox = await screen.findByRole('none')
    const submitButton = await within(dialogBox).findByRole('button', {name: 'Submit review'})
    expect(submitButton).toBeInTheDocument()

    await user.click(submitButton)

    expect(onSubmit).toHaveBeenCalledWith('aaa', 'APPROVE', 'fakeId', 'test-id', 'mock-head-oid')
  })

  test('can only leave comment review on closed PR when there are one or more pending review comments', async () => {
    const {user} = render(
      <TestComponent
        viewerLogin="test-viewer"
        pullRequest={{
          ...buildPullRequest({state: 'CLOSED'}),
        }}
        viewerPendingReview={{
          id: 'test-id',
          comments: {
            totalCount: 1,
          },
        }}
      />,
    )

    const submitComments = await screen.findByRole('button', {
      name: 'Submit comments (1)',
    })
    await user.click(submitComments)

    const submitRadios = screen.queryAllByRole('radio')
    expect(submitRadios).toHaveLength(0)
  })

  test('PR author cannot approve their pull request with comments', async () => {
    const {user} = render(
      <TestComponent
        viewerLogin="test-author"
        pullRequest={{
          ...buildPullRequest({author: {login: 'test-author'}}),

          viewerCanLeaveNonCommentReviews: false,
        }}
        viewerPendingReview={{
          id: 'test-id',
          comments: {
            totalCount: 1,
          },
        }}
      />,
    )

    const submitCommentsButton = await screen.findByRole('button', {name: 'Submit comments (1)'})
    await user.click(submitCommentsButton)

    const approvalTooltip = await screen.findByRole('tooltip', {
      name: `Pull request authors can't approve their own pull requests.`,
    })
    const requestedChangesTooltip = screen.getByRole('tooltip', {
      name: `Pull request authors can't request changes on their own pull requests.`,
    })
    const approvalRadio = within(approvalTooltip).getByRole('radio', {
      name: 'Approve Submit feedback and approve merging these changes.',
    })
    expect(approvalRadio).toHaveAttribute('disabled')
    const requestedChangesRadio = within(requestedChangesTooltip).getByRole('radio', {
      name: 'Request changes Submit feedback that must be addressed before merging.',
    })
    expect(requestedChangesRadio).toHaveAttribute('disabled')
  })
})

describe('discarding a PR review', () => {
  test('can discard a review', async () => {
    jest.spyOn(window, 'confirm').mockImplementation(() => true)

    const {user} = render(
      <TestComponent
        pullRequest={buildPullRequest()}
        viewerLogin="monalisa"
        viewerPendingReview={{id: 'test-id', comments: {totalCount: 27}}}
      />,
    )

    const reviewButton = await screen.findByRole('button', {name: 'Submit review (27)'})
    await user.click(reviewButton)

    await screen.findByText('27 pending comments')
    const abandonButton = await screen.findByText('Discard review')
    expect(abandonButton).toBeInTheDocument()

    // TODO: Re-enable and update once we have the tanstack implementation
    await user.click(abandonButton)

    // abandon button goes away after abandoning review
    await waitFor(() => expect(screen.queryByText('Discard review')).not.toBeInTheDocument())
    await waitFor(() => expect(screen.queryByText('27')).not.toBeInTheDocument())
    expectAnalyticsEvents<PullRequestsTargetType>(
      {
        type: 'submit_review_dialog.open',
        target: 'REVIEW_CHANGES_BUTTON',
        data: {
          app_name: 'pull_request',
        },
      },
      {
        type: 'submit_review_dialog.cancel',
        target: 'CANCEL_REVIEW_BUTTON',
        data: {
          app_name: 'pull_request',
        },
      },
    )
  })

  test('failure shows a banner', async () => {
    jest.spyOn(window, 'confirm').mockImplementation(() => true)

    const {user} = render(
      <TestComponent
        cancelReview={() => ({success: false, errorMessage: 'test-error'})}
        pullRequest={buildPullRequest({author: {login: 'test-author'}})}
        viewerLogin="test-reviewer"
        viewerPendingReview={noPendingComments}
      />,
    )

    const reviewButton = await screen.findByRole('button', {name: 'Submit review'})
    await user.click(reviewButton)

    const abandonButton = await screen.findByText('Discard review')
    expect(abandonButton).toBeInTheDocument()

    await user.click(abandonButton)

    const errorBanner = await screen.findByText('Failed to cancel review: test-error')
    expect(errorBanner).toBeInTheDocument()
  })
})

describe('Author display state', () => {
  describe('PR is open', () => {
    describe('author has 0 pending comments', () => {
      test('renders nothing', () => {
        render(
          <TestComponent
            viewerLogin="test-author"
            viewerPendingReview={noPendingComments}
            pullRequest={{
              ...buildPullRequest({state: 'OPEN', author: {login: 'test-author'}}),
              // API returns false for author viewing PR
              viewerCanLeaveNonCommentReviews: false,
            }}
          />,
        )

        expect(screen.queryByRole('button')).not.toBeInTheDocument()
      })
    })

    describe('author has 1 or more pending comments', () => {
      test('renders "Submit comments" button with pending review comment count and "Discard comments" button', async () => {
        const {user} = render(
          <TestComponent
            viewerLogin="test-author"
            viewerPendingReview={onePendingComment}
            pullRequest={{
              ...buildPullRequest({state: 'OPEN', author: {login: 'test-author'}}),
              // API returns false for author viewing PR
              viewerCanLeaveNonCommentReviews: false,
            }}
          />,
        )

        const submitCommentsButton = screen.getByRole('button', {name: 'Submit comments (1)'})
        expect(submitCommentsButton).toBeInTheDocument()
        await user.click(submitCommentsButton)

        expect(screen.getByRole('button', {name: 'Discard comments'})).toBeInTheDocument()
      })
    })
  })

  describe('PR is not open', () => {
    describe('author has 0 pending comments', () => {
      test('renders nothing', () => {
        render(
          <TestComponent
            viewerLogin="test-author"
            viewerPendingReview={noPendingComments}
            pullRequest={{
              ...buildPullRequest({state: 'MERGED', author: {login: 'test-author'}}),
              // API returns false for author viewing PR
              viewerCanLeaveNonCommentReviews: false,
            }}
          />,
        )

        expect(screen.queryByRole('button')).not.toBeInTheDocument()
      })
    })

    describe('author has 1 or more pending comments', () => {
      test('renders "Submit comments" button with pending review comment count and "Discard comments" button', async () => {
        const {user} = render(
          <TestComponent
            viewerLogin="test-author"
            viewerPendingReview={onePendingComment}
            pullRequest={{
              ...buildPullRequest({state: 'MERGED', author: {login: 'test-author'}}),
              // API returns false for author viewing PR
              viewerCanLeaveNonCommentReviews: false,
            }}
          />,
        )

        const submitCommentsButton = screen.getByRole('button', {name: 'Submit comments (1)'})
        expect(submitCommentsButton).toBeInTheDocument()
        await user.click(submitCommentsButton)

        expect(screen.getByRole('button', {name: 'Discard comments'})).toBeInTheDocument()
      })
    })
  })
})

describe('Reviewer with approval rights display state', () => {
  describe('PR is open', () => {
    describe('when reviewer has 0 pending comments', () => {
      test('renders "Submit review" button', () => {
        render(
          <TestComponent
            viewerLogin="test-reviewer"
            viewerPendingReview={noPendingComments}
            pullRequest={{
              ...buildPullRequest({state: 'OPEN', author: {login: 'test-author'}}),
              viewerCanLeaveNonCommentReviews: true,
            }}
          />,
        )

        expect(screen.getByRole('button', {name: 'Submit review'})).toBeInTheDocument()
      })
    })

    describe('when reviewer has 1 or more pending comments', () => {
      test('renders "Submit review" button with pending review comment count and "Discard review" button', async () => {
        const {user} = render(
          <TestComponent
            viewerLogin="test-reviewer"
            viewerPendingReview={onePendingComment}
            pullRequest={{
              ...buildPullRequest({state: 'OPEN', author: {login: 'test-author'}}),
              viewerCanLeaveNonCommentReviews: true,
            }}
          />,
        )

        const submitReviewButton = screen.getByRole('button', {name: 'Submit review (1)'})
        expect(submitReviewButton).toBeInTheDocument()
        await user.click(submitReviewButton)

        expect(screen.getByRole('button', {name: 'Discard review'})).toBeInTheDocument()
      })
    })
  })

  describe('PR is not open', () => {
    describe('when reviewer has 0 pending comments', () => {
      test('renders nothing', () => {
        render(
          <TestComponent
            viewerLogin="test-reviewer"
            viewerPendingReview={noPendingComments}
            pullRequest={{
              ...buildPullRequest({state: 'MERGED', author: {login: 'test-author'}}),
              viewerCanLeaveNonCommentReviews: true,
            }}
          />,
        )

        expect(screen.queryByRole('button')).not.toBeInTheDocument()
      })
    })

    describe('when reviewer has 1 or more pending comments', () => {
      test('renders "Submit comments" button with pending review comment count and "Discard comments" button', async () => {
        const {user} = render(
          <TestComponent
            viewerLogin="test-reviewer"
            viewerPendingReview={onePendingComment}
            pullRequest={{
              ...buildPullRequest({state: 'MERGED', author: {login: 'test-author'}}),
              viewerCanLeaveNonCommentReviews: true,
            }}
          />,
        )

        const submitCommentsButton = screen.getByRole('button', {name: 'Submit comments (1)'})
        expect(submitCommentsButton).toBeInTheDocument()
        await user.click(submitCommentsButton)

        expect(screen.getByRole('button', {name: 'Discard comments'})).toBeInTheDocument()
      })
    })
  })
})

describe('Reviewer without approval rights display state', () => {
  describe('PR is open', () => {
    describe('when reviewer has 0 pending comments', () => {
      test('renders nothing', () => {
        render(
          <TestComponent
            viewerLogin="test-reviewer"
            viewerPendingReview={noPendingComments}
            pullRequest={{
              ...buildPullRequest({state: 'OPEN', author: {login: 'test-author'}}),
              viewerCanLeaveNonCommentReviews: false,
            }}
          />,
        )

        expect(screen.queryByRole('button')).not.toBeInTheDocument()
      })
    })

    describe('when reviewer has 1 or more pending comments', () => {
      test('renders "Submit comments" buttons with pending review comment count', async () => {
        const {user} = render(
          <TestComponent
            viewerLogin="test-reviewer"
            viewerPendingReview={onePendingComment}
            pullRequest={{
              ...buildPullRequest({state: 'OPEN', author: {login: 'test-author'}}),
              viewerCanLeaveNonCommentReviews: false,
            }}
          />,
        )

        const submitCommentsButton = screen.getByRole('button', {name: 'Submit comments (1)'})
        expect(submitCommentsButton).toBeInTheDocument()
        await user.click(submitCommentsButton)

        expect(screen.getByRole('button', {name: 'Discard comments'})).toBeInTheDocument()
      })
    })
  })

  describe('PR is not open', () => {
    describe('when reviewer has 0 pending comments', () => {
      test('renders nothing', () => {
        render(
          <TestComponent
            viewerLogin="test-reviewer"
            viewerPendingReview={noPendingComments}
            pullRequest={{
              ...buildPullRequest({state: 'CLOSED', author: {login: 'test-author'}}),
              viewerCanLeaveNonCommentReviews: false,
            }}
          />,
        )

        expect(screen.queryByRole('button')).not.toBeInTheDocument()
      })
    })

    describe('when reviewer has 1 or more pending comments', () => {
      test('renders "Submit comments" buttons with pending review comment count and "Discard comments" button', async () => {
        const {user} = render(
          <TestComponent
            viewerLogin="test-reviewer"
            viewerPendingReview={onePendingComment}
            pullRequest={{
              ...buildPullRequest({state: 'CLOSED', author: {login: 'test-author'}}),
              viewerCanLeaveNonCommentReviews: false,
            }}
          />,
        )

        const submitCommentsButton = screen.getByRole('button', {name: 'Submit comments (1)'})
        expect(submitCommentsButton).toBeInTheDocument()
        await user.click(submitCommentsButton)

        expect(screen.getByRole('button', {name: 'Discard comments'})).toBeInTheDocument()
      })
    })
  })
})
