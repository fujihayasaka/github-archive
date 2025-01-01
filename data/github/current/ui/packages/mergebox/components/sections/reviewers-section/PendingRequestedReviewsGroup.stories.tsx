import type {Meta, StoryObj} from '@storybook/react'
import {within, expect, userEvent} from '@storybook/test'
import {shouldInteractionPlay} from '@github-ui/storybook'

import {PendingRequestedReviewsGroup, type PendingRequestedReviewsGroupProps} from './PendingRequestedReviewsGroup'

import {ReviewGroup, type PendingReviewRequest} from '../../../types'
import {PageDataContextProvider} from '@github-ui/pull-request-page-data-tooling/page-data-context'
import {BASE_PAGE_DATA_URL} from '@github-ui/pull-request-page-data-tooling/render-with-query-client'

const meta: Meta<typeof PendingRequestedReviewsGroup> = {
  title: 'Pull Requests/Merge Box/PendingRequestedReviewsGroup',
  component: PendingRequestedReviewsGroup,
  tags: ['flaky'],
  beforeEach: () => {
    sessionStorage.clear()
  },
}

type Story = StoryObj<typeof PendingRequestedReviewsGroup>

const disabledArg = {
  table: {
    disable: true,
  },
}

const argTypes = {
  children: disabledArg,
  count: disabledArg,
  pullRequestId: disabledArg,
  reviewGroup: disabledArg,
}

const octocat = {
  login: 'octocat',
  avatarUrl: 'https://avatars.githubusercontent.com/u/678910?v=4',
  name: 'octocat',
  url: 'https://github.com/octocat',
}

const octokitten = {
  login: 'octokitten',
  avatarUrl: 'https://avatars.githubusercontent.com/u/678910?v=4',
  name: 'octokitten',
  url: 'https://github.com/octokitten',
}

const pendingReviewOne: PendingReviewRequest = {
  reviewer: {...octocat, type: 'USER'},
  isCodeOwner: false,
}

const pendingReviewTwo: PendingReviewRequest = {
  reviewer: {...octokitten, type: 'TEAM'},
  isCodeOwner: true,
}

function PendingRequestedReviewsGroupStoryComponent(props: PendingRequestedReviewsGroupProps) {
  return (
    <PageDataContextProvider basePageDataUrl={BASE_PAGE_DATA_URL}>
      <PendingRequestedReviewsGroup {...props} />
    </PageDataContextProvider>
  )
}
export const OnePendingReviewRequest: Story = {
  argTypes,
  render: () => (
    <PendingRequestedReviewsGroupStoryComponent
      viewerCanDismissReviews
      pendingRequestedReviews={[pendingReviewOne]}
      pullRequestId="PR_123"
      reviewGroup={ReviewGroup.PendingReviewRequest}
    />
  ),
  play: async ({canvasElement, step}) => {
    if (!shouldInteractionPlay()) return

    const canvas = within(canvasElement)
    let groupButton: HTMLElement
    const reviewText = 'was requested for review'

    await step('assert that the group button is rendered, but not expanded', async () => {
      groupButton = await canvas.findByRole('button', {name: 'Expand 1 pending review group', expanded: false})
    })

    await step('assert that the review in the group is not visible before expanding', async () => {
      expect(canvas.queryByText(pendingReviewOne.reviewer!.login)).not.toBeInTheDocument()
      expect(canvas.queryByText(reviewText)).not.toBeInTheDocument()
    })

    await step('assert that clicking on the group button will render the review', async () => {
      await userEvent.click(groupButton)
      expect(await canvas.findByText(pendingReviewOne.reviewer!.login)).toBeVisible()
      expect(canvas.getByText(reviewText)).toBeVisible()
    })
  },
}

export const MultiplePendingReviews: Story = {
  argTypes,
  render: () => (
    <PendingRequestedReviewsGroupStoryComponent
      viewerCanDismissReviews
      pendingRequestedReviews={[pendingReviewOne, pendingReviewTwo]}
      pullRequestId="PR_123"
      reviewGroup={ReviewGroup.PendingReviewRequest}
    />
  ),
  play: async ({canvasElement, step}) => {
    if (!shouldInteractionPlay()) return

    const canvas = within(canvasElement)
    let groupButton: HTMLElement
    const codeownersText = 'was requested for review as a codeowner'
    const nonCodeownersText = 'was requested for review'

    await step('assert that the group button is rendered, but not expanded', async () => {
      groupButton = await canvas.findByRole('button', {name: 'Expand 2 pending reviews group', expanded: false})
    })

    await step('assert that the reviews in the group are not visible before expanding', async () => {
      // Review One
      expect(canvas.queryByText(pendingReviewOne.reviewer!.login)).not.toBeInTheDocument()
      expect(canvas.queryByText(nonCodeownersText)).not.toBeInTheDocument()
      // Review two
      expect(canvas.queryByText(pendingReviewTwo.reviewer!.login)).not.toBeInTheDocument()
      expect(canvas.queryByText(codeownersText)).not.toBeInTheDocument()
    })

    await step('assert that clicking on the group button will render the reviews', async () => {
      await userEvent.click(groupButton)
      // Review One
      expect(await canvas.findByText(pendingReviewOne.reviewer!.login)).toBeVisible()
      expect(canvas.getByText(nonCodeownersText)).toBeVisible()
      // Review two
      expect(canvas.getByText(pendingReviewTwo.reviewer!.login)).toBeVisible()
      expect(canvas.getByText(codeownersText)).toBeVisible()
    })
  },
}

export default meta
