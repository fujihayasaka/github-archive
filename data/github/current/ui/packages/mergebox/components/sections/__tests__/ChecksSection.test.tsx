import {useAnalytics} from '@github-ui/use-analytics'
import {screen, waitFor} from '@testing-library/react'
import {renderWithClient, BASE_PAGE_DATA_URL} from '@github-ui/pull-request-page-data-tooling/render-with-query-client'
import {PageData} from '@github-ui/pull-request-page-data-tooling/page-data'
import {mockFetch} from '@github-ui/mock-fetch'

import {StatusCheckGenerator} from '../../../test-utils/object-generators/status-check'
import {
  checksSectionFailedState,
  checksSectionFailedTimedOutState,
  checksSectionPassingState,
  checksSectionPassingWithSkippedState,
  checksSectionPendingState,
  checksSectionPendingFromQueuedState,
  checksSectionPendingWithFailureState,
  checksSectionSomeFailedState,
  checksSectionPendingApproval,
  checksSectionPendingApprovalWithChecks,
  checksSectionRequested,
} from '../../../test-utils/mocks/checks-section-mocks'
import {aliveChannels} from '../../../test-utils/mocks/alive-channels-mock'
import {AliveTestProvider} from '@github-ui/use-alive/test-utils'
import type {StatusChecksPageData} from '../../../page-data/payloads/status-checks'
import {assertButtonInLoadingState} from '../../../test-utils/loading-button-asserts'
import {ChecksSection, type ChecksSectionProps} from '../ChecksSection'

import type {ChecksSectionStatusType} from '../../../helpers/merge-box-status-calculator/checks-section-status'

jest.mock('@github-ui/use-analytics')
const sendAnalyticsEventMock = jest.fn()
jest.mocked(useAnalytics).mockReturnValue({sendAnalyticsEvent: sendAnalyticsEventMock})

beforeEach(() => sendAnalyticsEventMock.mockReset())

const statusChecksPageDataRoute = `${BASE_PAGE_DATA_URL}/page_data/${PageData.statusChecks}`
const runActionRequiredWorkflowsRoute = `${BASE_PAGE_DATA_URL}/page_data/${PageData.runActionRequiredWorkflows}`

const defaultProps: ChecksSectionProps = {
  pullRequestId: 'pullRequest123',
  pullRequestHeadSha: 'mock-head-sha',
  focusPrimaryMergeButton: jest.fn(),
  sectionStatus: 'PENDING' as ChecksSectionStatusType,
  shouldRender: true,
}

function TestComponent(props: ChecksSectionProps) {
  return (
    <AliveTestProvider>
      <ChecksSection {...props} />
    </AliveTestProvider>
  )
}

describe('preview view', () => {
  test('renders if there are no checks and the status is PENDING_APPROVAL', async () => {
    mockFetch.mockRoute(statusChecksPageDataRoute, checksSectionPendingApproval)
    const props: ChecksSectionProps = {...defaultProps, sectionStatus: 'PENDING_APPROVAL'}

    renderWithClient(<TestComponent {...props} />)
    await screen.findByText('1 workflow awaiting approval')
    expect(screen.getByText('This workflow requires approval from a maintainer.')).toBeInTheDocument()
  })

  test('renders pending state when there are pending checks and no failures', async () => {
    mockFetch.mockRoute(statusChecksPageDataRoute, checksSectionPendingState)
    renderWithClient(<TestComponent {...defaultProps} />)

    await screen.findByText("Some checks haven't completed yet")
    expect(screen.getByText('1 pending check')).toBeInTheDocument()
  })

  test('renders the pending-failed state when there are pending checks and any failures', async () => {
    mockFetch.mockRoute(statusChecksPageDataRoute, checksSectionPendingWithFailureState)
    const props: ChecksSectionProps = {...defaultProps, sectionStatus: 'PENDING_FAILED'}
    renderWithClient(<TestComponent {...props} />)

    await screen.findByText('Some checks were not successful')
    expect(screen.getByText('3 failing, 3 pending, 3 successful checks')).toBeInTheDocument()
  })

  test('renders the passed state when all checks have passed', async () => {
    mockFetch.mockRoute(statusChecksPageDataRoute, checksSectionPassingState)
    const props: ChecksSectionProps = {...defaultProps, sectionStatus: 'PASSED'}
    renderWithClient(<TestComponent {...props} />)

    await screen.findByText('All checks have passed')
    expect(screen.getByText('2 successful checks')).toBeInTheDocument()
  })

  test('renders the some-failed state when all checks have completed and some failed', async () => {
    mockFetch.mockRoute(statusChecksPageDataRoute, checksSectionSomeFailedState)
    const props: ChecksSectionProps = {...defaultProps, sectionStatus: 'SOME_FAILED'}
    renderWithClient(<TestComponent {...props} />)

    await screen.findByText('Some checks were not successful')
    expect(screen.getByText('1 failing, 1 successful checks')).toBeInTheDocument()
  })

  test('renders the failed state when all checks have completed and failed', async () => {
    mockFetch.mockRoute(statusChecksPageDataRoute, checksSectionFailedState)
    const props: ChecksSectionProps = {...defaultProps, sectionStatus: 'FAILED'}
    renderWithClient(<TestComponent {...props} />)

    await screen.findByText('All checks have failed')
    expect(screen.getByText('2 failing checks')).toBeInTheDocument()
  })

  test('records cancelled, timed out, and stale check runs separately', async () => {
    const response: StatusChecksPageData = {
      aliveChannels: {commitHeadShaChannel: aliveChannels.commitHeadShaChannel},
      statusRollup: {
        summary: [
          {count: 1, state: 'SUCCESS'},
          {count: 1, state: 'TIMED_OUT'},
          {count: 1, state: 'CANCELLED'},
          {count: 1, state: 'STALE'},
          {count: 1, state: 'FAILURE'},
        ],
        combinedState: 'SOME_FAILED',
        pendingWorkflowApprovalRollup: null,
      },
      statusChecks: [
        StatusCheckGenerator({state: 'SUCCESS'}),
        StatusCheckGenerator({state: 'TIMED_OUT'}),
        StatusCheckGenerator({state: 'CANCELLED'}),
        StatusCheckGenerator({state: 'STALE'}),
        StatusCheckGenerator({state: 'FAILURE'}),
      ],
    }
    mockFetch.mockRoute(statusChecksPageDataRoute, response)
    const props: ChecksSectionProps = {...defaultProps, sectionStatus: 'SOME_FAILED'}
    renderWithClient(<TestComponent {...props} />)

    await screen.findByText('Some checks were not successful')
    expect(screen.getByText('1 failing, 1 timed out, 1 cancelled, 1 stale, 1 successful checks')).toBeInTheDocument()
  })

  test('records failure, error, and startup failure status as failures', async () => {
    const response: StatusChecksPageData = {
      aliveChannels: {commitHeadShaChannel: aliveChannels.commitHeadShaChannel},
      statusRollup: {
        summary: [
          {count: 1, state: 'STARTUP_FAILURE'},
          {count: 2, state: 'FAILURE'},
          {count: 1, state: 'ERROR'},
        ],
        combinedState: 'FAILED',
        pendingWorkflowApprovalRollup: null,
      },
      statusChecks: [
        StatusCheckGenerator({state: 'STARTUP_FAILURE'}),
        StatusCheckGenerator({state: 'FAILURE'}),
        StatusCheckGenerator({state: 'FAILURE'}),
        StatusCheckGenerator({state: 'ERROR'}),
      ],
    }
    mockFetch.mockRoute(statusChecksPageDataRoute, response)
    const props: ChecksSectionProps = {...defaultProps, sectionStatus: 'FAILED'}
    renderWithClient(<TestComponent {...props} />)

    await screen.findByText('All checks have failed')
    expect(screen.getByText('4 failing checks')).toBeInTheDocument()
  })

  test('records success and neutral as separate states', async () => {
    const response: StatusChecksPageData = {
      aliveChannels: {commitHeadShaChannel: aliveChannels.commitHeadShaChannel},
      statusRollup: {
        summary: [
          {count: 1, state: 'SUCCESS'},
          {count: 1, state: 'NEUTRAL'},
        ],
        combinedState: 'PASSED',
        pendingWorkflowApprovalRollup: null,
      },
      statusChecks: [StatusCheckGenerator({state: 'SUCCESS'}), StatusCheckGenerator({state: 'NEUTRAL'})],
    }
    mockFetch.mockRoute(statusChecksPageDataRoute, response)
    const props: ChecksSectionProps = {...defaultProps, sectionStatus: 'PASSED'}
    renderWithClient(<TestComponent {...props} />)

    await screen.findByText('All checks have passed')
    expect(screen.getByText('1 neutral, 1 successful checks')).toBeInTheDocument()
  })

  test('records pending, waiting, and action required as pending states', async () => {
    const response: StatusChecksPageData = {
      aliveChannels: {commitHeadShaChannel: aliveChannels.commitHeadShaChannel},
      statusRollup: {
        summary: [
          {count: 1, state: 'ACTION_REQUIRED'},
          {count: 1, state: 'PENDING'},
          {count: 1, state: 'WAITING'},
        ],
        combinedState: 'PENDING',
        pendingWorkflowApprovalRollup: null,
      },
      statusChecks: [
        StatusCheckGenerator({state: 'ACTION_REQUIRED'}),
        StatusCheckGenerator({state: 'PENDING'}),
        StatusCheckGenerator({state: 'WAITING'}),
      ],
    }
    mockFetch.mockRoute(statusChecksPageDataRoute, response)
    renderWithClient(<TestComponent {...defaultProps} />)

    await screen.findByText("Some checks haven't completed yet")
    expect(screen.getByText('3 pending checks')).toBeInTheDocument()
  })

  test('records in_progress and pending as separate states', async () => {
    const response: StatusChecksPageData = {
      aliveChannels: {commitHeadShaChannel: aliveChannels.commitHeadShaChannel},
      statusRollup: {
        summary: [
          {count: 1, state: 'IN_PROGRESS'},
          {count: 1, state: 'PENDING'},
        ],
        combinedState: 'PENDING',
        pendingWorkflowApprovalRollup: null,
      },
      statusChecks: [StatusCheckGenerator({state: 'IN_PROGRESS'}), StatusCheckGenerator({state: 'PENDING'})],
    }
    mockFetch.mockRoute(statusChecksPageDataRoute, response)
    renderWithClient(<TestComponent {...defaultProps} />)

    await screen.findByText("Some checks haven't completed yet")
    expect(screen.getByText('1 pending, 1 in progress checks')).toBeInTheDocument()
  })

  test('counts queued statuses as pending', async () => {
    mockFetch.mockRoute(statusChecksPageDataRoute, checksSectionPendingFromQueuedState)
    renderWithClient(<TestComponent {...defaultProps} />)

    await screen.findByText("Some checks haven't completed yet")
    expect(screen.getByText('1 queued check')).toBeInTheDocument()
  })

  test('counts requested check runs as pending', async () => {
    const response: StatusChecksPageData = {
      aliveChannels: {commitHeadShaChannel: aliveChannels.commitHeadShaChannel},
      statusRollup: {
        summary: [{count: 1, state: 'REQUESTED'}],
        combinedState: 'PENDING',
        pendingWorkflowApprovalRollup: null,
      },
      statusChecks: [StatusCheckGenerator({state: 'REQUESTED'})],
    }
    mockFetch.mockRoute(statusChecksPageDataRoute, response)
    renderWithClient(<TestComponent {...defaultProps} />)

    await screen.findByText("Some checks haven't completed yet")
    expect(screen.getByText('1 requested check')).toBeInTheDocument()
  })

  test('counts skipped checks as success', async () => {
    mockFetch.mockRoute(statusChecksPageDataRoute, checksSectionPassingWithSkippedState)
    const props: ChecksSectionProps = {...defaultProps, sectionStatus: 'PASSED'}
    renderWithClient(<TestComponent {...props} />)

    await screen.findByText('All checks have passed')
    expect(screen.getByText('1 skipped check')).toBeInTheDocument()
  })

  test('counts timed out checks as failure', async () => {
    mockFetch.mockRoute(statusChecksPageDataRoute, checksSectionFailedTimedOutState)
    const props: ChecksSectionProps = {...defaultProps, sectionStatus: 'FAILED'}
    renderWithClient(<TestComponent {...props} />)

    await screen.findByText('All checks have failed')
    expect(screen.getByText('1 timed out check')).toBeInTheDocument()
  })
})

test('when all checks pass, component is not expanded', async () => {
  mockFetch.mockRoute(statusChecksPageDataRoute, checksSectionPassingState)
  const props: ChecksSectionProps = {...defaultProps, sectionStatus: 'PASSED'}
  renderWithClient(<TestComponent {...props} />)

  const collapsedButton = await screen.findByRole('button', {name: 'Expand checks', expanded: false})
  expect(collapsedButton).toBeInTheDocument()
})

describe('when the combined status is PENDING_APPROVAL', () => {
  test('when there are multiple pending workflows and no expired workflow runs', async () => {
    const response: StatusChecksPageData = {
      ...checksSectionPendingApproval,
      statusRollup: {
        ...checksSectionPendingApproval.statusRollup,
        pendingWorkflowApprovalRollup: {
          workflowsRequiringApprovalCount: 2,
          viewerCanApproveWorkflowRuns: true,
          hasExpiredWorkflowRuns: false,
          approvalRequiredMessage: 'This workflow requires approval from a maintainer.',
          helpLink: 'https://help.github',
        },
      },
    }
    mockFetch.mockRoute(statusChecksPageDataRoute, response)
    const props: ChecksSectionProps = {...defaultProps, sectionStatus: 'PENDING_APPROVAL'}

    renderWithClient(<TestComponent {...props} />)

    await screen.findByText('2 workflows awaiting approval')
    expect(screen.getByText('This workflow requires approval from a maintainer.')).toBeInTheDocument()
    expect(screen.getByRole('link', {name: 'Learn more about approving workflows.'})).toBeInTheDocument()
  })

  test('when there are expired workflow runs', async () => {
    const response: StatusChecksPageData = {
      ...checksSectionPendingApproval,
      statusRollup: {
        ...checksSectionPendingApproval.statusRollup,
        pendingWorkflowApprovalRollup: {
          workflowsRequiringApprovalCount: 2,
          viewerCanApproveWorkflowRuns: true,
          hasExpiredWorkflowRuns: true,
          approvalRequiredMessage: 'This workflow requires approval from a maintainer.',
          helpLink: 'https://help.github',
        },
      },
    }
    mockFetch.mockRoute(statusChecksPageDataRoute, response)
    const props: ChecksSectionProps = {...defaultProps, sectionStatus: 'PENDING_APPROVAL'}

    renderWithClient(<TestComponent {...props} />)

    await screen.findByText('2 workflows awaiting approval')
    expect(screen.queryByText('This workflow requires approval from a maintainer.')).not.toBeInTheDocument()
    expect(
      screen.getByText('Unable to re-run one or more workflows because they were created over a month ago.'),
    ).toBeInTheDocument()
    expect(screen.queryByRole('link', {name: 'Learn more about approving workflows.'})).not.toBeInTheDocument()
  })

  test('when the user can approve pending workflow runs', async () => {
    const response: StatusChecksPageData = {
      ...checksSectionPendingApproval,
      statusRollup: {
        ...checksSectionPendingApproval.statusRollup,
        pendingWorkflowApprovalRollup: {
          workflowsRequiringApprovalCount: 2,
          viewerCanApproveWorkflowRuns: true,
          hasExpiredWorkflowRuns: true,
          approvalRequiredMessage: 'This workflow requires approval from a maintainer.',
          helpLink: 'https://help.github',
        },
      },
    }
    mockFetch.mockRoute(statusChecksPageDataRoute, response)
    const props: ChecksSectionProps = {...defaultProps, sectionStatus: 'PENDING_APPROVAL'}

    renderWithClient(<TestComponent {...props} />)

    await screen.findByText('2 workflows awaiting approval')
    expect(screen.getByRole('button', {name: 'Approve and run workflows'})).toBeInTheDocument()
  })

  test('approving a workflow run - success', async () => {
    const response: StatusChecksPageData = {
      ...checksSectionPendingApproval,
      statusRollup: {
        ...checksSectionPendingApproval.statusRollup,
        pendingWorkflowApprovalRollup: {
          workflowsRequiringApprovalCount: 2,
          viewerCanApproveWorkflowRuns: true,
          hasExpiredWorkflowRuns: true,
          approvalRequiredMessage: 'This workflow requires approval from a maintainer.',
          helpLink: 'https://help.github',
        },
      },
    }
    mockFetch.mockRoute(statusChecksPageDataRoute, response)
    const props: ChecksSectionProps = {...defaultProps, sectionStatus: 'PENDING_APPROVAL'}

    const {user} = renderWithClient(<TestComponent {...props} />)

    await screen.findByText('2 workflows awaiting approval')
    const button = screen.getByRole('button', {name: 'Approve and run workflows'})
    expect(button).toBeInTheDocument()

    await user.click(button)
    assertButtonInLoadingState(button, 'Re-running workflows')

    mockFetch.resolvePendingRequest(
      runActionRequiredWorkflowsRoute,
      {message: 'Successfully approved pending workflows '},
      {status: 200, ok: true},
    )
  })

  test('approving a workflow run - error', async () => {
    const response: StatusChecksPageData = {
      ...checksSectionPendingApproval,
      statusRollup: {
        ...checksSectionPendingApproval.statusRollup,
        pendingWorkflowApprovalRollup: {
          workflowsRequiringApprovalCount: 2,
          viewerCanApproveWorkflowRuns: true,
          hasExpiredWorkflowRuns: true,
          approvalRequiredMessage: 'This workflow requires approval from a maintainer.',
          helpLink: 'https://help.github',
        },
      },
    }
    mockFetch.mockRoute(statusChecksPageDataRoute, response)
    const props: ChecksSectionProps = {...defaultProps, sectionStatus: 'PENDING_APPROVAL'}

    const {user} = renderWithClient(<TestComponent {...props} />)

    await screen.findByText('2 workflows awaiting approval')
    const button = screen.getByRole('button', {name: 'Approve and run workflows'})
    expect(button).toBeInTheDocument()

    await user.click(button)
    assertButtonInLoadingState(button, 'Re-running workflows')
    const errorMessage =
      'Unable to re-run one or more workflows. Check if the workflows are already running, are more than 30 days old, or are disabled.'

    mockFetch.resolvePendingRequest(
      runActionRequiredWorkflowsRoute,
      {
        error: errorMessage,
      },
      {status: 422, ok: false},
    )

    expect(await screen.findByText(errorMessage)).toBeInTheDocument()
  })

  test('when the user cannot approve pending workflow runs', async () => {
    const response: StatusChecksPageData = {
      ...checksSectionPendingApproval,
      statusRollup: {
        ...checksSectionPendingApproval.statusRollup,
        pendingWorkflowApprovalRollup: {
          workflowsRequiringApprovalCount: 2,
          viewerCanApproveWorkflowRuns: false,
          hasExpiredWorkflowRuns: true,
          approvalRequiredMessage: 'This workflow requires approval from a maintainer.',
          helpLink: 'https://help.github',
        },
      },
    }
    mockFetch.mockRoute(statusChecksPageDataRoute, response)
    const props: ChecksSectionProps = {...defaultProps, sectionStatus: 'PENDING_APPROVAL'}

    renderWithClient(<TestComponent {...props} />)

    await screen.findByText('2 workflows awaiting approval')
    expect(screen.queryByRole('button', {name: 'Approve and run workflows'})).not.toBeInTheDocument()
  })

  test('displays checks if they exist and does not allow section to be collapsed', async () => {
    mockFetch.mockRoute(statusChecksPageDataRoute, checksSectionPendingApprovalWithChecks)

    const props: ChecksSectionProps = {...defaultProps, sectionStatus: 'PENDING_APPROVAL'}
    renderWithClient(<TestComponent {...props} />)

    await screen.findByText('1 workflow awaiting approval')
    expect(screen.getByRole('button', {name: 'Approve and run workflows'})).toBeInTheDocument()
    expect(screen.getByText('1 pending check')).toBeInTheDocument()
    expect(screen.getByText('1 successful check')).toBeInTheDocument()
    expect(screen.queryByRole('button', {name: 'Collapse checks', expanded: true})).not.toBeInTheDocument()
    expect(screen.queryByRole('button', {name: 'Expand checks', expanded: false})).not.toBeInTheDocument()
  })
})

test('when all checks are not passing, component is expanded by default', async () => {
  mockFetch.mockRoute(statusChecksPageDataRoute, checksSectionSomeFailedState)
  const props: ChecksSectionProps = {...defaultProps, sectionStatus: 'SOME_FAILED'}
  renderWithClient(<TestComponent {...props} />)

  const expandedButton = await screen.findByRole('button', {name: 'Collapse checks', expanded: true})
  expect(expandedButton).toBeInTheDocument()
})

describe('Analytics events', () => {
  test('it emits events when user expands or collapses checks section', async () => {
    mockFetch.mockRoute(statusChecksPageDataRoute, checksSectionSomeFailedState)
    const {user} = renderWithClient(<TestComponent {...defaultProps} />)

    const expectedMetadata = {
      statusCheckCounts: JSON.stringify({SUCCESS: 1, FAILURE: 1}),
    }

    const expandedButton = await screen.findByRole('button', {name: 'Collapse checks', expanded: true})
    await user.click(expandedButton)

    expect(sendAnalyticsEventMock).toHaveBeenCalledWith(
      'checks_section.collapse',
      'MERGEBOX_CHECKS_SECTION_TOGGLE_BUTTON',
      expectedMetadata,
    )

    const collapsedButton = await screen.findByRole('button', {name: 'Expand checks', expanded: false})
    await user.click(collapsedButton)

    expect(sendAnalyticsEventMock).toHaveBeenCalledWith(
      'checks_section.expand',
      'MERGEBOX_CHECKS_SECTION_TOGGLE_BUTTON',
      expectedMetadata,
    )

    // Test that we don't make additional calls
    expect(sendAnalyticsEventMock).toHaveBeenCalledTimes(2)
  })

  test('it emits events when user expands or collapses check group sections', async () => {
    const expectedMetadata = {
      statusCheckCounts: JSON.stringify({SUCCESS: 1, FAILURE: 1}),
    }
    const eventTarget = 'MERGEBOX_CHECKS_GROUP_TOGGLE_BUTTON'
    mockFetch.mockRoute(statusChecksPageDataRoute, checksSectionSomeFailedState)
    const {user} = renderWithClient(<TestComponent {...defaultProps} />)

    await user.click(await screen.findByRole('button', {name: 'Collapse 1 failing check group'}))

    expect(sendAnalyticsEventMock).toHaveBeenCalledWith('checks_group.collapse', eventTarget, {
      ...expectedMetadata,
      group: 'FAILURE',
    })

    await user.click(screen.getByRole('button', {name: 'Expand 1 failing check group'}))

    expect(sendAnalyticsEventMock).toHaveBeenCalledWith('checks_group.expand', eventTarget, {
      ...expectedMetadata,
      group: 'FAILURE',
    })

    await user.click(screen.getByRole('button', {name: 'Collapse 1 successful check group'}))

    expect(sendAnalyticsEventMock).toHaveBeenCalledWith('checks_group.collapse', eventTarget, {
      ...expectedMetadata,
      group: 'SUCCESS',
    })

    await user.click(screen.getByRole('button', {name: 'Expand 1 successful check group'}))

    expect(sendAnalyticsEventMock).toHaveBeenCalledWith('checks_group.expand', eventTarget, {
      ...expectedMetadata,
      group: 'SUCCESS',
    })

    // Test that we don't make additional calls
    expect(sendAnalyticsEventMock).toHaveBeenCalledTimes(4)
  })
})

test('Check sections can be expanded and collapsed', async () => {
  const response: StatusChecksPageData = {
    aliveChannels: {commitHeadShaChannel: aliveChannels.commitHeadShaChannel},
    statusRollup: {
      summary: [
        {count: 1, state: 'SUCCESS'},
        {count: 1, state: 'FAILURE'},
      ],
      combinedState: 'SOME_FAILED',
      pendingWorkflowApprovalRollup: null,
    },
    statusChecks: [
      StatusCheckGenerator({state: 'SUCCESS', displayName: 'test workflow / Check Run 1'}),
      StatusCheckGenerator({state: 'FAILURE', displayName: 'test workflow / Check Run 2'}),
    ],
  }
  mockFetch.mockRoute(statusChecksPageDataRoute, response)
  const {user} = renderWithClient(<TestComponent {...defaultProps} />)

  await user.click(await screen.findByRole('button', {name: 'Collapse 1 successful check group'}))
  expect(screen.getByRole('button', {name: 'Expand 1 successful check group'})).toBeInTheDocument()
  await user.click(screen.getByRole('button', {name: 'Collapse 1 failing check group'}))
  expect(screen.getByRole('button', {name: 'Expand 1 failing check group'})).toBeInTheDocument()
})

test('Checks section indicates that checks will not run with merge conflicts', async () => {
  mockFetch.mockRoute(statusChecksPageDataRoute, checksSectionRequested)
  const props: ChecksSectionProps = {
    pullRequestId: 'pullRequest123',
    pullRequestHeadSha: 'mock-head-sha',
    focusPrimaryMergeButton: jest.fn(),
    sectionStatus: 'PENDING_CONFLICTS',
    shouldRender: true,
  }
  renderWithClient(<TestComponent {...props} />)
  await screen.findByText('Checks awaiting conflict resolution')
  expect(screen.getByText('Checks awaiting conflict resolution')).toBeInTheDocument()
})

test('Checks section does not render if passed shouldRender as false', async () => {
  mockFetch.mockRoute(statusChecksPageDataRoute, checksSectionRequested)
  const props: ChecksSectionProps = {
    pullRequestId: 'pullRequest123',
    pullRequestHeadSha: 'mock-head-sha',
    focusPrimaryMergeButton: jest.fn(),
    sectionStatus: 'PENDING_CONFLICTS',
    shouldRender: false,
  }
  renderWithClient(<TestComponent {...props} />)

  await waitFor(() => {
    expect(screen.queryByText('Checks awaiting conflict resolution')).not.toBeInTheDocument()
  })
})
