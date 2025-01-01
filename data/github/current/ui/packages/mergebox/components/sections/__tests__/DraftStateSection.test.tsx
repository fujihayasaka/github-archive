import {act, screen} from '@testing-library/react'
import {PageData} from '@github-ui/pull-request-page-data-tooling/page-data'
import {BASE_PAGE_DATA_URL, renderWithClient} from '@github-ui/pull-request-page-data-tooling/render-with-query-client'
import {expectAnalyticsEvents} from '@github-ui/analytics-test-utils'
import {mockFetch} from '@github-ui/mock-fetch'

import {DraftStateSection as TestComponent, type DraftStateSectionProps} from '../DraftStateSection'

const markReadyForReviewMutationRoute = `${BASE_PAGE_DATA_URL}/page_data/${PageData.markReadyForReview}`

const defaultProps: DraftStateSectionProps = {
  isDraft: true,
  state: 'OPEN',
  viewerCanUpdate: true,
}

describe('Draft State Section', () => {
  test('it does not render if isDraft is false', () => {
    const props = {
      ...defaultProps,
      isDraft: false,
    }
    const {container} = renderWithClient(<TestComponent {...props} />)

    expect(container).toBeEmptyDOMElement()
  })

  test('does not render when the pr is not open', () => {
    const props: DraftStateSectionProps = {
      ...defaultProps,
      state: 'CLOSED',
    }
    const {container} = renderWithClient(<TestComponent {...props} />)

    expect(container).toBeEmptyDOMElement()
  })

  test('does not render when the user does not have permission to update the PR', () => {
    const props: DraftStateSectionProps = {
      ...defaultProps,
      viewerCanUpdate: false,
    }
    const {container} = renderWithClient(<TestComponent {...props} />)

    expect(container).toBeEmptyDOMElement()
  })

  test('renders when pull request is in draft', () => {
    const props: DraftStateSectionProps = {
      ...defaultProps,
      isDraft: true,
      state: 'OPEN',
      viewerCanUpdate: true,
    }
    renderWithClient(<TestComponent {...props} />)

    expect(screen.getByText('Ready for review')).toBeInTheDocument()
  })

  test('shows error banner when marking ready for review fails', async () => {
    const props: DraftStateSectionProps = {
      ...defaultProps,
      isDraft: true,
      state: 'OPEN',
      viewerCanUpdate: true,
    }

    const {user} = renderWithClient(<TestComponent {...props} />)
    await user.click(screen.getByText('Ready for review'))

    const outerMarkReadyForReviewButton = screen
      .getAllByRole('button')
      .find(element => element.innerHTML.includes('Marking ready for review...'))
    expect(outerMarkReadyForReviewButton).toHaveAttribute('aria-disabled', 'true')

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
    expect(await screen.findByRole('button', {name: 'Ready for review'})).toHaveAttribute('aria-disabled', 'false')
  })

  test('it emits events when user marks pull request ready for review', async () => {
    const props: DraftStateSectionProps = {
      ...defaultProps,
      isDraft: true,
      state: 'OPEN',
      viewerCanUpdate: true,
    }
    const {user} = renderWithClient(<TestComponent {...props} />)

    await user.click(screen.getByRole('button', {name: 'Ready for review'}))
    expect(await screen.findByText('Marking ready for review...')).toBeInTheDocument()

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
    const props: DraftStateSectionProps = {
      ...defaultProps,
      isDraft: true,
      state: 'OPEN',
      viewerCanUpdate: true,
    }
    const {user} = renderWithClient(<TestComponent {...props} />)

    await user.click(screen.getByRole('button', {name: 'Ready for review'}))

    const outerMarkReadyForReviewButton = screen
      .getAllByRole('button')
      .find(element => element.innerHTML.includes('Marking ready for review...'))
    expect(outerMarkReadyForReviewButton).toHaveAttribute('aria-disabled', 'true')

    mockFetch.resolvePendingRequest(markReadyForReviewMutationRoute, undefined, {
      ok: true,
    })

    expect(await screen.findByRole('button', {name: 'Ready for review'})).toHaveAttribute('aria-disabled', 'false')
  })
})
