import {expectAnalyticsEvents} from '@github-ui/analytics-test-utils'
import {render} from '@github-ui/react-core/test-utils'
import {screen, within} from '@testing-library/react'

import type {PullRequestsTargetType} from '../../../types/analytics-events-types'
import type {PullRequest, Repository} from '../../../page-data/payloads/toolbar'
import {ReviewMenuButton} from '../ReviewMenuButton'
import {AnalyticsProvider} from '@github-ui/analytics-provider'
import {PageDataContextProvider} from '@github-ui/pull-request-page-data-tooling/page-data-context'
import {getFilesRoutePullRequest} from '../../../test-utils/files-changed/pull-request-mock-data'

jest.mock('../../../page-data/loaders/use-markers-data', () => ({
  useMarkersDataWithSelectThreadAndAnnotationIDs: jest.fn(() => ({
    data: {
      threads: {},
      annotations: {},
    },
  })),
}))
jest.mock('../../../page-data/payloads/pending-review', () => ({
  usePendingReviewPageData: jest.fn(() => ({
    data: {
      id: 1,
      pendingReviewIDs: [7],
    },
  })),
}))
const mockThreadPreview = [
  {
    bodyHTML: '<p>test</p>',
    threadId: '7',
    commentId: '7',
    isOutdated: false,
    isResolved: false,
    line: 7,
    path: 'filePath',
    subjectType: 'LINE',
    threadPreviewComments: [],
  },
]
jest.mock('../../../hooks/use-generate-thread-previews', () => ({
  useGenerateThreadPreviews: jest.fn(() => {
    return mockThreadPreview
  }),
}))
function TestComponent({
  pullRequest,
  viewerLogin,
}: {
  pullRequest: PullRequest
  repository: Repository
  viewerLogin: string
}) {
  return (
    <PageDataContextProvider basePageDataUrl={pullRequest.pathName}>
      <AnalyticsProvider appName="pull_request" category="review_menu" metadata={{pull_request_id: pullRequest.id}}>
        <ReviewMenuButton
          commentBoxConfig={{
            pasteUrlsAsPlainText: false,
            useMonospaceFont: false,
            emojiSkinTonePreference: 0,
          }}
          commentBoxSubject={undefined}
          diffEntries={[]}
          currentUserLogin={viewerLogin}
          pullRequest={pullRequest}
          repository={pullRequest.repository}
        />
      </AnalyticsProvider>
    </PageDataContextProvider>
  )
}

describe('analytic events', () => {
  test('clicking on "Submit review" button to open dialog', async () => {
    const pullRequest = getFilesRoutePullRequest()

    const {user} = render(
      <TestComponent pullRequest={pullRequest} repository={pullRequest.repository} viewerLogin="test-author" />,
    )
    await user.click(screen.getByRole('button', {name: 'Submit review (1)'}))

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
    const pullRequest = getFilesRoutePullRequest()

    const {user} = render(
      <TestComponent pullRequest={pullRequest} repository={pullRequest.repository} viewerLogin="test-author" />,
    )

    await user.click(screen.getByRole('button', {name: 'Submit review (1)'}))
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
    const pullRequest = getFilesRoutePullRequest()

    const {user} = render(
      <TestComponent pullRequest={pullRequest} repository={pullRequest.repository} viewerLogin="test-author" />,
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

  test('controlled comment box is in sync with the review menu', async () => {
    // For this test only, we need no comments from useGenerateThreadPreviews
    // so submit is disabled when Comment review type is selected
    jest
      .spyOn(jest.requireMock('../../../hooks/use-generate-thread-previews'), 'useGenerateThreadPreviews')
      .mockImplementation(() => [])

    const pullRequest = getFilesRoutePullRequest()

    const {user} = render(
      <TestComponent pullRequest={pullRequest} repository={pullRequest.repository} viewerLogin="test-author" />,
    )

    await user.click(screen.getByRole('button', {name: 'Submit review'}))
    const dialog = await screen.findByRole('dialog')

    // Comment review type requires a comment
    await user.click(
      within(dialog).getByRole('radio', {name: 'Comment Submit general feedback without explicit approval.'}),
    )
    expect(within(dialog).getByRole('button', {name: 'Submit review'})).toBeDisabled()

    // Type a comment to enable the submit button
    // this validates that the controlled comment box is in sync with the review menu
    const commentBox = within(dialog).getByRole('textbox')
    await user.type(commentBox, 'This is a test comment')

    expect(within(dialog).getByRole('button', {name: 'Submit review'})).toBeEnabled()
  })
})
