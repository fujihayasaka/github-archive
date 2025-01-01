import {act, screen} from '@testing-library/react'
import {PageData} from '@github-ui/pull-request-page-data-tooling/page-data'
import {BASE_PAGE_DATA_URL, renderWithClient} from '@github-ui/pull-request-page-data-tooling/render-with-query-client'
import {expectAnalyticsEvents} from '@github-ui/analytics-test-utils'
import {mockFetch} from '@github-ui/mock-fetch'

import {DraftStateSection as TestComponent} from '../DraftStateSection'
import {
  assertButtonEnabled,
  assertButtonInLoadingState,
  assertWaitForButtonToBeEnabled,
} from '../../../test-utils/loading-button-asserts'

const markReadyForReviewMutationRoute = `${BASE_PAGE_DATA_URL}/page_data/${PageData.markReadyForReview}`

const defaultProps = {
  viewerCanUpdate: true,
  helpUrl: 'https://github.help.com',
}

describe('Draft State Section', () => {
  test('shows error banner when marking ready for review fails', async () => {
    const {user} = renderWithClient(<TestComponent {...defaultProps} />)

    const markReadyForReviewButton = screen.getByRole('button', {name: 'Ready for review'})
    assertButtonEnabled(markReadyForReviewButton)

    await user.click(markReadyForReviewButton)

    assertButtonInLoadingState(markReadyForReviewButton, 'Marking ready for review')
    act(() => {
      mockFetch.resolvePendingRequest(
        markReadyForReviewMutationRoute,
        {error: 'Pull request failed to be marked as ready for review'},
        {
          ok: false,
          status: 422,
        },
      )
    })

    expect(await screen.findByText('Pull request failed to be marked as ready for review')).toBeVisible()
    assertButtonEnabled(markReadyForReviewButton)
  })

  test('it emits events when user marks pull request ready for review', async () => {
    const {user} = renderWithClient(<TestComponent {...defaultProps} />)

    const markReadyForReviewButton = screen.getByRole('button', {name: 'Ready for review'})
    assertButtonEnabled(markReadyForReviewButton)

    await user.click(markReadyForReviewButton)

    assertButtonInLoadingState(markReadyForReviewButton, 'Marking ready for review')

    mockFetch.resolvePendingRequest(markReadyForReviewMutationRoute, undefined, {
      ok: true,
    })

    expectAnalyticsEvents({
      type: 'draft_state_section.mark_ready_for_review',
      target: 'MERGEBOX_DRAFT_STATE_SECTION_MARK_READY_FOR_REVIEW_BUTTON',
    })

    expect(await screen.findByText('Ready for review')).toBeInTheDocument()
  })

  test('shows a pending state while the mutation is in progress', async () => {
    const {user} = renderWithClient(<TestComponent {...defaultProps} />)

    const markReadyForReviewButton = screen.getByRole('button', {name: 'Ready for review'})
    assertButtonEnabled(markReadyForReviewButton)

    await user.click(markReadyForReviewButton)

    assertButtonInLoadingState(markReadyForReviewButton, 'Marking ready for review')

    mockFetch.resolvePendingRequest(markReadyForReviewMutationRoute, undefined, {
      ok: true,
    })

    await assertWaitForButtonToBeEnabled(markReadyForReviewButton)
    expect.hasAssertions()
  })

  test('show the Draft State Section even if the user does not have write access', async () => {
    renderWithClient(<TestComponent {...defaultProps} viewerCanUpdate={false} />)

    expect(screen.getByText('This pull request is still a work in progress')).toBeInTheDocument()
  })

  test('shows the mark ready for review button when the user has write access', async () => {
    const {user} = renderWithClient(<TestComponent {...defaultProps} />)

    const markReadyForReviewButton = screen.getByRole('button', {name: 'Ready for review'})
    assertButtonEnabled(markReadyForReviewButton)

    await user.click(markReadyForReviewButton)

    assertButtonInLoadingState(markReadyForReviewButton, 'Marking ready for review')

    mockFetch.resolvePendingRequest(markReadyForReviewMutationRoute, undefined, {
      ok: true,
    })

    expect(await screen.findByText('Ready for review')).toBeInTheDocument()
  })

  test('does not show the mark ready for review button when the user does not have write access', async () => {
    renderWithClient(<TestComponent {...defaultProps} viewerCanUpdate={false} />)

    expect(screen.queryByRole('button', {name: 'Ready for review'})).not.toBeInTheDocument()
  })

  test('shows the proper subtitle when the user does not have permission to mark the pull request as ready for review', async () => {
    renderWithClient(<TestComponent {...defaultProps} viewerCanUpdate={false} />)

    const paragraph = screen.getByText(
      (_, el) =>
        (el?.nodeName === 'P' &&
          el.textContent?.includes('Only those with') &&
          el.textContent?.includes('write access') &&
          el.textContent?.includes('to this repository can mark a draft pull request as ready for review.')) ||
        false,
    )

    expect(paragraph).toBeInTheDocument()
  })
})
