import {expectAnalyticsEvents} from '@github-ui/analytics-test-utils'
import {render} from '@github-ui/react-core/test-utils'
import {screen, within} from '@testing-library/react'

import {buildPendingCommentPreview, buildPullRequest} from '../../test-utils/mock-data'
import type {PullRequestsTargetType} from '../../types/analytics-events-types'
import type {PullRequest, Repository} from '../../page-data/payloads/toolbar'
import {ReviewMenuButton} from '../ReviewMenuButton'
import {AnalyticsProvider} from '@github-ui/analytics-provider'
import {PageDataContextProvider} from '@github-ui/pull-request-page-data-tooling/page-data-context'
import type {SafeHTMLString} from '@github-ui/safe-html'
import type {PendingReview} from '../../page-data/payloads/pending-review'

function TestComponent({
  viewerPendingReview,
  pullRequest,
  viewerLogin,
}: {
  viewerPendingReview: PendingReview
  pullRequest: PullRequest
  repository: Repository
  viewerLogin: string
}) {
  return (
    <PageDataContextProvider basePageDataUrl={pullRequest.pathName}>
      <AnalyticsProvider appName="pull_request" category="review_menu" metadata={{pull_request_id: pullRequest.id}}>
        <ReviewMenuButton
          currentUserLogin={viewerLogin}
          initialPendingReview={viewerPendingReview}
          pullRequest={pullRequest}
          repository={pullRequest.repository}
        />
      </AnalyticsProvider>
    </PageDataContextProvider>
  )
}

const noPendingComments = {
  comments: [],
  id: 'test-id',
}

const onePendingComment = {
  comments: [buildPendingCommentPreview({bodyHTML: 'testHTML' as SafeHTMLString})],
  id: 'test-id',
}

describe('analytic events', () => {
  test('clicking on "Submit review" button to open dialog', async () => {
    const pullRequest = buildPullRequest()

    const {user} = render(
      <TestComponent
        pullRequest={pullRequest}
        repository={pullRequest.repository}
        viewerLogin="test-author"
        viewerPendingReview={noPendingComments}
      />,
    )
    await user.click(screen.getByRole('button', {name: 'Submit review'}))

    expectAnalyticsEvents<PullRequestsTargetType>({
      type: 'submit_review_dialog.open',
      target: 'REVIEW_CHANGES_BUTTON',
      data: {
        app_name: 'pull_request',
      },
    })
  })

  test('abandoning review', async () => {
    jest.spyOn(window, 'confirm').mockImplementation(() => true)
    const pullRequest = buildPullRequest()

    const {user} = render(
      <TestComponent
        pullRequest={pullRequest}
        repository={pullRequest.repository}
        viewerLogin="test-author"
        viewerPendingReview={noPendingComments}
      />,
    )

    await user.click(screen.getByRole('button', {name: 'Submit review'}))
    const dialog = await screen.findByRole('dialog')
    await user.click(within(dialog).getByRole('button', {name: 'Discard review'}))

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

  test('submitting review', async () => {
    const pullRequest = buildPullRequest()

    const {user} = render(
      <TestComponent
        pullRequest={pullRequest}
        repository={pullRequest.repository}
        viewerLogin="test-author"
        viewerPendingReview={onePendingComment}
      />,
    )

    await user.click(screen.getByRole('button', {name: 'Submit review (1)'}))
    const dialog = await screen.findByRole('dialog')
    await user.click(within(dialog).getByRole('button', {name: 'Submit review'}))

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
  })
})
