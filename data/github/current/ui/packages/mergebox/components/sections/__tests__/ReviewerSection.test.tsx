import {render} from '@github-ui/react-core/test-utils'
import {useAnalytics} from '@github-ui/use-analytics'
import {fireEvent, screen} from '@testing-library/react'

import type {PullRequestReviewState, PullRequestRuleFailureReason, PendingReviewRequest} from '../../../types'
import type {ReviewerSectionProps} from '../ReviewerSection'
import {ConsolidatedReviewState, ReviewerSection} from '../ReviewerSection'
import {PageDataContextProvider} from '@github-ui/pull-request-page-data-tooling/page-data-context'
import {BASE_PAGE_DATA_URL} from '@github-ui/pull-request-page-data-tooling/render-with-query-client'
// eslint-disable-next-line no-restricted-imports
import {mockFetch} from '@github-ui/mock-fetch'
import {PageData} from '@github-ui/pull-request-page-data-tooling/page-data'

jest.mock('@github-ui/use-analytics')
const sendAnalyticsEventMock = jest.fn()
jest.mocked(useAnalytics).mockReturnValue({sendAnalyticsEvent: sendAnalyticsEventMock})

beforeEach(() => {
  sendAnalyticsEventMock.mockReset()
  sessionStorage.clear()
})
afterEach(() => jest.clearAllMocks())

const moreReviewsFailureReason: PullRequestRuleFailureReason = 'MORE_REVIEWS_REQUIRED'
const changesRequestedFailureReason: PullRequestRuleFailureReason = 'CHANGES_REQUESTED'
const socFailureReason: PullRequestRuleFailureReason = 'SOC2_APPROVAL_PROCESS_REQUIRED'
const lastPushApprovalFailureReason: PullRequestRuleFailureReason = 'LAST_PUSH_APPROVAL_REQUIRED'
const reviewApprovedState: PullRequestReviewState = 'APPROVED'
const changesRequestedState: PullRequestReviewState = 'CHANGES_REQUESTED'
const dismissReviewValidationMessage = 'Please provide a reason for dismissing the review'

const dismissReviewRoute = `${BASE_PAGE_DATA_URL}/page_data/${PageData.dismissReview}`

const reviewerSectionData: ReviewerSectionProps = {
  consolidatedFailureReasons: [],
  numReviewsRequired: 0,
  reviewsState: ConsolidatedReviewState.REVIEWED,
  latestOpinionatedReviews: [
    {
      id: 1,
      authorCanPushToRepository: true,
      author: {
        login: 'octocat',
        name: 'octocat',
        url: '',
        avatarUrl: '',
      },
      onBehalfOf: ['some-team-reviewers'],
      state: reviewApprovedState,
    },
  ],
  pullRequestId: 'PR_123',
  pendingRequestedReviews: [],
  viewerCanDismissReviews: false,
  viewerCanReRequestReviews: false,
  helpUrl: '',
}

function ReviewerSectionTestComponent(props: ReviewerSectionProps) {
  return (
    <PageDataContextProvider basePageDataUrl={BASE_PAGE_DATA_URL}>
      <ReviewerSection {...props} />
    </PageDataContextProvider>
  )
}

describe('reviews are required (pull request rule applies)', () => {
  test('renders reviewer section with no reviewers', async () => {
    const props: ReviewerSectionProps = {
      ...reviewerSectionData,
      numReviewsRequired: 1,
      consolidatedFailureReasons: [moreReviewsFailureReason],
      reviewsState: ConsolidatedReviewState.REVIEW_REQUIRED,
      latestOpinionatedReviews: [],
    }
    render(<ReviewerSection {...props} />)
    expect(screen.getByText('Review required')).toBeInTheDocument()
  })

  test('renders reviewer section with approving review', async () => {
    const props: ReviewerSectionProps = {
      ...reviewerSectionData,
      numReviewsRequired: 1,
      reviewsState: ConsolidatedReviewState.APPROVED,
      latestOpinionatedReviews: [
        {
          id: 1,
          authorCanPushToRepository: true,
          author: {
            login: 'octocat',
            name: 'octocat',
            avatarUrl: '',
            url: '',
          },
          onBehalfOf: ['some-team-reviewers'],
          state: reviewApprovedState,
        },
      ],
    }
    render(<ReviewerSectionTestComponent {...props} />)

    expect(screen.getByText('Changes approved')).toBeInTheDocument()
  })

  test('renders section with one required review and one approving review and one review requesting changes', async () => {
    const props: ReviewerSectionProps = {
      ...reviewerSectionData,
      numReviewsRequired: 1,
      consolidatedFailureReasons: [changesRequestedFailureReason],
      reviewsState: ConsolidatedReviewState.CHANGES_REQUESTED,
      latestOpinionatedReviews: [
        {
          id: 1,
          authorCanPushToRepository: true,
          author: {
            login: 'octocat',
            name: 'octocat',
            avatarUrl: '',
            url: '',
          },
          onBehalfOf: ['some-team-reviewers'],
          state: reviewApprovedState,
        },
        {
          id: 2,
          authorCanPushToRepository: true,
          author: {
            login: 'octokitten',
            name: 'octokitten',
            avatarUrl: '/octokitten',
            url: 'wwww.octokeen.com',
          },
          onBehalfOf: ['some-team-reviewers'],
          state: changesRequestedState,
        },
      ],
    }
    render(<ReviewerSectionTestComponent {...props} />)
    expect(screen.getByText('Changes requested')).toBeInTheDocument()
  })

  test('renders reviewer section with compliance review required and no reviews', async () => {
    const props: ReviewerSectionProps = {
      ...reviewerSectionData,
      numReviewsRequired: 1,
      consolidatedFailureReasons: [socFailureReason],
      reviewsState: ConsolidatedReviewState.REVIEW_REQUIRED,
      latestOpinionatedReviews: [],
    }
    render(<ReviewerSectionTestComponent {...props} />)

    const reviewText = screen.getByText(/review from a compliance team is required/)
    expect(reviewText).toBeInTheDocument()
    expect(screen.getByText('Review required')).toBeInTheDocument()
  })

  test('renders reviewer section with last pusher requirement and no required approvals', async () => {
    const props: ReviewerSectionProps = {
      ...reviewerSectionData,
      numReviewsRequired: 0,
      consolidatedFailureReasons: [moreReviewsFailureReason, lastPushApprovalFailureReason],
      reviewsState: ConsolidatedReviewState.REVIEW_REQUIRED,
      latestOpinionatedReviews: [],
    }
    render(<ReviewerSectionTestComponent {...props} />)

    const reviewText = screen.getByText(/An approval on the most recent push is required/)
    expect(reviewText).toBeInTheDocument()
    expect(screen.getByText('Review required')).toBeInTheDocument()
  })

  test('renders reviewer section with compliance review required and a review requesting changes', async () => {
    const props: ReviewerSectionProps = {
      ...reviewerSectionData,
      numReviewsRequired: 1,
      consolidatedFailureReasons: [changesRequestedFailureReason, socFailureReason],
      reviewsState: ConsolidatedReviewState.REVIEW_REQUIRED,
      latestOpinionatedReviews: [
        {
          id: 1,
          authorCanPushToRepository: true,
          author: {
            login: 'octocat',
            name: 'octocat',
            avatarUrl: '',
            url: '',
          },
          onBehalfOf: ['some-team-reviewers'],
          state: reviewApprovedState,
        },
        {
          id: 2,
          authorCanPushToRepository: true,
          author: {
            login: 'octokitten',
            name: 'octokitten',
            avatarUrl: '/octokitten',
            url: 'wwww.octokeen.com',
          },
          onBehalfOf: ['some-team-reviewers'],
          state: changesRequestedState,
        },
      ],
    }
    render(<ReviewerSectionTestComponent {...props} />)
    const reviewText = screen.getByText(/review from a compliance team is required/)
    expect(reviewText).toBeInTheDocument()
    expect(screen.getByText('Review required')).toBeInTheDocument()
  })

  test('renders reviewer section with 2 reviews required and only 1 approving review', async () => {
    const props: ReviewerSectionProps = {
      ...reviewerSectionData,
      numReviewsRequired: 2,
      consolidatedFailureReasons: [moreReviewsFailureReason],
      reviewsState: ConsolidatedReviewState.REVIEW_REQUIRED,
      latestOpinionatedReviews: [
        {
          id: 1,
          authorCanPushToRepository: true,
          author: {
            login: 'octocat',
            name: 'octocat',
            avatarUrl: '',
            url: '',
          },
          onBehalfOf: ['some-team-reviewers'],
          state: reviewApprovedState,
        },
      ],
    }
    render(<ReviewerSectionTestComponent {...props} />)
    const reviewText = screen.getByText(/At least 2 approving reviews are required/)
    expect(reviewText).toBeInTheDocument()
    expect(screen.getByText('Review required')).toBeInTheDocument()
  })
})

describe('reviews are not required (no pull request rule applies)', () => {
  test('renders reviewer section with no reviews required and an approving review', async () => {
    const props: ReviewerSectionProps = {
      ...reviewerSectionData,
      numReviewsRequired: 0,
      consolidatedFailureReasons: [],
      reviewsState: ConsolidatedReviewState.REVIEWED,
      latestOpinionatedReviews: [
        {
          id: 1,
          authorCanPushToRepository: true,
          author: {
            login: 'octocat',
            name: 'octocat',
            avatarUrl: '',
            url: '',
          },
          onBehalfOf: ['some-team-reviewers'],
          state: reviewApprovedState,
        },
      ],
    }
    render(<ReviewerSectionTestComponent {...props} />)
    expect(screen.getByText('Changes reviewed')).toBeInTheDocument()
  })

  test('renders reviewer section with no reviews required and a review requesting changes', async () => {
    const props: ReviewerSectionProps = {
      ...reviewerSectionData,
      numReviewsRequired: 0,
      consolidatedFailureReasons: [],
      reviewsState: ConsolidatedReviewState.REVIEWED,
      latestOpinionatedReviews: [
        {
          id: 1,
          authorCanPushToRepository: true,
          author: {
            login: 'octocat',
            name: 'octocat',
            avatarUrl: '',
            url: '',
          },
          onBehalfOf: ['some-team-reviewers'],
          state: changesRequestedState,
        },
      ],
    }
    render(<ReviewerSectionTestComponent {...props} />)
    expect(screen.getByText('Changes reviewed')).toBeInTheDocument()
  })
})

test("review summary doesn't count reviews where author cannot push to repository in its total counts", async () => {
  const props: ReviewerSectionProps = {
    ...reviewerSectionData,
    numReviewsRequired: 1,
    consolidatedFailureReasons: [changesRequestedFailureReason],
    reviewsState: ConsolidatedReviewState.CHANGES_REQUESTED,
    latestOpinionatedReviews: [
      {
        id: 1,
        authorCanPushToRepository: true,
        author: {
          login: 'octocat',
          name: 'octocat',
          avatarUrl: '',
          url: '',
        },
        onBehalfOf: ['some-team-reviewers'],
        state: reviewApprovedState,
      },
      {
        id: 2,
        authorCanPushToRepository: false,
        author: {
          login: 'octokitten',
          name: 'octokitten',
          avatarUrl: '/octokitten',
          url: 'wwww.octokeen.com',
        },
        onBehalfOf: [],
        state: reviewApprovedState,
      },
    ],
  }
  render(<ReviewerSectionTestComponent {...props} />)

  expect(screen.getByText(/1 approving review/)).toBeInTheDocument()
})

test('review list item has the proper aria-label', async () => {
  const props = reviewerSectionData

  const {user} = render(<ReviewerSectionTestComponent {...props} />)

  const expandButton = screen.getByLabelText('Expand 1 approval group')
  expect(expandButton).toBeInTheDocument()
  await user.click(expandButton)

  expect(screen.getByLabelText('octocat approved these changes for some-team-reviewers')).toBeInTheDocument()
})

describe('Analytics events', () => {
  test('it emits events when user expands or collapses reviewer section', async () => {
    const props = reviewerSectionData
    const {user} = render(<ReviewerSectionTestComponent {...props} />)

    await user.click(screen.getByRole('button', {name: 'Collapse reviews'}))

    expect(sendAnalyticsEventMock).toHaveBeenCalledWith(
      'reviewers_section.collapse',
      'MERGEBOX_REVIEWERS_SECTION_TOGGLE_BUTTON',
    )

    await user.click(screen.getByRole('button', {name: 'Expand reviews'}))

    expect(sendAnalyticsEventMock).toHaveBeenCalledWith(
      'reviewers_section.expand',
      'MERGEBOX_REVIEWERS_SECTION_TOGGLE_BUTTON',
    )

    // Test that we don't make additional calls
    expect(sendAnalyticsEventMock).toHaveBeenCalledTimes(2)
  })

  test('it emits events when user expands or collapses review groups', async () => {
    const props = {
      ...reviewerSectionData,
      latestOpinionatedReviews: [
        {
          id: 1,
          authorCanPushToRepository: true,
          author: {
            login: 'octocat',
            name: 'octocat',
            avatarUrl: '',
            url: '',
          },
          onBehalfOf: ['some-team-reviewers'],
          state: changesRequestedState,
        },
        {
          id: 2,
          authorCanPushToRepository: false,
          author: {
            login: 'octokitten',
            name: 'octokitten',
            avatarUrl: '/octokitten',
            url: 'wwww.octokeen.com',
          },
          onBehalfOf: [],
          state: reviewApprovedState,
        },
      ],
      pendingRequestedReviews: [
        {
          reviewer: {
            login: 'betty',
            name: 'betty',
            avatarUrl: '',
            url: '',
            type: 'USER',
          },
          isCodeOwner: false,
        } as PendingReviewRequest,
      ],
    }
    const {user} = render(<ReviewerSectionTestComponent {...props} />)

    await user.click(screen.getByRole('button', {name: 'Expand 1 approval group', expanded: false}))

    expect(sendAnalyticsEventMock).toHaveBeenCalledWith(
      'reviewers_group.expand',
      'MERGEBOX_REVIEWERS_GROUP_TOGGLE_BUTTON',
      {group: 'approvals'},
    )

    await user.click(screen.getByRole('button', {name: 'Collapse 1 approval group', expanded: true}))

    expect(sendAnalyticsEventMock).toHaveBeenCalledWith(
      'reviewers_group.collapse',
      'MERGEBOX_REVIEWERS_GROUP_TOGGLE_BUTTON',
      {group: 'approvals'},
    )

    await user.click(screen.getByRole('button', {name: 'Expand 1 requested change group', expanded: false}))

    expect(sendAnalyticsEventMock).toHaveBeenCalledWith(
      'reviewers_group.expand',
      'MERGEBOX_REVIEWERS_GROUP_TOGGLE_BUTTON',
      {group: 'requested changes'},
    )

    await user.click(screen.getByRole('button', {name: 'Collapse 1 requested change group', expanded: true}))

    expect(sendAnalyticsEventMock).toHaveBeenCalledWith(
      'reviewers_group.collapse',
      'MERGEBOX_REVIEWERS_GROUP_TOGGLE_BUTTON',
      {group: 'requested changes'},
    )

    await user.click(screen.getByRole('button', {name: 'Expand 1 pending review group', expanded: false}))

    expect(sendAnalyticsEventMock).toHaveBeenCalledWith(
      'reviewers_group.expand',
      'MERGEBOX_REVIEWERS_GROUP_TOGGLE_BUTTON',
      {group: 'pending reviews'},
    )

    await user.click(screen.getByRole('button', {name: 'Collapse 1 pending review group', expanded: true}))

    expect(sendAnalyticsEventMock).toHaveBeenCalledWith(
      'reviewers_group.collapse',
      'MERGEBOX_REVIEWERS_GROUP_TOGGLE_BUTTON',
      {group: 'pending reviews'},
    )

    // Test that we don't make additional calls
    expect(sendAnalyticsEventMock).toHaveBeenCalledTimes(6)
  })
})

describe('Secondary actions', () => {
  test('it does not render the secondary actions if the user can neither dismiss nor re-request reviews', async () => {
    const props = {
      ...reviewerSectionData,
      latestOpinionatedReviews: [
        {
          id: 1,
          authorCanPushToRepository: true,
          author: {
            login: 'octocat',
            name: 'octocat',
            avatarUrl: '',
            url: '',
          },
          onBehalfOf: ['some-team-reviewers'],
          state: reviewApprovedState,
        },
      ],
    }
    const {user} = render(<ReviewerSectionTestComponent {...props} />)

    const approvalChevron = await screen.findByText('1 approval')
    expect(approvalChevron).toBeInTheDocument()

    await user.click(approvalChevron)

    const reviewOptionsButton = screen.queryByLabelText('More review options')
    expect(reviewOptionsButton).not.toBeInTheDocument()
  })

  test('it does not render the secondary actions if the review has no id (it is a review request, not a review)', async () => {
    const props: ReviewerSectionProps = {
      ...reviewerSectionData,
      pendingRequestedReviews: [
        {
          reviewer: {
            login: 'betty',
            name: 'betty',
            avatarUrl: '',
            url: '',
            type: 'USER',
          },
          isCodeOwner: false,
        },
      ],
      latestOpinionatedReviews: [],
    }
    const {user} = render(<ReviewerSectionTestComponent {...props} />)

    const pendingChevron = await screen.findByText('1 pending review')
    expect(pendingChevron).toBeInTheDocument()

    await user.click(pendingChevron)

    const reviewOptionsButton = screen.queryByLabelText('More review options')
    expect(reviewOptionsButton).not.toBeInTheDocument()
  })
})

describe('Dismiss reviews', () => {
  test('it renders dismiss reviews menu item when user has permission to dismiss reviews', async () => {
    const props: ReviewerSectionProps = {
      ...reviewerSectionData,
      viewerCanDismissReviews: true,
      latestOpinionatedReviews: [
        {
          id: 1,
          authorCanPushToRepository: true,
          author: {
            login: 'octocat',
            name: 'octocat',
            avatarUrl: '',
            url: '',
          },
          onBehalfOf: ['some-team-reviewers'],
          state: reviewApprovedState,
        },
      ],
    }
    const {user} = render(<ReviewerSectionTestComponent {...props} />)

    const approvalChevron = await screen.findByText('1 approval')
    expect(approvalChevron).toBeInTheDocument()

    await user.click(approvalChevron)

    const reviewOptionsButton = screen.getByLabelText('More review options')
    expect(reviewOptionsButton).toBeInTheDocument()
    // Temporary workaround for "Element requested is not a known focusable element"
    // Logged when clicking the review options button
    jest.spyOn(console, 'warn').mockImplementation()
    await user.click(reviewOptionsButton)

    const dismissReviewButton = await screen.findByText('Dismiss review')
    expect(dismissReviewButton).toBeInTheDocument()
  })

  test('it does not render dismiss reviews menu item when user does not have permission to dismiss reviews', async () => {
    const props: ReviewerSectionProps = {
      ...reviewerSectionData,
      viewerCanReRequestReviews: true,
      viewerCanDismissReviews: false,
      latestOpinionatedReviews: [
        {
          id: 1,
          authorCanPushToRepository: true,
          author: {
            login: 'octocat',
            name: 'octocat',
            avatarUrl: '',
            url: '',
          },
          onBehalfOf: ['some-team-reviewers'],
          state: reviewApprovedState,
        },
      ],
    }
    const {user} = render(<ReviewerSectionTestComponent {...props} />)

    const approvalChevron = await screen.findByText('1 approval')
    expect(approvalChevron).toBeInTheDocument()
    await user.click(approvalChevron)

    const reviewOptionsButton = screen.getByLabelText('More review options')
    expect(reviewOptionsButton).toBeInTheDocument()
    // Temporary workaround for "Element requested is not a known focusable element"
    // Logged when clicking the review options button
    jest.spyOn(console, 'warn').mockImplementation()
    await user.click(reviewOptionsButton)

    expect(screen.queryByRole('span', {name: 'Dismiss reviews'})).not.toBeInTheDocument()
  })

  test('when the user activates the dismiss reviews menu item, it opens the dismiss reviews dialog', async () => {
    const props: ReviewerSectionProps = {
      ...reviewerSectionData,
      viewerCanDismissReviews: true,
      latestOpinionatedReviews: [
        {
          id: 1,
          authorCanPushToRepository: true,
          author: {
            login: 'octocat',
            name: 'octocat',
            avatarUrl: '',
            url: '',
          },
          onBehalfOf: ['some-team-reviewers'],
          state: reviewApprovedState,
        },
      ],
    }
    const {user} = render(<ReviewerSectionTestComponent {...props} />)

    const approvalChevron = await screen.findByText('1 approval')
    expect(approvalChevron).toBeInTheDocument()

    await user.click(approvalChevron)

    const reviewOptionsButton = screen.getByLabelText('More review options')
    expect(reviewOptionsButton).toBeInTheDocument()
    // Temporary workaround for "Element requested is not a known focusable element"
    // Logged when clicking the review options button
    jest.spyOn(console, 'warn').mockImplementation()
    await user.click(reviewOptionsButton)

    const dismissReviewButton = await screen.findByText('Dismiss review')
    expect(dismissReviewButton).toBeInTheDocument()
    await user.click(dismissReviewButton)

    const dismissReviewsDialog = await screen.findByRole('dialog')
    expect(dismissReviewsDialog).toBeInTheDocument()

    expect(dismissReviewsDialog).toHaveTextContent(`Reason for dismissing octocat's review`)
    const captionMessage =
      'This reason will appear in the timeline so other users will know why the review was dismissed.'
    expect(dismissReviewsDialog).toHaveTextContent(captionMessage)
  })

  test('cancelling closes the dismiss reviews dialog and returns focus to menu options', async () => {
    const props: ReviewerSectionProps = {
      ...reviewerSectionData,
      viewerCanDismissReviews: true,
      latestOpinionatedReviews: [
        {
          id: 1,
          authorCanPushToRepository: true,
          author: {
            login: 'octocat',
            name: 'octocat',
            avatarUrl: '',
            url: '',
          },
          onBehalfOf: ['some-team-reviewers'],
          state: reviewApprovedState,
        },
      ],
    }
    const {user} = render(<ReviewerSectionTestComponent {...props} />)

    const approvalChevron = await screen.findByText('1 approval')
    expect(approvalChevron).toBeInTheDocument()

    await user.click(approvalChevron)

    const reviewOptionsButton = screen.getByLabelText('More review options')
    expect(reviewOptionsButton).toBeInTheDocument()
    // Temporary workaround for "Element requested is not a known focusable element"
    // Logged when clicking the review options button
    jest.spyOn(console, 'warn').mockImplementation()
    await user.click(reviewOptionsButton)

    const dismissReviewButton = await screen.findByText('Dismiss review')
    expect(dismissReviewButton).toBeInTheDocument()
    await user.click(dismissReviewButton)

    const dismissReviewsDialog = await screen.findByRole('dialog')
    expect(dismissReviewsDialog).toBeInTheDocument()

    const cancelButton = await screen.findByRole('button', {name: 'Cancel'})
    expect(cancelButton).toBeInTheDocument()

    await user.click(cancelButton)

    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
    expect(await screen.findByRole('button', {name: 'More review options'})).toHaveFocus()
  })

  test('validation errors prevent submitting the dismiss review form', async () => {
    const props: ReviewerSectionProps = {
      ...reviewerSectionData,
      viewerCanDismissReviews: true,
      latestOpinionatedReviews: [
        {
          id: 1,
          authorCanPushToRepository: true,
          author: {
            login: 'octocat',
            name: 'octocat',
            avatarUrl: '',
            url: '',
          },
          onBehalfOf: ['some-team-reviewers'],
          state: reviewApprovedState,
        },
      ],
    }
    const {user} = render(<ReviewerSectionTestComponent {...props} />)

    const approvalChevron = await screen.findByText('1 approval')
    expect(approvalChevron).toBeInTheDocument()

    await user.click(approvalChevron)

    const reviewOptionsButton = screen.getByLabelText('More review options')
    expect(reviewOptionsButton).toBeInTheDocument()
    // Temporary workaround for "Element requested is not a known focusable element"
    // Logged when clicking the review options button
    jest.spyOn(console, 'warn').mockImplementation()
    await user.click(reviewOptionsButton)

    const dismissReviewButton = await screen.findByText('Dismiss review')
    expect(dismissReviewButton).toBeInTheDocument()
    await user.click(dismissReviewButton)

    const dismissReviewsDialog = await screen.findByRole('dialog')
    expect(dismissReviewsDialog).toBeInTheDocument()

    // Activating submit button shows the validation error
    const submitButton = screen.getByRole('button', {name: 'Dismiss review'})
    user.click(submitButton)

    const validationError = await screen.findByText(dismissReviewValidationMessage)
    expect(validationError).toBeInTheDocument()

    // No request is made to the server
    mockFetch.mockRoute(dismissReviewRoute, {}, {status: 422, ok: false})
    expect(mockFetch.fetch).not.toHaveBeenCalled()
  })

  test('empty string for reason is not valid', async () => {
    const props: ReviewerSectionProps = {
      ...reviewerSectionData,
      viewerCanDismissReviews: true,
      latestOpinionatedReviews: [
        {
          id: 1,
          authorCanPushToRepository: true,
          author: {
            login: 'octocat',
            name: 'octocat',
            avatarUrl: '',
            url: '',
          },
          onBehalfOf: ['some-team-reviewers'],
          state: reviewApprovedState,
        },
      ],
    }
    const {user} = render(<ReviewerSectionTestComponent {...props} />)

    const approvalChevron = await screen.findByText('1 approval')
    expect(approvalChevron).toBeInTheDocument()

    await user.click(approvalChevron)

    const reviewOptionsButton = screen.getByLabelText('More review options')
    expect(reviewOptionsButton).toBeInTheDocument()
    // Temporary workaround for "Element requested is not a known focusable element"
    // Logged when clicking the review options button
    jest.spyOn(console, 'warn').mockImplementation()
    await user.click(reviewOptionsButton)

    const dismissReviewButton = await screen.findByText('Dismiss review')
    expect(dismissReviewButton).toBeInTheDocument()
    await user.click(dismissReviewButton)

    const dismissReviewsDialog = await screen.findByRole('dialog')
    expect(dismissReviewsDialog).toBeInTheDocument()

    const inputTextarea = screen.getByRole('textbox', {name: /Reason for dismissing/})
    expect(inputTextarea).toBeInTheDocument()
    await user.type(inputTextarea, '        ')

    // Activating submit button displays validation error
    const submitButton = screen.getByRole('button', {name: 'Dismiss review'})
    user.click(submitButton)
    expect(await screen.findByText(dismissReviewValidationMessage)).toBeInTheDocument()

    // No request is made to the server
    mockFetch.mockRoute(dismissReviewRoute, {}, {status: 422, ok: false})
    expect(mockFetch.fetch).not.toHaveBeenCalled()
  })

  test('successfully submitting the dismiss review form shows a loading state, then closes the dialog', async () => {
    const props: ReviewerSectionProps = {
      ...reviewerSectionData,
      viewerCanDismissReviews: true,
      latestOpinionatedReviews: [
        {
          id: 1,
          authorCanPushToRepository: true,
          author: {
            login: 'octocat',
            name: 'octocat',
            avatarUrl: '',
            url: '',
          },
          onBehalfOf: ['some-team-reviewers'],
          state: reviewApprovedState,
        },
      ],
    }
    const {user} = render(<ReviewerSectionTestComponent {...props} />)

    const approvalChevron = await screen.findByText('1 approval')
    expect(approvalChevron).toBeInTheDocument()

    await user.click(approvalChevron)

    const reviewOptionsButton = screen.getByLabelText('More review options')
    expect(reviewOptionsButton).toBeInTheDocument()
    // Temporary workaround for "Element requested is not a known focusable element"
    // Logged when clicking the review options button
    jest.spyOn(console, 'warn').mockImplementation()
    await user.click(reviewOptionsButton)

    const dismissReviewButton = await screen.findByText('Dismiss review')
    expect(dismissReviewButton).toBeInTheDocument()
    await user.click(dismissReviewButton)

    const dismissReviewsDialog = await screen.findByRole('dialog')
    expect(dismissReviewsDialog).toBeInTheDocument()

    const submitButton = screen.getByRole('button', {name: 'Dismiss review'})
    await user.click(submitButton)

    const inputTextarea = screen.getByRole('textbox', {name: /Reason for dismissing/})
    expect(inputTextarea).toBeInTheDocument()
    await user.type(inputTextarea, 'This is stale!')

    // Submitting actually makes a request when there is a reason
    mockFetch.mockRoute(dismissReviewRoute, {}, {status: 200, ok: true})
    await user.click(submitButton)

    expect(mockFetch.fetch).toHaveBeenCalled()
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
  })

  test('clearing dismissal message does not show validation error until submit is pressed again', async () => {
    const props: ReviewerSectionProps = {
      ...reviewerSectionData,
      viewerCanDismissReviews: true,
      latestOpinionatedReviews: [
        {
          id: 1,
          authorCanPushToRepository: true,
          author: {
            login: 'octocat',
            name: 'octocat',
            avatarUrl: '',
            url: '',
          },
          onBehalfOf: ['some-team-reviewers'],
          state: reviewApprovedState,
        },
      ],
    }
    const {user} = render(<ReviewerSectionTestComponent {...props} />)

    const approvalChevron = await screen.findByText('1 approval')
    expect(approvalChevron).toBeInTheDocument()

    await user.click(approvalChevron)

    const reviewOptionsButton = screen.getByLabelText('More review options')
    expect(reviewOptionsButton).toBeInTheDocument()
    // Temporary workaround for "Element requested is not a known focusable element"
    // Logged when clicking the review options button
    jest.spyOn(console, 'warn').mockImplementation()
    await user.click(reviewOptionsButton)

    const dismissReviewButton = await screen.findByText('Dismiss review')
    expect(dismissReviewButton).toBeInTheDocument()
    await user.click(dismissReviewButton)

    const dismissReviewsDialog = await screen.findByRole('dialog')
    expect(dismissReviewsDialog).toBeInTheDocument()

    const submitButton = screen.getByRole('button', {name: 'Dismiss review'})
    await user.click(submitButton)

    // Show the validation error on submit
    const validationError = await screen.findByText('Please provide a reason for dismissing the review')
    expect(validationError).toBeInTheDocument()

    const inputTextarea = screen.getByRole('textbox', {name: /Reason for dismissing/})
    expect(inputTextarea).toBeInTheDocument()

    // Clear the validation error
    await user.type(inputTextarea, 'A')

    // Clearing message doesn't show validation message again until submit is attempted
    await user.type(inputTextarea, '{Backspace}')
    expect(screen.queryByText(dismissReviewValidationMessage)).not.toBeInTheDocument()
  })

  test('unsuccessfully submitting the dismiss review form shows an error state and leaves dialog open', async () => {
    const props: ReviewerSectionProps = {
      ...reviewerSectionData,
      viewerCanDismissReviews: true,
      latestOpinionatedReviews: [
        {
          id: 1,
          authorCanPushToRepository: true,
          author: {
            login: 'octocat',
            name: 'octocat',
            avatarUrl: '',
            url: '',
          },
          onBehalfOf: ['some-team-reviewers'],
          state: reviewApprovedState,
        },
      ],
    }
    const {user} = render(<ReviewerSectionTestComponent {...props} />)

    const approvalChevron = await screen.findByText('1 approval')
    expect(approvalChevron).toBeInTheDocument()

    await user.click(approvalChevron)

    const reviewOptionsButton = screen.getByLabelText('More review options')
    expect(reviewOptionsButton).toBeInTheDocument()
    // Temporary workaround for "Element requested is not a known focusable element"
    // Logged when clicking the review options button
    jest.spyOn(console, 'warn').mockImplementation()
    await user.click(reviewOptionsButton)

    const dismissReviewButton = await screen.findByText('Dismiss review')
    expect(dismissReviewButton).toBeInTheDocument()
    await user.click(dismissReviewButton)

    const dismissReviewsDialog = await screen.findByRole('dialog')
    expect(dismissReviewsDialog).toBeInTheDocument()

    const inputTextarea = screen.getByRole('textbox', {name: /Reason for dismissing/})
    expect(inputTextarea).toBeInTheDocument()

    await user.type(inputTextarea, 'This is a test reason')

    const submitButton = screen.getByRole('button', {name: 'Dismiss review'})
    mockFetch.mockRoute(dismissReviewRoute, {error: 'Could not dismiss review'}, {status: 422, ok: false})
    await user.click(submitButton)

    expect(await screen.findByRole('dialog')).toBeInTheDocument()

    expect(await screen.findByText('Could not dismiss review')).toBeInTheDocument()
    expect(mockFetch.fetch).toHaveBeenCalled()
  })
})

describe('Re-request reviews', () => {
  test('it renders re-request reviews button when user has permission to re-request reviews', async () => {
    const props: ReviewerSectionProps = {
      ...reviewerSectionData,
      latestOpinionatedReviews: [
        {
          id: 1,
          authorCanPushToRepository: true,
          author: {
            login: 'octocat',
            name: 'octocat',
            avatarUrl: '',
            url: '',
          },
          onBehalfOf: ['some-team-reviewers'],
          state: reviewApprovedState,
        },
      ],
      viewerCanReRequestReviews: true,
    }
    render(<ReviewerSectionTestComponent {...props} />)

    const approvalChevron = await screen.findByText('1 approval')
    expect(approvalChevron).toBeInTheDocument()

    // eslint-disable-next-line testing-library/prefer-user-event
    fireEvent.click(approvalChevron)

    const reviewOptionsButton = await screen.findByLabelText('More review options')
    expect(reviewOptionsButton).toBeInTheDocument()
    // eslint-disable-next-line testing-library/prefer-user-event
    fireEvent.click(reviewOptionsButton)

    const reRequestReviewButton = await screen.findByText('Re-request review')
    expect(reRequestReviewButton).toBeInTheDocument()
  })

  test('it does not render re-request reviews button when user does not have permission to re-request reviews', async () => {
    const props: ReviewerSectionProps = {
      ...reviewerSectionData,
      latestOpinionatedReviews: [
        {
          id: 1,
          authorCanPushToRepository: true,
          author: {
            login: 'octocat',
            name: 'octocat',
            avatarUrl: '',
            url: '',
          },
          onBehalfOf: ['some-team-reviewers'],
          state: reviewApprovedState,
        },
      ],
      viewerCanDismissReviews: true,
      viewerCanReRequestReviews: false,
    }

    render(<ReviewerSectionTestComponent {...props} />)

    const approvalChevron = await screen.findByText('1 approval')
    expect(approvalChevron).toBeInTheDocument()

    // eslint-disable-next-line testing-library/prefer-user-event
    fireEvent.click(approvalChevron)

    const reviewOptionsButton = await screen.findByLabelText('More review options')
    expect(reviewOptionsButton).toBeInTheDocument()

    // eslint-disable-next-line testing-library/prefer-user-event
    fireEvent.click(reviewOptionsButton)

    expect(screen.queryByRole('span', {name: 'Re-request reviews'})).not.toBeInTheDocument()
  })
})
