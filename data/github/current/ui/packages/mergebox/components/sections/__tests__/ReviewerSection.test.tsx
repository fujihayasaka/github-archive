import {render} from '@github-ui/react-core/test-utils'
import {useAnalytics} from '@github-ui/use-analytics'
import {fireEvent, screen} from '@testing-library/react'

import type {PullRequestReviewState, PullRequestRuleFailureReason, PendingReviewRequest} from '../../../types'
import type {ReviewerSectionProps} from '../ReviewerSection'
import {ConsolidatedReviewState, getReviewsState, ReviewerSection} from '../ReviewerSection'
import {PageDataContextProvider} from '@github-ui/pull-request-page-data-tooling/page-data-context'
import {BASE_PAGE_DATA_URL} from '@github-ui/pull-request-page-data-tooling/render-with-query-client'
import queryClient from '@github-ui/pull-request-page-data-tooling/query-client'
import {QueryClientProvider} from '@tanstack/react-query'

jest.mock('@github-ui/use-analytics')
const sendAnalyticsEventMock = jest.fn()
jest.mocked(useAnalytics).mockReturnValue({sendAnalyticsEvent: sendAnalyticsEventMock})

beforeEach(() => sendAnalyticsEventMock.mockReset())

const moreReviewsFailureReason: PullRequestRuleFailureReason = 'MORE_REVIEWS_REQUIRED'
const changesRequestedFailureReason: PullRequestRuleFailureReason = 'CHANGES_REQUESTED'
const socFailureReason: PullRequestRuleFailureReason = 'SOC2_APPROVAL_PROCESS_REQUIRED'
const lastPushApprovalFailureReason: PullRequestRuleFailureReason = 'LAST_PUSH_APPROVAL_REQUIRED'
const reviewApprovedState: PullRequestReviewState = 'APPROVED'
const changesRequestedState: PullRequestReviewState = 'CHANGES_REQUESTED'

const reviewerSectionData = {
  reviewerRuleRollups: [],
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
  refetchMergeBoxQuery: jest.fn(),
  pendingRequestedReviews: [],
  viewerCanDismissReviews: true,
  viewerCanReRequestReviews: true,
}

function ReviewerSectionTestComponent(props: ReviewerSectionProps) {
  return (
    <PageDataContextProvider basePageDataUrl={BASE_PAGE_DATA_URL}>
      <QueryClientProvider client={queryClient}>
        <ReviewerSection {...props} />
      </QueryClientProvider>
    </PageDataContextProvider>
  )
}

describe('getReviewsState', () => {
  it('returns APPROVED when there are no failure reasons and at least one review', () => {
    const reviewsRequired = 1
    const isCodeownersRequired = false
    const reviews: Array<{readonly authorCanPushToRepository: boolean; readonly state: PullRequestReviewState}> = [
      {
        authorCanPushToRepository: false,
        state: 'APPROVED',
      },
    ]
    const failureReasons: PullRequestRuleFailureReason[] = []

    expect(getReviewsState(reviewsRequired, isCodeownersRequired, reviews, failureReasons)).toBe(
      ConsolidatedReviewState.APPROVED,
    )
  })

  it('returns APPROVED when there are no failure reasons and codeowners review is required', () => {
    const reviewsRequired = 0
    const isCodeownersRequired = true
    const reviews: Array<{readonly authorCanPushToRepository: boolean; readonly state: PullRequestReviewState}> = [
      {
        authorCanPushToRepository: false,
        state: 'APPROVED',
      },
    ]
    const failureReasons: PullRequestRuleFailureReason[] = []

    expect(getReviewsState(reviewsRequired, isCodeownersRequired, reviews, failureReasons)).toBe(
      ConsolidatedReviewState.APPROVED,
    )
  })

  it('returns REVIEW_REQUIRED when there are failure reasons that require more reviews', () => {
    const reviewsRequired = 2
    const isCodeownersRequired = false
    const reviews: Array<{readonly authorCanPushToRepository: boolean; readonly state: PullRequestReviewState}> = [
      {
        authorCanPushToRepository: false,
        state: 'APPROVED',
      },
    ]
    const failureReasons: PullRequestRuleFailureReason[] = ['MORE_REVIEWS_REQUIRED']

    expect(getReviewsState(reviewsRequired, isCodeownersRequired, reviews, failureReasons)).toBe(
      ConsolidatedReviewState.REVIEW_REQUIRED,
    )
  })

  it('returns REVIEW_REQUIRED when there are failure reasons that require codeowners review', () => {
    const reviewsRequired = 0
    const isCodeownersRequired = true
    const reviews: Array<{readonly authorCanPushToRepository: boolean; readonly state: PullRequestReviewState}> = [
      {
        authorCanPushToRepository: false,
        state: 'APPROVED',
      },
    ]
    const failureReasons: PullRequestRuleFailureReason[] = ['CODE_OWNER_REVIEW_REQUIRED']

    expect(getReviewsState(reviewsRequired, isCodeownersRequired, reviews, failureReasons)).toBe(
      ConsolidatedReviewState.REVIEW_REQUIRED,
    )
  })

  it('returns REVIEW_REQUIRED when there are failure reasons that require SOC2 approval process', () => {
    const reviewsRequired = 0
    const isCodeownersRequired = false
    const reviews: Array<{readonly authorCanPushToRepository: boolean; readonly state: PullRequestReviewState}> = [
      {
        authorCanPushToRepository: false,
        state: 'APPROVED',
      },
    ]
    const failureReasons: PullRequestRuleFailureReason[] = ['SOC2_APPROVAL_PROCESS_REQUIRED']

    expect(getReviewsState(reviewsRequired, isCodeownersRequired, reviews, failureReasons)).toBe(
      ConsolidatedReviewState.REVIEW_REQUIRED,
    )
  })

  it('returns CHANGES_REQUESTED when there are failure reasons that require changes', () => {
    const reviewsRequired = 0
    const isCodeownersRequired = false
    const reviews: Array<{readonly authorCanPushToRepository: boolean; readonly state: PullRequestReviewState}> = [
      {
        authorCanPushToRepository: false,
        state: 'APPROVED',
      },
    ]
    const failureReasons: PullRequestRuleFailureReason[] = ['CHANGES_REQUESTED']

    expect(getReviewsState(reviewsRequired, isCodeownersRequired, reviews, failureReasons)).toBe(
      ConsolidatedReviewState.CHANGES_REQUESTED,
    )
  })

  it('returns REVIEW_REQUIRED when there are failure reasons that require changes and more reviews', () => {
    const reviewsRequired = 2
    const isCodeownersRequired = false
    const reviews: Array<{readonly authorCanPushToRepository: boolean; readonly state: PullRequestReviewState}> = [
      {
        authorCanPushToRepository: false,
        state: 'APPROVED',
      },
    ]
    const failureReasons: PullRequestRuleFailureReason[] = ['CHANGES_REQUESTED', 'MORE_REVIEWS_REQUIRED']

    expect(getReviewsState(reviewsRequired, isCodeownersRequired, reviews, failureReasons)).toBe(
      ConsolidatedReviewState.REVIEW_REQUIRED,
    )
  })

  it('returns REVIEWED when there are no failure reasons and at least one review and no reviews are required', () => {
    const reviewsRequired = 0
    const isCodeownersRequired = false
    const reviews: Array<{readonly authorCanPushToRepository: boolean; readonly state: PullRequestReviewState}> = [
      {
        authorCanPushToRepository: false,
        state: 'APPROVED',
      },
    ]
    const failureReasons: PullRequestRuleFailureReason[] = []

    expect(getReviewsState(reviewsRequired, isCodeownersRequired, reviews, failureReasons)).toBe(
      ConsolidatedReviewState.REVIEWED,
    )
  })
})

describe('reviews are required (pull request rule applies)', () => {
  test('renders reviewer section with no reviewers', async () => {
    const props = {
      ...reviewerSectionData,
      reviewerRuleRollups: [
        {
          requiredReviewers: 1,
          requiresCodeowners: false,
          failureReasons: [moreReviewsFailureReason],
        },
      ],
      latestOpinionatedReviews: [],
    }
    render(<ReviewerSection {...props} />)
    expect(screen.getByText('Review required')).toBeInTheDocument()
  })

  test('renders reviewer section with approving review', async () => {
    const props = {
      ...reviewerSectionData,
      reviewerRuleRollups: [
        {
          requiredReviewers: 1,
          requiresCodeowners: false,
          failureReasons: [],
        },
      ],
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
    const props = {
      ...reviewerSectionData,
      reviewerRuleRollups: [
        {
          requiredReviewers: 1,
          requiresCodeowners: false,
          failureReasons: [changesRequestedFailureReason],
        },
      ],
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
    const props = {
      ...reviewerSectionData,
      reviewerRuleRollups: [
        {
          requiredReviewers: 1,
          requiresCodeowners: false,
          failureReasons: [socFailureReason],
        },
      ],
      latestOpinionatedReviews: [],
    }
    render(<ReviewerSectionTestComponent {...props} />)

    const reviewText = screen.getByText(/review from a compliance team is required/)
    expect(reviewText).toBeInTheDocument()
    screen.getByText('Review required')
  })

  test('renders reviewer section with last pusher requirement and no required approvals', async () => {
    const props = {
      ...reviewerSectionData,
      reviewerRuleRollups: [
        {
          requiredReviewers: 0,
          requiresCodeowners: false,
          failureReasons: [moreReviewsFailureReason, lastPushApprovalFailureReason],
        },
      ],
      latestOpinionatedReviews: [],
    }
    render(<ReviewerSectionTestComponent {...props} />)

    const reviewText = screen.getByText(/An approval on the most recent push is required/)
    expect(reviewText).toBeInTheDocument()
    screen.getByText('Review required')
  })

  test('renders reviewer section with compliance review required and a review requesting changes', async () => {
    const props = {
      ...reviewerSectionData,
      reviewerRuleRollups: [
        {
          requiredReviewers: 1,
          requiresCodeowners: false,
          failureReasons: [changesRequestedFailureReason, socFailureReason],
        },
      ],
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
    screen.getByText('Review required')
  })

  test('renders reviewer section with 2 reviews required and only 1 approving review', async () => {
    const props = {
      ...reviewerSectionData,
      reviewerRuleRollups: [
        {
          requiredReviewers: 2,
          requiresCodeowners: false,
          failureReasons: [moreReviewsFailureReason],
        },
      ],
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
    screen.getByText('Review required')
  })
})

describe('reviews are not required (no pull request rule applies)', () => {
  test('renders reviewer section with no reviews required and an approving review', async () => {
    const props = {
      ...reviewerSectionData,
      reviewerRuleRollups: [],
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
    const props = {
      ...reviewerSectionData,
      reviewerRuleRollups: [],
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

  test('does not render reviewer section if no reviews are required and there are no reviews', async () => {
    const props = {
      ...reviewerSectionData,
      reviewerRuleRollups: [
        {
          requiredReviewers: 0,
          requiresCodeowners: false,
          failureReasons: [],
        },
      ],
      latestOpinionatedReviews: [],
    }
    render(<ReviewerSectionTestComponent {...props} />)

    expect(screen.queryByText(/Review required/)).not.toBeInTheDocument()
    expect(screen.queryByText(/Changes approved/)).not.toBeInTheDocument()
    expect(screen.queryByText(/Changes reviewed/)).not.toBeInTheDocument()
    expect(screen.queryByText(/Changes requested/)).not.toBeInTheDocument()
  })
})

test("review summary doesn't count reviews where author cannot push to repository in its total counts", async () => {
  const props = {
    ...reviewerSectionData,
    reviewerRuleRollups: [
      {
        requiredReviewers: 1,
        requiresCodeowners: false,
        failureReasons: [changesRequestedFailureReason],
      },
    ],
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

describe('Dismiss reviews', () => {
  test('it renders dismiss reviews button when user has permission to dismiss reviews', async () => {
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
    render(<ReviewerSectionTestComponent {...props} />)

    const approvalChevron = await screen.findByText('1 approval')
    expect(approvalChevron).toBeInTheDocument()

    // eslint-disable-next-line testing-library/prefer-user-event
    fireEvent.click(approvalChevron)

    const reviewOptionsButton = screen.getByLabelText('Review options')
    expect(reviewOptionsButton).toBeInTheDocument()
    // eslint-disable-next-line testing-library/prefer-user-event
    fireEvent.click(reviewOptionsButton)

    const dismissReviewButton = await screen.findByText('Dismiss review')
    expect(dismissReviewButton).toBeInTheDocument()
  })

  test('it does not render dismiss reviews button when user does not have permission to dismiss reviews', async () => {
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
      viewerCanDismissReviews: false,
    }
    render(<ReviewerSectionTestComponent {...props} />)

    const approvalChevron = await screen.findByText('1 approval')
    expect(approvalChevron).toBeInTheDocument()

    // eslint-disable-next-line testing-library/prefer-user-event
    fireEvent.click(approvalChevron)

    const reviewOptionsButton = screen.getByLabelText('Review options')
    expect(reviewOptionsButton).toBeInTheDocument()

    // eslint-disable-next-line testing-library/prefer-user-event
    fireEvent.click(reviewOptionsButton)

    expect(screen.queryByRole('span', {name: 'Dismiss reviews'})).not.toBeInTheDocument()
  })

  test('when the user clicks the dismiss reviews button, it opens the dismiss reviews dialog', async () => {
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
    render(<ReviewerSectionTestComponent {...props} />)

    const approvalChevron = await screen.findByText('1 approval')
    expect(approvalChevron).toBeInTheDocument()

    // eslint-disable-next-line testing-library/prefer-user-event
    fireEvent.click(approvalChevron)

    const reviewOptionsButton = screen.getByLabelText('Review options')
    expect(reviewOptionsButton).toBeInTheDocument()
    // eslint-disable-next-line testing-library/prefer-user-event
    fireEvent.click(reviewOptionsButton)

    const dismissReviewButton = await screen.findByText('Dismiss review')
    expect(dismissReviewButton).toBeInTheDocument()
    // eslint-disable-next-line testing-library/prefer-user-event
    fireEvent.click(dismissReviewButton)

    const dismissReviewsDialog = await screen.findByRole('dialog')
    expect(dismissReviewsDialog).toBeInTheDocument()

    expect(dismissReviewsDialog).toHaveTextContent('Reason for dismissing')
  })
})

describe('Re-request reviews', () => {
  test('it renders re-request reviews button when user has permission to re-request reviews', async () => {
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
    render(<ReviewerSectionTestComponent {...props} />)

    const approvalChevron = await screen.findByText('1 approval')
    expect(approvalChevron).toBeInTheDocument()

    // eslint-disable-next-line testing-library/prefer-user-event
    fireEvent.click(approvalChevron)

    const reviewOptionsButton = screen.getByLabelText('Review options')
    expect(reviewOptionsButton).toBeInTheDocument()
    // eslint-disable-next-line testing-library/prefer-user-event
    fireEvent.click(reviewOptionsButton)

    const reRequestReviewButton = await screen.findByText('Re-request review')
    expect(reRequestReviewButton).toBeInTheDocument()
  })

  test('it does not render re-request reviews button when user does not have permission to re-request reviews', async () => {
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
      viewerCanReRequestReviews: false,
    }

    render(<ReviewerSectionTestComponent {...props} />)

    const approvalChevron = await screen.findByText('1 approval')
    expect(approvalChevron).toBeInTheDocument()

    // eslint-disable-next-line testing-library/prefer-user-event
    fireEvent.click(approvalChevron)

    const reviewOptionsButton = screen.getByLabelText('Review options')
    expect(reviewOptionsButton).toBeInTheDocument()

    // eslint-disable-next-line testing-library/prefer-user-event
    fireEvent.click(reviewOptionsButton)

    expect(screen.queryByRole('span', {name: 'Re-request reviews'})).not.toBeInTheDocument()
  })
})
