import {screen, waitFor} from '@testing-library/react'

import {MergeQueueSection as TestComponent, type Props} from '../MergeQueueSection'
import {noop} from '@github-ui/noop'
import {expectAnalyticsEvents} from '@github-ui/analytics-test-utils'
import {mockFetch} from '@github-ui/mock-fetch'
import {BASE_PAGE_DATA_URL, renderWithClient} from '@github-ui/pull-request-page-data-tooling/render-with-query-client'
import {PageData} from '@github-ui/pull-request-page-data-tooling/page-data'

afterEach(() => {
  jest.clearAllMocks()
})

const defaultProps: Props = {
  mergeQueue: {
    url: 'https://github.localhost/monalisa/smile/queue',
  },
  mergeQueueEntry: {
    position: 1,
    state: 'AWAITING_CHECKS',
    isLocked: false,
  },
  viewerCanAddAndRemoveFromMergeQueue: true,
  focusPrimaryMergeButton: noop,
}

const dequeuePullRequestPageDataRoute = `${BASE_PAGE_DATA_URL}/page_data/${PageData.dequeuePullRequest}`

describe('MergeQueueSection', () => {
  test('renders remove from queue button if the viewer has permission', async () => {
    const props: Props = {
      ...defaultProps,
      mergeQueueEntry: {
        position: 1,
        state: 'AWAITING_CHECKS',
        isLocked: false,
      },
      viewerCanAddAndRemoveFromMergeQueue: true,
    }

    renderWithClient(<TestComponent {...props} />)

    expect(screen.getByRole('button', {name: 'Remove from queue'})).toBeInTheDocument()
  })

  test('does not render remove from queue button if the viewer does not have permission', async () => {
    const props: Props = {
      ...defaultProps,
      viewerCanAddAndRemoveFromMergeQueue: false,
    }
    renderWithClient(<TestComponent {...props} />)

    expect(screen.queryByRole('button', {name: 'Remove from queue'})).not.toBeInTheDocument()
  })

  test('does not render remove from queue button if the merge entry is locked and displays explanatory text', async () => {
    const props: Props = {
      ...defaultProps,
      mergeQueueEntry: {
        position: 1,
        state: 'MERGEABLE',
        isLocked: true,
      },
      viewerCanAddAndRemoveFromMergeQueue: true,
    }

    renderWithClient(<TestComponent {...props} />)

    expect(screen.queryByRole('button', {name: 'Remove from queue'})).not.toBeInTheDocument()
    expect(screen.getByText('This pull request is locked for deployment by the')).toBeInTheDocument()
  })

  test('renders an "up next" message if there are no PRs ahead of it in the queue', async () => {
    const props: Props = {
      ...defaultProps,
      mergeQueueEntry: {
        position: 1,
        state: 'QUEUED',
        isLocked: false,
      },
      viewerCanAddAndRemoveFromMergeQueue: true,
    }

    renderWithClient(<TestComponent {...props} />)

    expect(screen.getByText(/This pull request is next up/)).toBeInTheDocument()
    expect(screen.getByRole('link', {name: 'merge queue'})).toBeInTheDocument()
  })

  test('displays how many pull requests are ahead in the queue', async () => {
    const props: Props = {
      ...defaultProps,
      mergeQueueEntry: {
        position: 5,
        state: 'QUEUED',
        isLocked: false,
      },
      viewerCanAddAndRemoveFromMergeQueue: true,
    }

    renderWithClient(<TestComponent {...props} />)

    expect(screen.getByText(/There are 4 pull requests ahead of this one/)).toBeInTheDocument()
    expect(screen.getByRole('link', {name: 'merge queue'})).toBeInTheDocument()
  })

  describe('confirmation dialog', () => {
    test('opens when removing a PR from the queue and handles close & cancel', async () => {
      const props: Props = {
        ...defaultProps,
        mergeQueueEntry: {
          position: 1,
          state: 'AWAITING_CHECKS',
          isLocked: false,
        },
        viewerCanAddAndRemoveFromMergeQueue: true,
      }

      const {user} = renderWithClient(<TestComponent {...props} />)

      const removeButton = screen.getByRole('button', {name: 'Remove from queue'})
      expect(removeButton).toBeInTheDocument()

      await user.click(removeButton)
      expect(screen.getByLabelText('Remove from the queue?')).toBeInTheDocument()
      const cancelButton = screen.getByRole('button', {name: 'Cancel'})
      expect(cancelButton).toBeInTheDocument()

      await user.click(cancelButton)
      expect(screen.queryByLabelText('Remove from the queue?')).not.toBeInTheDocument()
      expect(screen.queryByRole('button', {name: 'Remove from queue'})).toHaveFocus()

      await user.click(removeButton)
      expect(screen.getByLabelText('Remove from the queue?')).toBeInTheDocument()
      const closeButton = screen.getByLabelText('Close')
      expect(closeButton).toBeInTheDocument()

      await user.click(closeButton)
      expect(screen.queryByLabelText('Remove from the queue?')).not.toBeInTheDocument()
      expect(screen.queryByRole('button', {name: 'Remove from queue'})).toHaveFocus()
    })

    test('opens when removing a PR from the queue and handles successful confirming removal', async () => {
      mockFetch.mockRouteOnce(dequeuePullRequestPageDataRoute, {}, {status: 200, ok: true})
      const focusPrimaryMergeButtonMock = jest.fn()

      const props: Props = {
        ...defaultProps,
        mergeQueueEntry: {
          position: 1,
          state: 'AWAITING_CHECKS',
          isLocked: false,
        },
        viewerCanAddAndRemoveFromMergeQueue: true,
        focusPrimaryMergeButton: focusPrimaryMergeButtonMock,
      }

      const {user} = renderWithClient(<TestComponent {...props} />)

      const removeButton = screen.getByRole('button', {name: 'Remove from queue'})
      expect(removeButton).toBeInTheDocument()

      await user.click(removeButton)
      expect(screen.getByLabelText('Remove from the queue?')).toBeInTheDocument()
      const confirmRemoveButton = screen.getByRole('button', {name: 'Remove from the queue'})
      expect(confirmRemoveButton).toBeInTheDocument()

      await user.click(confirmRemoveButton)
      await waitFor(() => expect(screen.queryByLabelText('Remove from the queue?')).not.toBeInTheDocument())
      expect(screen.queryByText('Removing from queue')).not.toBeInTheDocument()
      expect(focusPrimaryMergeButtonMock).toHaveBeenCalled()

      expectAnalyticsEvents({
        type: 'merge_queue_section.dequeue_pull_request',
        target: 'MERGEBOX_MERGE_QUEUE_SECTION_REMOVE_FROM_QUEUE_BUTTON',
      })
    })

    test('handles dequeueing (pending) state', async () => {
      const props: Props = {
        ...defaultProps,
        mergeQueueEntry: {
          position: 1,
          state: 'AWAITING_CHECKS',
          isLocked: false,
        },
        viewerCanAddAndRemoveFromMergeQueue: true,
      }

      const {user} = renderWithClient(<TestComponent {...props} />)

      const removeButton = screen.getByRole('button', {name: 'Remove from queue'})
      expect(removeButton).toBeInTheDocument()

      await user.click(removeButton)
      expect(screen.getByLabelText('Remove from the queue?')).toBeInTheDocument()
      const confirmRemoveButton = screen.getByRole('button', {name: 'Remove from the queue'})
      expect(confirmRemoveButton).toBeInTheDocument()

      await user.click(confirmRemoveButton)
      const removingFromQueue = screen.getByRole('button', {name: /Removing from the queue/})
      expect(removingFromQueue).toBeInTheDocument()
      expect(removingFromQueue).toHaveAttribute('aria-disabled', 'true')
      expect(screen.getByLabelText('Remove from the queue?')).toBeInTheDocument()

      const cancelButton = screen.getByRole('button', {name: 'Cancel'})
      await user.click(cancelButton)
      expect(screen.getByLabelText('Remove from the queue?')).toBeInTheDocument()
    })

    test('renders errors in a flash message if present', async () => {
      mockFetch.mockRouteOnce(dequeuePullRequestPageDataRoute, {error: 'whoops!'}, {status: 422, ok: false})

      const props: Props = {
        ...defaultProps,
        mergeQueueEntry: {
          position: 5,
          state: 'QUEUED',
          isLocked: false,
        },
        viewerCanAddAndRemoveFromMergeQueue: true,
      }

      const {user} = renderWithClient(<TestComponent {...props} />)

      const removeButton = screen.getByRole('button', {name: 'Remove from queue'})
      expect(removeButton).toBeInTheDocument()

      await user.click(removeButton)
      expect(screen.getByLabelText('Remove from the queue?')).toBeInTheDocument()
      const confirmRemoveButton = screen.getByRole('button', {name: 'Remove from the queue'})
      expect(confirmRemoveButton).toBeInTheDocument()

      await user.click(confirmRemoveButton)
      expect(screen.queryByLabelText('Remove from the queue?')).not.toBeInTheDocument()
      expect(screen.getByText('whoops!')).toBeInTheDocument()
      expect(removeButton).toHaveFocus()

      // clears error if user tries again
      await user.click(removeButton)
      expect(screen.queryByText('whoops!')).not.toBeInTheDocument()
    })
  })
})
