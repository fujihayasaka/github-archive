import type {Meta, StoryObj} from '@storybook/react'
import {within, expect, userEvent} from '@storybook/test'

import {OpinionatedReviewsGroup, type OpinionatedReviewsGroupProps} from './OpinionatedReviewsGroup'

import {ReviewGroup, type OpinionatedReview} from '../../../types'
import {BASE_PAGE_DATA_URL} from '@github-ui/pull-request-page-data-tooling/render-with-query-client'
import queryClient from '@github-ui/pull-request-page-data-tooling/query-client'
import {QueryClientProvider} from '@tanstack/react-query'
import {PageDataContextProvider} from '@github-ui/pull-request-page-data-tooling/page-data-context'

const meta: Meta<typeof OpinionatedReviewsGroup> = {
  title: 'Pull Requests/mergebox/OpinionatedReviewsGroup',
  component: OpinionatedReviewsGroup,
}

type Story = StoryObj<typeof OpinionatedReviewsGroup>

const disabledArg = {
  table: {
    disable: true,
  },
}

const argTypes = {
  children: disabledArg,
  count: disabledArg,
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

const approvalReviewOne: OpinionatedReview = {
  id: 1,
  authorCanPushToRepository: true,
  author: octocat,
  onBehalfOf: ['my-cool-team-reviewers'],
  state: 'APPROVED',
}

const approvalReviewTwo: OpinionatedReview = {
  id: 2,
  authorCanPushToRepository: true,
  author: octokitten,
  onBehalfOf: [],
  state: 'APPROVED',
}

const requestedChangeReviewOne: OpinionatedReview = {
  id: 3,
  authorCanPushToRepository: true,
  author: octocat,
  onBehalfOf: ['my-cool-team-reviewers'],
  state: 'CHANGES_REQUESTED',
}

const requestedChangeReviewTwo: OpinionatedReview = {
  id: 4,
  authorCanPushToRepository: true,
  author: octokitten,
  onBehalfOf: [],
  state: 'CHANGES_REQUESTED',
}

function OpinionatedReviewsGroupStoryComponent(props: OpinionatedReviewsGroupProps) {
  return (
    <PageDataContextProvider basePageDataUrl={BASE_PAGE_DATA_URL}>
      <QueryClientProvider client={queryClient}>
        <OpinionatedReviewsGroup {...props} />
      </QueryClientProvider>
    </PageDataContextProvider>
  )
}

export const OneApproval: Story = {
  argTypes,
  render: () => (
    <OpinionatedReviewsGroupStoryComponent
      viewerCanDismissReviews
      refetchMergeBoxQuery={() => {}}
      opinionatedReviews={[approvalReviewOne]}
      reviewGroup={ReviewGroup.Approvals}
    />
  ),
  play: async ({canvasElement, step}) => {
    const canvas = within(canvasElement)
    let groupButton: HTMLElement
    const requestedChangesText = 'Approved these changes for my-cool-team-reviewers'

    await step('assert that the group button is rendered, but not expanded', async () => {
      groupButton = await canvas.findByRole('button', {name: 'Expand 1 approval group', expanded: false})
    })

    await step('assert that the review in the group is not visible before expanding', async () => {
      expect(canvas.queryByText(approvalReviewOne.author!.login)).not.toBeInTheDocument()
      expect(canvas.queryByText(requestedChangesText)).not.toBeInTheDocument()
    })

    await step('assert that clicking on the group button will render the review', async () => {
      await userEvent.click(groupButton)
      expect(await canvas.findByText(approvalReviewOne.author!.login)).toBeVisible()
      expect(canvas.getByText(requestedChangesText)).toBeVisible()
    })
  },
}

export const MultipleApprovals: Story = {
  argTypes,
  render: () => (
    <OpinionatedReviewsGroupStoryComponent
      viewerCanDismissReviews
      refetchMergeBoxQuery={() => {}}
      opinionatedReviews={[approvalReviewOne, approvalReviewTwo]}
      reviewGroup={ReviewGroup.Approvals}
    />
  ),
  play: async ({canvasElement, step}) => {
    const canvas = within(canvasElement)
    let groupButton: HTMLElement
    const approvalOneText = 'Approved these changes for my-cool-team-reviewers'
    const approvalTwoText = 'Approved these changes'

    await step('assert that the group button is rendered, but not expanded', async () => {
      groupButton = await canvas.findByRole('button', {name: 'Expand 2 approvals group', expanded: false})
    })

    await step('assert that the reviews in the group are not visible before expanding', async () => {
      // Review One
      expect(canvas.queryByText(approvalReviewOne.author!.login)).not.toBeInTheDocument()
      expect(canvas.queryByText(approvalOneText)).not.toBeInTheDocument()
      // Review two
      expect(canvas.queryByText(approvalReviewTwo.author!.login)).not.toBeInTheDocument()
      expect(canvas.queryByText(approvalTwoText)).not.toBeInTheDocument()
    })

    await step('assert that clicking on the group button will render the reviews', async () => {
      await userEvent.click(groupButton)
      // Review One
      expect(await canvas.findByText(approvalReviewOne.author!.login)).toBeVisible()
      expect(canvas.getByText(approvalOneText)).toBeVisible()
      // Review two
      expect(canvas.getByText(approvalReviewTwo.author!.login)).toBeVisible()
      expect(canvas.getByText(approvalTwoText)).toBeVisible()
    })
  },
}

export const OneRequestedChange: Story = {
  argTypes,
  render: () => (
    <OpinionatedReviewsGroupStoryComponent
      viewerCanDismissReviews
      refetchMergeBoxQuery={() => {}}
      opinionatedReviews={[requestedChangeReviewOne]}
      reviewGroup={ReviewGroup.RequestedChanges}
    />
  ),
  play: async ({canvasElement, step}) => {
    const canvas = within(canvasElement)
    let groupButton: HTMLElement
    const reviewText = 'Requested changes'

    await step('assert that the group button is rendered, but not expanded', async () => {
      groupButton = await canvas.findByRole('button', {name: 'Expand 1 requested change group', expanded: false})
    })

    await step('assert that the review in the group is not visible before expanding', async () => {
      expect(canvas.queryByText(requestedChangeReviewOne.author!.login)).not.toBeInTheDocument()
      expect(canvas.queryByText(reviewText)).not.toBeInTheDocument()
    })

    await step('assert that clicking on the group button will render the review', async () => {
      await userEvent.click(groupButton)
      expect(await canvas.findByText(requestedChangeReviewOne.author!.login)).toBeVisible()
      expect(canvas.getByText(reviewText)).toBeVisible()
    })
  },
}

export const MultipleRequestedChanges: Story = {
  argTypes,
  render: () => (
    <OpinionatedReviewsGroupStoryComponent
      viewerCanDismissReviews
      refetchMergeBoxQuery={() => {}}
      opinionatedReviews={[requestedChangeReviewOne, requestedChangeReviewTwo]}
      reviewGroup={ReviewGroup.RequestedChanges}
    />
  ),
  play: async ({canvasElement, step}) => {
    const canvas = within(canvasElement)
    let groupButton: HTMLElement
    const reviewText = 'Requested changes'

    await step('assert that the group button is rendered, but not expanded', async () => {
      groupButton = await canvas.findByRole('button', {name: 'Expand 2 requested changes group', expanded: false})
    })

    await step('assert that the reviews in the group are not visible before expanding', async () => {
      // Review One author
      expect(canvas.queryByText(requestedChangeReviewOne.author!.login)).not.toBeInTheDocument()
      // Review two author
      expect(canvas.queryByText(requestedChangeReviewTwo.author!.login)).not.toBeInTheDocument()
      // eslint-disable-next-line github/array-foreach
      canvas.queryAllByText(reviewText).forEach(el => expect(el).not.toBeInTheDocument())
    })

    await step('assert that clicking on the group button will render the reviews', async () => {
      await userEvent.click(groupButton)
      // Review One
      expect(await canvas.findByText(requestedChangeReviewOne.author!.login)).toBeVisible()
      // Review two
      expect(canvas.getByText(requestedChangeReviewTwo.author!.login)).toBeVisible()
      // eslint-disable-next-line github/array-foreach
      canvas.getAllByText(reviewText).forEach(el => expect(el).toBeVisible())
    })
  },
}

export default meta
