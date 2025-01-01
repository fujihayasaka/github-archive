import type {Meta, StoryObj} from '@storybook/react'
import {within, expect, userEvent} from '@storybook/test'
import {shouldInteractionPlay} from '@github-ui/storybook'

import {ConsolidatedReviewState, ReviewerSection, type ReviewerSectionProps} from './ReviewerSection'

import type {Author, PendingReviewRequest} from '../../types'
import {PageDataContextProvider} from '@github-ui/pull-request-page-data-tooling/page-data-context'
import {BASE_PAGE_DATA_URL} from '@github-ui/pull-request-page-data-tooling/render-with-query-client'
import {delay, http, HttpResponse} from 'msw'
import {PageData} from '@github-ui/pull-request-page-data-tooling/page-data'

const dismissReviewRoute = `${BASE_PAGE_DATA_URL}/page_data/${PageData.dismissReview}`

const meta: Meta<typeof ReviewerSection> = {
  title: 'Pull Requests/Merge Box/ReviewerSection',
  component: ReviewerSection,
  beforeEach: () => {
    // Erase all stored content in the local storage before each test as comments are stored in local storage
    sessionStorage.clear()
  },
  parameters: {
    msw: {
      handlers: [
        http.post(dismissReviewRoute, async () => {
          await delay()
          return HttpResponse.json({error: 'Unable to dismiss review'}, {status: 422})
        }),
      ],
    },
  },
}

type Story = StoryObj<typeof ReviewerSection>

const disabledArg = {
  table: {
    disable: true,
  },
}

const argTypes = {
  latestOpinionatedReviews: disabledArg,
  pendingRequestedReviews: disabledArg,
  reviewerRuleRollups: disabledArg,
}

const reviewAuthor: Author = {
  login: 'octocat',
  name: 'Octo Cat',
  avatarUrl: 'https://avatars.githubusercontent.com/desktop',
  url: 'https://github.com/octocat',
}

const userReviewRequest: PendingReviewRequest = {
  reviewer: {
    login: 'betty',
    name: 'Betty',
    avatarUrl: 'https://avatars.githubusercontent.com/github',
    url: 'https://github.com/betty',
    type: 'USER',
  },
  isCodeOwner: false,
}

const codeownerUserReviewRequest: PendingReviewRequest = {
  reviewer: {
    login: 'juan-mayor',
    name: 'Juan Mayor',
    avatarUrl: 'https://avatars.githubusercontent.com/github',
    url: 'https://github.com/juan-mayor',
    type: 'USER',
  },
  isCodeOwner: true,
}

const codeownerTeamReviewRequest: PendingReviewRequest = {
  reviewer: {
    login: 'testorg-fa71044edc2c/team-5559f4e458ef',
    name: 'team-5559f4e458ef',
    avatarUrl: 'https://avatars.githubusercontent.com/atom',
    url: 'https://github.com/orgs/testorg-fa71044edc2c/teams/team-5559f4e458ef',
    type: 'TEAM',
  },
  isCodeOwner: true,
}

function ReviewerSectionStoryComponent(props: ReviewerSectionProps) {
  return (
    <PageDataContextProvider basePageDataUrl={BASE_PAGE_DATA_URL}>
      <ReviewerSection {...props} />
    </PageDataContextProvider>
  )
}

export const ChangesRequested: Story = {
  argTypes,
  render: () => (
    <ReviewerSectionStoryComponent
      latestOpinionatedReviews={[
        {
          id: 1,
          state: 'CHANGES_REQUESTED',
          author: reviewAuthor,
          authorCanPushToRepository: true,
          onBehalfOf: ['special-reviewer-team'],
        },
      ]}
      pendingRequestedReviews={[]}
      pullRequestId="PR_123"
      numReviewsRequired={1}
      reviewsState={ConsolidatedReviewState.CHANGES_REQUESTED}
      consolidatedFailureReasons={['CHANGES_REQUESTED']}
      helpUrl="https://help.github.com"
      viewerCanDismissReviews
      viewerCanReRequestReviews
    />
  ),
  play: async ({canvasElement, step}) => {
    if (!shouldInteractionPlay()) return

    const canvas = within(canvasElement)
    let groupButton: HTMLElement
    const requestedChangesText = 'Requested changes'

    await step('assert the correct section header info is rendered', async () => {
      expect(await canvas.findByText('Changes requested')).toBeInTheDocument()
      expect(canvas.getByText('1 change requested by reviewers with write access.')).toBeInTheDocument()
    })

    await step('assert that the requested changes group button is rendered, but not expanded', async () => {
      groupButton = await canvas.findByRole('button', {name: 'Expand 1 requested change group', expanded: false})
    })

    await step('assert that the review in the requested changes group is not visible before expanding', async () => {
      expect(canvas.queryByText(reviewAuthor.login)).not.toBeInTheDocument()
      expect(canvas.queryByText(requestedChangesText)).not.toBeInTheDocument()
    })

    await step(
      'assert that clicking on the requested changes group button will render the requested change review',
      async () => {
        await userEvent.click(groupButton)
        expect(await canvas.findByText(reviewAuthor.login)).toBeVisible()
        expect(canvas.getByText(requestedChangesText)).toBeVisible()
      },
    )
  },
}

export const CodeownerReviewRequired: Story = {
  argTypes,
  render: () => (
    <ReviewerSectionStoryComponent
      latestOpinionatedReviews={[
        {
          id: 1,
          state: 'APPROVED',
          author: reviewAuthor,
          authorCanPushToRepository: true,
          onBehalfOf: ['special-reviewer-team'],
        },
      ]}
      pendingRequestedReviews={[codeownerUserReviewRequest, codeownerTeamReviewRequest]}
      pullRequestId="PR_123"
      numReviewsRequired={1}
      reviewsState={ConsolidatedReviewState.REVIEW_REQUIRED}
      consolidatedFailureReasons={['CODE_OWNER_REVIEW_REQUIRED']}
      helpUrl="https://help.github.com"
      viewerCanDismissReviews
      viewerCanReRequestReviews
    />
  ),
  play: async ({canvasElement, step}) => {
    if (!shouldInteractionPlay()) return

    const canvas = within(canvasElement)
    let groupButton: HTMLElement
    const codeownerRequestedText = 'was requested for review as a codeowner'

    await step('assert the correct section header info is rendered', async () => {
      await expect(canvas.getByText('Review required')).toBeInTheDocument()
      expect(canvas.getByText('Code owner review required by reviewers with write access.')).toBeInTheDocument()
    })

    await step(
      'assert that the requested changes and pending reviews group buttons are rendered, but not expanded',
      async () => {
        expect(
          await canvas.findByRole('button', {name: 'Expand 1 approval group', expanded: false}),
        ).toBeInTheDocument()
        groupButton = canvas.getByRole('button', {name: 'Expand 2 pending reviews group', expanded: false})
      },
    )

    await step('assert that the reviews in the pending reviews group are not visible before expanding', async () => {
      expect(canvas.queryByText(codeownerUserReviewRequest.reviewer!.login)).not.toBeInTheDocument()
      expect(canvas.queryByText(codeownerTeamReviewRequest.reviewer!.login)).not.toBeInTheDocument()
      // eslint-disable-next-line github/array-foreach
      canvas.queryAllByText(codeownerRequestedText).forEach(el => expect(el).not.toBeInTheDocument())
    })

    await step('assert that clicking on the pending reviews group button will render the pending reviews', async () => {
      await userEvent.click(groupButton)
      expect(await canvas.findByText(codeownerUserReviewRequest.reviewer!.login)).toBeVisible()
      expect(canvas.getByText(codeownerTeamReviewRequest.reviewer!.login)).toBeVisible()
      // eslint-disable-next-line github/array-foreach
      canvas.getAllByText(codeownerRequestedText).forEach(el => expect(el).toBeVisible())
    })
  },
}

export const NoReviewRequired: Story = {
  argTypes,
  render: () => (
    <ReviewerSectionStoryComponent
      latestOpinionatedReviews={[
        {
          id: 1,
          state: 'APPROVED',
          author: reviewAuthor,
          authorCanPushToRepository: true,
          onBehalfOf: ['special-reviewer-team'],
        },
      ]}
      pendingRequestedReviews={[]}
      pullRequestId="PR_123"
      numReviewsRequired={0}
      reviewsState={ConsolidatedReviewState.REVIEWED}
      consolidatedFailureReasons={[]}
      helpUrl="https://help.github.com"
      viewerCanDismissReviews
      viewerCanReRequestReviews
    />
  ),
  play: async ({canvasElement, step}) => {
    if (!shouldInteractionPlay()) return

    const canvas = within(canvasElement)
    let groupButton: HTMLElement
    const reviewerText = 'Approved these changes for special-reviewer-team'

    await step('assert the correct section header info is rendered', async () => {
      expect(await canvas.findByText('Changes reviewed')).toBeInTheDocument()
      expect(canvas.getByText('1 approving review by reviewers with write access.')).toBeInTheDocument()
    })

    await step('assert that the approval reviews group button is rendered, but not expanded', async () => {
      groupButton = await canvas.findByRole('button', {name: 'Expand 1 approval group', expanded: false})
    })

    await step('assert that the review in the review group is not visible before expanding', async () => {
      expect(canvas.queryByText(reviewAuthor.login)).not.toBeInTheDocument()
      expect(canvas.queryByText(reviewerText)).not.toBeInTheDocument()
    })

    await step(
      'assert that clicking on the approval reviews group button will render the approval review',
      async () => {
        await userEvent.click(groupButton)
        expect(await canvas.findByText(reviewAuthor.login)).toBeVisible()
        expect(canvas.getByText(reviewerText)).toBeVisible()
      },
    )
  },
}

export const Approved: Story = {
  argTypes,
  render: () => (
    <ReviewerSectionStoryComponent
      latestOpinionatedReviews={[
        {
          id: 1,
          state: 'APPROVED',
          author: reviewAuthor,
          authorCanPushToRepository: true,
          onBehalfOf: ['special-reviewer-team', 'another-reviewer-team'],
        },
      ]}
      pendingRequestedReviews={[]}
      pullRequestId="PR_123"
      numReviewsRequired={1}
      reviewsState={ConsolidatedReviewState.APPROVED}
      consolidatedFailureReasons={[]}
      helpUrl="https://help.github.com"
      viewerCanDismissReviews
      viewerCanReRequestReviews
    />
  ),
  play: async ({canvasElement, step}) => {
    if (!shouldInteractionPlay()) return

    const canvas = within(canvasElement)
    let groupButton: HTMLElement
    const reviewerText = 'Approved these changes for special-reviewer-team and another-reviewer-team'

    await step('assert the correct section header info is rendered', async () => {
      expect(await canvas.findByText('Changes approved')).toBeInTheDocument()
      expect(canvas.getByText('1 approving review by reviewers with write access.')).toBeInTheDocument()
    })

    await step('assert that the approval reviews group button is rendered, but not expanded', async () => {
      groupButton = await canvas.findByRole('button', {name: 'Expand 1 approval group', expanded: false})
    })

    await step('assert that the review in the approval reviews group is not visible before expanding', async () => {
      expect(canvas.queryByText(reviewAuthor.login)).not.toBeInTheDocument()
      expect(canvas.queryByText(reviewerText)).not.toBeInTheDocument()
    })

    await step(
      'assert that clicking on the approval reviews group button will render the approval review',
      async () => {
        await userEvent.click(groupButton)
        expect(await canvas.findByText(reviewAuthor.login)).toBeVisible()
        expect(canvas.getByText(reviewerText)).toBeVisible()
      },
    )
  },
}

export const ReviewRequested: Story = {
  argTypes,
  render: () => (
    <ReviewerSectionStoryComponent
      latestOpinionatedReviews={[]}
      pullRequestId="PR_123"
      pendingRequestedReviews={[userReviewRequest, codeownerUserReviewRequest]}
      numReviewsRequired={2}
      reviewsState={ConsolidatedReviewState.REVIEW_REQUIRED}
      consolidatedFailureReasons={['MORE_REVIEWS_REQUIRED']}
      helpUrl="https://help.github.com"
      viewerCanDismissReviews
      viewerCanReRequestReviews
    />
  ),
  play: async ({canvasElement, step}) => {
    if (!shouldInteractionPlay()) return

    const canvas = within(canvasElement)
    let groupButton: HTMLElement
    const reviewerText = 'was requested for review'
    const codeownerReviewerText = 'was requested for review as a codeowner'

    await step('assert the correct section header info is rendered', async () => {
      expect(await canvas.findByText('Review required')).toBeInTheDocument()
      expect(
        canvas.getByText('At least 2 approving reviews are required by reviewers with write access.'),
      ).toBeInTheDocument()
    })

    await step('assert that the pending reviews group button is rendered, but not expanded', async () => {
      groupButton = await canvas.findByRole('button', {name: 'Expand 2 pending reviews group', expanded: false})
    })

    await step('assert that the reviews in the pending reviews group are not visible before expanding', async () => {
      expect(canvas.queryByText(userReviewRequest.reviewer!.login)).not.toBeInTheDocument()
      expect(canvas.queryByText(codeownerUserReviewRequest.reviewer!.login)).not.toBeInTheDocument()
      expect(canvas.queryByText(reviewerText)).not.toBeInTheDocument()
      expect(canvas.queryByText(codeownerReviewerText)).not.toBeInTheDocument()
    })

    await step('assert that clicking on the pending reviews group button will render the pending reviews', async () => {
      await userEvent.click(groupButton)
      expect(await canvas.findByText(userReviewRequest.reviewer!.login)).toBeVisible()
      expect(canvas.getByText(codeownerUserReviewRequest.reviewer!.login)).toBeVisible()
      expect(canvas.getByText(reviewerText)).toBeVisible()
      expect(canvas.getByText(codeownerReviewerText)).toBeVisible()
    })
  },
}

export default meta
