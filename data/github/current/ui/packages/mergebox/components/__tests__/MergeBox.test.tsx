import {act, screen, waitFor} from '@testing-library/react'
import {MergeBoxTestComponent as TestComponent} from '../../test-utils/MergeBoxTestComponent'
import {BASE_PAGE_DATA_URL, renderWithClient} from '@github-ui/pull-request-page-data-tooling/render-with-query-client'
import {PageData} from '@github-ui/pull-request-page-data-tooling/page-data'
// eslint-disable-next-line no-restricted-imports
import {expectMockFetchCalledTimes, mockFetch} from '@github-ui/mock-fetch'
import {
  checksSectionNoChecksState,
  checksSectionPassingState,
  checksSectionPendingState,
  checksSectionSomeFailedState,
} from '../../test-utils/mocks/checks-section-mocks'
import {mergeBoxMockData} from '../../test-utils/mocks/json-api-response.mock'
import {dispatchAliveTestMessage} from '@github-ui/use-alive/test-utils'
import {
  unsignedHeadRefChannel,
  unsignedCommitHeadShaChannel,
  unsignedStateChannel,
} from '../../test-utils/mocks/alive-channels-mock'

const statusChecksPageDataRoute = `${BASE_PAGE_DATA_URL}/page_data/${PageData.statusChecks}`
const baseMergeBoxPageDataRoute = `${BASE_PAGE_DATA_URL}/page_data/${PageData.mergeBox}`
const mergeBoxPageDataRoute = `${baseMergeBoxPageDataRoute}?merge_method=MERGE&bypass_requirements=false`

// Reset the Tanstack Query Client Cache between tests to ensure that we don't use stale data.
afterEach(() => {
  jest.clearAllTimers()
})

describe('MergeBox', () => {
  test('loads data from the JSON endpoint', async () => {
    mockFetch.mockRoute(mergeBoxPageDataRoute, mergeBoxMockData())
    mockFetch.mockRoute(statusChecksPageDataRoute, checksSectionNoChecksState)
    renderWithClient(<TestComponent />)

    await waitFor(() => {
      expect(screen.queryByText('Loading')).not.toBeInTheDocument()
    })
    expect(screen.getByText('Merging is blocked')).toBeInTheDocument()
    expectMockFetchCalledTimes(mergeBoxPageDataRoute, 1)
    expectMockFetchCalledTimes(statusChecksPageDataRoute, 1)
  })

  test('shows a loading state if the request has not resolved yet', async () => {
    mockFetch.mockRoute(mergeBoxPageDataRoute, mergeBoxMockData())
    mockFetch.mockRoute(statusChecksPageDataRoute, checksSectionNoChecksState)
    renderWithClient(<TestComponent />)

    expect(screen.getByText('Loading')).toBeInTheDocument()

    await waitFor(() => {
      expect(screen.queryByText('Loading')).not.toBeInTheDocument()
    })
    expectMockFetchCalledTimes(mergeBoxPageDataRoute, 1)
    expectMockFetchCalledTimes(statusChecksPageDataRoute, 1)
  })

  test('refetches the merge box query when there is a live update', async () => {
    mockFetch.mockRoute(mergeBoxPageDataRoute, mergeBoxMockData())
    mockFetch.mockRoute(statusChecksPageDataRoute, checksSectionNoChecksState)
    renderWithClient(<TestComponent />)

    expect(screen.getByText('Loading')).toBeInTheDocument()

    await waitFor(() => {
      expect(screen.queryByText('Loading')).not.toBeInTheDocument()
    })

    mockFetch.mockRoute(mergeBoxPageDataRoute, mergeBoxMockData({pullRequestKind: 'draft'}))
    act(() => {
      dispatchAliveTestMessage(unsignedStateChannel, {})
    })

    expect(await screen.findByText('This pull request is still a work in progress')).toBeInTheDocument()
    expect(screen.getByText('Ready for review')).toBeInTheDocument()
    expectMockFetchCalledTimes(mergeBoxPageDataRoute, 2)
    expectMockFetchCalledTimes(statusChecksPageDataRoute, 1)
  })

  test('It does not refetch the merge box query when there is a live update and user is not viewing page', async () => {
    mockFetch.mockRoute(mergeBoxPageDataRoute, mergeBoxMockData())
    mockFetch.mockRoute(statusChecksPageDataRoute, checksSectionNoChecksState)

    renderWithClient(<TestComponent />)

    expect(screen.getByText('Loading')).toBeInTheDocument()

    await waitFor(() => expect(screen.queryByText('Loading')).not.toBeInTheDocument())

    act(() => {
      // Mock the page being hidden from browser view (e.g. clicking on another browser tab)
      Object.defineProperty(document, 'hidden', {value: true, writable: true})
      document.dispatchEvent(new Event('visibilitychange'))
    })

    mockFetch.mockRoute(mergeBoxPageDataRoute, mergeBoxMockData({pullRequestKind: 'draft'}))

    act(() => {
      dispatchAliveTestMessage(unsignedStateChannel, {})
    })

    await waitFor(() => {
      expect(screen.queryByText('Loading')).not.toBeInTheDocument()
    })

    // Assert that the merge box did not refetch data while user is not viewing the page
    expectMockFetchCalledTimes(mergeBoxPageDataRoute, 1)

    act(() => {
      // Mock a user clicking back to the browser tab with MergeBox
      Object.defineProperty(document, 'hidden', {value: false, writable: true})
      document.dispatchEvent(new Event('visibilitychange'))
    })

    await screen.findByText('This pull request is still a work in progress')

    // Assert that the merge box has refetched data now that the user is viewing the page again
    expectMockFetchCalledTimes(mergeBoxPageDataRoute, 2)
  })

  test('refetches the merge box query when there is a live update due to a push to the head', async () => {
    const mockData = mergeBoxMockData()
    mockFetch.mockRoute(mergeBoxPageDataRoute, mockData)
    mockFetch.mockRoute(statusChecksPageDataRoute, checksSectionNoChecksState)
    renderWithClient(<TestComponent />)

    expect(screen.getByText('Loading')).toBeInTheDocument()

    await waitFor(() => {
      expect(screen.queryByText('Loading')).not.toBeInTheDocument()
    })

    // update the head ref oid due to a push
    mockFetch.mockRoute(mergeBoxPageDataRoute, {
      ...mockData,
      pullRequest: {...mockData.pullRequest, headRefOid: '1098765432'},
    })
    act(() => {
      dispatchAliveTestMessage(unsignedHeadRefChannel, {})
    })

    await waitFor(() => expectMockFetchCalledTimes(mergeBoxPageDataRoute, 2))
    expectMockFetchCalledTimes(statusChecksPageDataRoute, 2)
  })

  test('refetches the merge box query when the merge method changes', async () => {
    const apiResponse = mergeBoxMockData({
      pullRequestKind: 'withDirectMergeEnabled',
      mergeRequirementsKind: 'mergeable',
    })

    mockFetch.mockRoute(mergeBoxPageDataRoute, apiResponse)
    mockFetch.mockRoute(statusChecksPageDataRoute, checksSectionNoChecksState)
    const {user} = renderWithClient(<TestComponent />)

    await waitFor(() => {
      expect(screen.queryByText('Loading')).not.toBeInTheDocument()
    })

    const mergeMethodOptions = screen.getByRole('button', {name: 'Select merge method'})
    await user.click(mergeMethodOptions)

    const squashAndMergeButton = await screen.findByText('Squash and merge')
    expect(squashAndMergeButton).toBeInTheDocument()

    // The refetch URL will have different parameters
    const squashMergeBoxPageDataRoute = `${baseMergeBoxPageDataRoute}?merge_method=SQUASH&bypass_requirements=false`
    // Arbitrarily change the data for the refetch so we have something to assert
    mockFetch.mockRoute(squashMergeBoxPageDataRoute, {
      pullRequest: {...apiResponse.pullRequest, isDraft: true},
      mergeRequirements: apiResponse.mergeRequirements,
    })
    mockFetch.mockRoute(statusChecksPageDataRoute, checksSectionNoChecksState)

    // Actually select the different merge method
    await user.click(squashAndMergeButton)

    await waitFor(() => {
      expect(screen.queryByText('Loading')).not.toBeInTheDocument()
    })

    // The mock return value changed the draft value, so assert that it's a draft now
    expect(await screen.findByText('This pull request is still a work in progress')).toBeInTheDocument()
    expect(screen.getByText('Ready for review')).toBeInTheDocument()
    expectMockFetchCalledTimes(mergeBoxPageDataRoute, 1)
    expectMockFetchCalledTimes(squashMergeBoxPageDataRoute, 1)
    expectMockFetchCalledTimes(statusChecksPageDataRoute, 1)
  })

  test('returns an h2 tag with sr-only class', async () => {
    mockFetch.mockRoute(mergeBoxPageDataRoute, mergeBoxMockData())
    mockFetch.mockRoute(statusChecksPageDataRoute, checksSectionNoChecksState)
    renderWithClient(<TestComponent />)

    await waitFor(() => {
      expect(screen.queryByText('Loading')).not.toBeInTheDocument()
    })

    const heading = screen.getByRole('heading', {level: 2, name: 'Merge info'})
    expect(heading).toBeInTheDocument()
    expect(heading).toHaveClass('sr-only')
  })

  test('it renders the fallback UI when PageData JSON response fails', async () => {
    jest.useFakeTimers()
    const spy = jest.spyOn(console, 'error').mockImplementation()

    mockFetch.mockRoute(mergeBoxPageDataRoute, {}, {status: 401, ok: false})
    mockFetch.mockRoute(statusChecksPageDataRoute, {})

    try {
      renderWithClient(<TestComponent />)

      await waitFor(() => {
        expect(screen.queryByText('Loading')).not.toBeInTheDocument()
      })
    } catch {
      act(() => jest.runAllTimers())
      await screen.findByText('Merge status cannot be loaded')
      await screen.findByText('Try reloading the page, or if the problem persists')
    }

    // Note: this spy asserts that a console.error() was made for thrown error that is caught above.
    expect(spy).toHaveBeenCalled()
    spy.mockRestore()
    expectMockFetchCalledTimes(mergeBoxPageDataRoute, 1)
  })
})

describe('Checks section', () => {
  test('it does not render if no checks are present', async () => {
    mockFetch.mockRoute(mergeBoxPageDataRoute, mergeBoxMockData())
    mockFetch.mockRoute(statusChecksPageDataRoute, checksSectionNoChecksState)
    renderWithClient(<TestComponent />)

    await waitFor(() => {
      expect(screen.queryByText('Loading')).not.toBeInTheDocument()
    })
    await waitFor(() => expect(screen.queryByLabelText(/checks/)).not.toBeInTheDocument())
    expectMockFetchCalledTimes(mergeBoxPageDataRoute, 1)
    expectMockFetchCalledTimes(statusChecksPageDataRoute, 1)
  })

  test('it renders the status check groups', async () => {
    mockFetch.mockRoute(mergeBoxPageDataRoute, mergeBoxMockData())
    mockFetch.mockRoute(statusChecksPageDataRoute, checksSectionSomeFailedState)
    renderWithClient(<TestComponent />)

    await screen.findByText('1 successful check')
    screen.getByText('1 failing check')
    expectMockFetchCalledTimes(mergeBoxPageDataRoute, 1)
    expectMockFetchCalledTimes(statusChecksPageDataRoute, 1)
  })

  test('it renders the fallback when the status checks endpoint fails and still shows the outer mergebox', async () => {
    jest.useFakeTimers()
    const spy = jest.spyOn(console, 'error').mockImplementation()

    mockFetch.mockRoute(mergeBoxPageDataRoute, mergeBoxMockData())
    mockFetch.mockRoute(statusChecksPageDataRoute, {}, {status: 401, ok: false})

    renderWithClient(<TestComponent />)

    await screen.findByText('Checks cannot be loaded right now')
    screen.getByText(
      (_, el) =>
        el?.nodeName === 'P' &&
        el.textContent === 'Try again or if the problem persists contact support or view the Checks tab.',
    )

    // Note: this spy asserts that a console.error() was made for thrown error that is caught above.
    expect(spy).toHaveBeenCalled()
    spy.mockRestore()
    expectMockFetchCalledTimes(mergeBoxPageDataRoute, 1)
    expect(screen.getByText('Merge when ready')).toBeInTheDocument()
  })

  test('merge box updates checks list when new data is returned from an alive channel,', async () => {
    mockFetch.mockRoute(mergeBoxPageDataRoute, mergeBoxMockData())
    mockFetch.mockRoute(statusChecksPageDataRoute, checksSectionPendingState)
    renderWithClient(<TestComponent />)

    expect(await screen.findByText('1 pending check')).toBeVisible()
    expect(screen.queryByText('2 successful checks')).not.toBeInTheDocument()

    mockFetch.mockRoute(statusChecksPageDataRoute, checksSectionPassingState)
    act(() => {
      dispatchAliveTestMessage(unsignedCommitHeadShaChannel, {})
    })

    expect(await screen.findByText('2 successful checks')).toBeVisible()
    expect(screen.queryByText('1 pending check')).not.toBeInTheDocument()
    expectMockFetchCalledTimes(mergeBoxPageDataRoute, 2)
    expectMockFetchCalledTimes(statusChecksPageDataRoute, 2)
  })
})

describe('closed and merged state', () => {
  // More tests live in ClosedOrMergeStateMergeBox.test.tsx
  test('it renders the closed state if the viewer can take an action', async () => {
    mockFetch.mockRoute(mergeBoxPageDataRoute, mergeBoxMockData({pullRequestKind: 'closedWithUserActionsAllowed'}))
    mockFetch.mockRoute(statusChecksPageDataRoute, checksSectionNoChecksState)
    renderWithClient(<TestComponent />)

    await waitFor(() => {
      expect(screen.queryByText('Loading')).not.toBeInTheDocument()
    })
    expect(screen.getByText('Closed with unmerged commits')).toBeInTheDocument()
    expectMockFetchCalledTimes(mergeBoxPageDataRoute, 1)
  })

  test('it renders the merged state if the viewer can take an action', async () => {
    mockFetch.mockRoute(statusChecksPageDataRoute, checksSectionNoChecksState)
    mockFetch.mockRoute(mergeBoxPageDataRoute, mergeBoxMockData({pullRequestKind: 'mergedWithUserActionsAllowed'}))
    renderWithClient(<TestComponent />)

    await waitFor(() => {
      expect(screen.queryByText('Loading')).not.toBeInTheDocument()
    })
    expect(screen.getByText('Pull request successfully merged and closed')).toBeInTheDocument()
    expectMockFetchCalledTimes(mergeBoxPageDataRoute, 1)
  })

  test('it renders the correct messaging if PR is closed', async () => {
    mockFetch.mockRoute(mergeBoxPageDataRoute, mergeBoxMockData({pullRequestKind: 'closedWithUserActionsAllowed'}))
    mockFetch.mockRoute(statusChecksPageDataRoute, checksSectionNoChecksState)
    renderWithClient(<TestComponent />)

    await waitFor(() => {
      expect(screen.queryByText('Loading')).not.toBeInTheDocument()
    })
    expect(screen.getByText('Closed with unmerged commits')).toBeInTheDocument()
    expectMockFetchCalledTimes(mergeBoxPageDataRoute, 1)
  })

  test('it does not show the merge section if the user cannot push to the base repo', async () => {
    mockFetch.mockRoute(
      mergeBoxPageDataRoute,
      mergeBoxMockData({
        pullRequestKind: 'withDirectMergeEnabled',
        mergeRequirementsKind: 'userRequiresPushAccessToMerge',
      }),
    )
    mockFetch.mockRoute(statusChecksPageDataRoute, checksSectionNoChecksState)
    renderWithClient(<TestComponent />)

    await waitFor(() => {
      expect(screen.queryByText('Loading')).not.toBeInTheDocument()
    })

    expect(screen.queryByRole('button', {name: 'Merge pull request'})).not.toBeInTheDocument()
    expectMockFetchCalledTimes(mergeBoxPageDataRoute, 1)
  })

  test('it does not show the merge section if the user cannot push to the base repo because they are blocked by an authorization policy', async () => {
    mockFetch.mockRoute(
      mergeBoxPageDataRoute,
      mergeBoxMockData({
        pullRequestKind: 'withMergeQueueEnabled',
        mergeRequirementsKind: 'userCanPushButIsBlockedByAuthorizationPolicy',
      }),
    )
    mockFetch.mockRoute(statusChecksPageDataRoute, checksSectionNoChecksState)
    renderWithClient(<TestComponent enabledFeatures={{hide_merge_section_if_user_cannot_push_to_base: true}} />)

    await waitFor(() => {
      expect(screen.queryByText('Loading')).not.toBeInTheDocument()
    })

    expect(screen.queryByRole('button', {name: 'Merge when ready'})).not.toBeInTheDocument()
    expectMockFetchCalledTimes(mergeBoxPageDataRoute, 1)
  })
})

describe('mergeability icons', () => {
  test('it does not render the icon if the PR is closed and the viewer cannot delete the head ref or restore the head ref', async () => {
    mockFetch.mockRoute(mergeBoxPageDataRoute, mergeBoxMockData({pullRequestKind: 'closedWithoutUserActionsAllowed'}))
    renderWithClient(<TestComponent />)

    await waitFor(() => {
      expect(screen.queryByText('Loading')).not.toBeInTheDocument()
    })
    expect(screen.queryByLabelText('Merged')).not.toBeInTheDocument()
  })

  test('it does render the icon if the PR is closed and the viewer can either delete the head ref or restore the head ref', async () => {
    mockFetch.mockRoute(mergeBoxPageDataRoute, mergeBoxMockData({pullRequestKind: 'closedWithUserActionsAllowed'}))
    renderWithClient(<TestComponent />)

    await waitFor(() => {
      expect(screen.queryByText('Loading')).not.toBeInTheDocument()
    })
    expect(screen.getByLabelText('Closed')).toBeInTheDocument()
  })

  test('it does render the icon if the PR is merged and the viewer can either delete the head ref or restore the head ref', async () => {
    mockFetch.mockRoute(mergeBoxPageDataRoute, mergeBoxMockData({pullRequestKind: 'mergedWithUserActionsAllowed'}))
    renderWithClient(<TestComponent />)

    await waitFor(() => {
      expect(screen.queryByText('Loading')).not.toBeInTheDocument()
    })
    expect(screen.getByLabelText('Merged')).toBeInTheDocument()
  })
})

describe('mergeability icons - responsive behavior', () => {
  test('has the correct classes to hide the icon when the screen size is small', async () => {
    mockFetch.mockRoute(mergeBoxPageDataRoute, mergeBoxMockData({pullRequestKind: 'draft'}))
    mockFetch.mockRoute(statusChecksPageDataRoute, checksSectionNoChecksState)

    renderWithClient(<TestComponent />)
    await waitFor(() => {
      expect(screen.queryByText('Loading')).not.toBeInTheDocument()
    })

    expect(screen.getByTestId('mergeability-icon-wrapper')).toHaveClass('d-none d-lg-block')
  })
})

test('It only shows the confirm merge form if a user is confirming selected merge', async () => {
  mockFetch.mockRoute(
    mergeBoxPageDataRoute,
    mergeBoxMockData({
      pullRequestKind: 'withDirectMergeEnabled',
      mergeRequirementsKind: 'mergeable',
    }),
  )
  mockFetch.mockRoute(statusChecksPageDataRoute, checksSectionPassingState)
  const {user} = renderWithClient(<TestComponent enabledFeatures={{merge_box_hide_sections: true}} />)

  await waitFor(() => expect(screen.queryByText('Loading')).not.toBeInTheDocument())

  expect(screen.getByLabelText('Reviews')).toBeInTheDocument()
  expect(screen.getByLabelText('Checks')).toBeInTheDocument()
  expect(screen.getByLabelText('Conflicts')).toBeInTheDocument()

  const mergeButton = await screen.findByRole('button', {name: 'Merge pull request'})

  await user.click(mergeButton)

  expect(await screen.findByRole('button', {name: 'Confirm merge'})).toBeInTheDocument()

  expect(screen.queryByLabelText('Reviews')).toBeNull()
  expect(screen.queryByLabelText('Checks')).toBeNull()
  expect(screen.queryByLabelText('Conflicts')).toBeNull()
})
