import {expectAnalyticsEvents} from '@github-ui/analytics-test-utils'
import {screen} from '@testing-library/react'

import {ConflictsSection as TestComponent} from '../ConflictsSection'
import type {ConflictsSectionProps} from '../ConflictsSection'
import {BASE_PAGE_DATA_URL, renderWithClient} from '@github-ui/pull-request-page-data-tooling/render-with-query-client'
import {PageData} from '@github-ui/pull-request-page-data-tooling/page-data'
import {mockFetch} from '@github-ui/mock-fetch'
import {fetchPoll} from '@github-ui/fetch-utils'
import {
  conflictsSectionCleanMergeState,
  conflictsSectionComplexConflictsMergeState,
  conflictsSectionPendingMergeState,
  conflictsSectionStandardConflictsMergeState,
} from '../../../test-utils/mocks/conflicts-condition-mock'

const conflictSectionPullRequest = {
  baseRefName: 'main',
  headRefOid: 'abc123',
  id: 'pr-123',
  resourcePath: '/octocat/Hello-World/pull/123',
  viewerCanUpdateBranch: false,
  viewerLogin: 'monalisa',
  canUserPushToBase: true,
}

afterEach(() => {
  jest.clearAllMocks()
})

describe('CLEAN, UNSTABLE, and HAS_HOOKS merge state status map to clean state of the conflicts section', () => {
  test('when mergeStateStatus is CLEAN, renders clean merge state', async () => {
    const props: ConflictsSectionProps = {
      ...conflictSectionPullRequest,
      ...conflictsSectionCleanMergeState,
    }
    renderWithClient(<TestComponent {...props} />)

    expect(screen.getByText('Merging can be performed automatically.')).toBeInTheDocument()
    expect(screen.getByText('No conflicts with base branch')).toBeInTheDocument()
  })

  test('when mergeStateStatus is UNSTABLE, renders clean merge state', async () => {
    const props: ConflictsSectionProps = {
      ...conflictSectionPullRequest,
      ...conflictsSectionCleanMergeState,
      mergeStateStatus: 'UNSTABLE',
    }
    renderWithClient(<TestComponent {...props} />)

    expect(screen.getByText('Merging can be performed automatically.')).toBeInTheDocument()
    expect(screen.getByText('No conflicts with base branch')).toBeInTheDocument()
  })

  test('when mergeStateStatus is HAS_HOOKS, renders clean merge state', async () => {
    const props: ConflictsSectionProps = {
      ...conflictSectionPullRequest,
      ...conflictsSectionCleanMergeState,
      mergeStateStatus: 'HAS_HOOKS',
    }
    renderWithClient(<TestComponent {...props} />)

    expect(screen.getByText('Merging can be performed automatically.')).toBeInTheDocument()
    expect(screen.getByText('No conflicts with base branch')).toBeInTheDocument()
  })

  test('clean merge state shows update branch button if viewer can update branch', async () => {
    const props: ConflictsSectionProps = {
      ...conflictSectionPullRequest,
      ...conflictsSectionCleanMergeState,
      mergeStateStatus: 'HAS_HOOKS',
      viewerCanUpdateBranch: true,
    }
    renderWithClient(<TestComponent {...props} />)

    expect(screen.getByRole('button', {name: 'Update branch'})).toBeInTheDocument()
  })

  test('clean merge state does not show update branch button if viewer cannot update branch', async () => {
    const props: ConflictsSectionProps = {
      ...conflictSectionPullRequest,
      ...conflictsSectionCleanMergeState,
      mergeStateStatus: 'HAS_HOOKS',
      viewerCanUpdateBranch: false,
    }
    renderWithClient(<TestComponent {...props} />)

    expect(screen.queryByRole('button', {name: 'Update branch'})).not.toBeInTheDocument()
  })
})

describe('pending state', () => {
  test('when mergeStateStatus is UNKNOWN and viewer cannot update branch, renders pending merge state', async () => {
    const props: ConflictsSectionProps = {
      ...conflictSectionPullRequest,
      ...conflictsSectionPendingMergeState,
      viewerCanUpdateBranch: false,
    }
    renderWithClient(<TestComponent {...props} />)

    expect(screen.getByText("Hang in there while we check the branch's status.")).toBeInTheDocument()
    expect(screen.getByText('Checking for the ability to merge automatically...')).toBeInTheDocument()
    expect(screen.queryByText('Update branch')).not.toBeInTheDocument()
  })

  test('when mergeStateStatus is UNKNOWN and viewer can update branch, renders pending merge state with update branch button', async () => {
    const props: ConflictsSectionProps = {
      ...conflictSectionPullRequest,
      ...conflictsSectionPendingMergeState,
      viewerCanUpdateBranch: true,
    }
    renderWithClient(<TestComponent {...props} />)

    expect(screen.getByText("Hang in there while we check the branch's status.")).toBeInTheDocument()
    expect(screen.getByText('Checking for the ability to merge automatically...')).toBeInTheDocument()
    expect(screen.getByText('Update branch')).toBeInTheDocument()
    expect(screen.getByLabelText('Update branch options')).toBeInTheDocument()
  })
})

describe('has merge conflicts', () => {
  test('when mergeStateStatus is DIRTY, renders standard conflicts merge state', async () => {
    const props: ConflictsSectionProps = {
      ...conflictSectionPullRequest,
      ...conflictsSectionStandardConflictsMergeState,
    }
    renderWithClient(<TestComponent {...props} />)

    expect(screen.getByText('web editor')).toBeInTheDocument()
    expect(screen.getByText('This branch has conflicts that must be resolved')).toBeInTheDocument()
    expect(screen.getByText('conflict.md')).toBeInTheDocument()
    expect(screen.getByText('conflict2.md')).toBeInTheDocument()
    expect(screen.getByText('Resolve conflicts')).toBeInTheDocument()
  })

  test('when mergeStateStatus is DIRTY, renders complex conflicts merge state', async () => {
    const props: ConflictsSectionProps = {
      ...conflictSectionPullRequest,
      ...conflictsSectionComplexConflictsMergeState,
    }
    renderWithClient(<TestComponent {...props} />)

    expect(
      screen.getByText(
        'Resolve conflicts then push again. These conflicts are too complex to resolve in the web editor. Actions workflows will not trigger on activity from this pull request while it has merge conflicts.',
      ),
    ).toBeInTheDocument()
    expect(screen.getByText('This branch has conflicts that must be resolved')).toBeInTheDocument()
    expect(screen.getByText('conflict.md')).toBeInTheDocument()
    expect(screen.getByText('conflict2.md')).toBeInTheDocument()
    expect(screen.queryByText('Resolve conflicts')).not.toBeInTheDocument()
  })
})

describe('out of date state', () => {
  test('when mergeStateStatus is BEHIND and viewer can update branch, renders branch out of date merge state with update button', async () => {
    const props: ConflictsSectionProps = {
      ...conflictSectionPullRequest,
      mergeStateStatus: 'BEHIND',
      conflictsCondition: {
        conflicts: [],
        isConflictResolvableInWeb: false,
        result: 'PASSED',
        message: null,
      },
      viewerCanUpdateBranch: true,
    }

    const {user} = renderWithClient(<TestComponent {...props} />)

    expect(
      screen.getByText(
        'Merge the latest changes from main into this branch. This merge commit will be associated with monalisa.',
      ),
    ).toBeInTheDocument()
    expect(screen.getByText('This branch is out-of-date with the base branch')).toBeInTheDocument()
    expect(screen.getByText('Update branch')).toBeInTheDocument()
    const toggleModeButton = screen.getByLabelText('Update branch options')
    await user.click(toggleModeButton)
    const rebaseButton = screen.getByText('Update with rebase')
    await user.click(rebaseButton)
    expect(screen.getByText('Rebase branch')).toBeInTheDocument()
  })

  test('when mergeStateStatus is BEHIND and viewer cannot update branch, renders branch out of date merge state without update button', async () => {
    const props: ConflictsSectionProps = {
      ...conflictSectionPullRequest,
      mergeStateStatus: 'BEHIND',
      conflictsCondition: {
        conflicts: [],
        isConflictResolvableInWeb: false,
        result: 'PASSED',
        message: null,
      },
      viewerCanUpdateBranch: false,
    }

    renderWithClient(<TestComponent {...props} />)

    expect(
      screen.getByText(
        'Merge the latest changes from main into this branch. This merge commit will be associated with monalisa.',
      ),
    ).toBeInTheDocument()
    expect(screen.getByText('This branch is out-of-date with the base branch')).toBeInTheDocument()
    expect(screen.queryByText('Update branch')).not.toBeInTheDocument()
  })

  test('when mergeStateStatus is BLOCKED, and user can update branch, renders branch out of date merge state', async () => {
    const props: ConflictsSectionProps = {
      ...conflictSectionPullRequest,
      mergeStateStatus: 'BLOCKED',
      conflictsCondition: {
        conflicts: [],
        isConflictResolvableInWeb: false,
        result: 'PASSED',
        message: null,
      },
      viewerCanUpdateBranch: true,
    }

    const {user} = renderWithClient(<TestComponent {...props} />)

    expect(
      screen.getByText(
        'Merge the latest changes from main into this branch. This merge commit will be associated with monalisa.',
      ),
    ).toBeInTheDocument()
    expect(screen.getByText('This branch is out-of-date with the base branch')).toBeInTheDocument()
    expect(screen.getByText('Update branch')).toBeInTheDocument()
    const toggleModeButton = screen.getByLabelText('Update branch options')
    await user.click(toggleModeButton)
    const rebaseButton = screen.getByText('Update with rebase')
    await user.click(rebaseButton)
    expect(screen.getByText('Rebase branch')).toBeInTheDocument()
  })

  test('when mergeStateStatus is BLOCKED and user cannot update the branch, renders nothing', async () => {
    const props: ConflictsSectionProps = {
      ...conflictSectionPullRequest,
      mergeStateStatus: 'BLOCKED',
      conflictsCondition: {
        conflicts: [],
        isConflictResolvableInWeb: false,
        result: 'PASSED',
        message: null,
      },
      viewerCanUpdateBranch: false,
    }

    const {container} = renderWithClient(<TestComponent {...props} />)

    expect(container).toBeEmptyDOMElement()
  })
})

describe('updating the branch', () => {
  test('sends analytics events for updating branch', async () => {
    const props: ConflictsSectionProps = {
      ...conflictSectionPullRequest,
      mergeStateStatus: 'BEHIND',
      conflictsCondition: {
        conflicts: [],
        isConflictResolvableInWeb: false,
        result: 'PASSED',
        message: null,
      },
      viewerCanUpdateBranch: true,
    }
    const {user} = renderWithClient(<TestComponent {...props} />)

    const toggleModeButton = screen.getByRole('button', {name: 'Update branch options'})
    await user.click(toggleModeButton)
    const rebaseMenuItem = screen.getByText('Update with rebase')
    await user.click(rebaseMenuItem)
    await user.click(toggleModeButton)
    const mergeCommitMenuItem = screen.getByText('Update with merge commit')
    await user.click(mergeCommitMenuItem)
    const updateBranchButton = screen.getByRole('button', {name: 'Update branch'})
    await user.click(updateBranchButton)

    expectAnalyticsEvents(
      {
        type: 'conflicts_section.select_rebase_method',
        target: 'MERGEBOX_CONFLICTS_SECTION_MERGE_METHOD_MENU_ITEM',
      },
      {
        type: 'conflicts_section.select_merge_commit_method',
        target: 'MERGEBOX_CONFLICTS_SECTION_MERGE_METHOD_MENU_ITEM',
      },
      {type: 'conflicts_section.update_branch', target: 'MERGEBOX_CONFLICTS_SECTION_UPDATE_BRANCH_BUTTON'},
    )
  })

  test('stays in pending state while branch is being updated', async () => {
    const props: ConflictsSectionProps = {
      ...conflictSectionPullRequest,
      mergeStateStatus: 'BEHIND',
      conflictsCondition: {
        conflicts: [],
        isConflictResolvableInWeb: false,
        result: 'PASSED',
        message: null,
      },
      viewerCanUpdateBranch: true,
    }
    const {user} = renderWithClient(<TestComponent {...props} />)

    const updateBranchButton = screen.getByRole('button', {name: 'Update branch'})
    await user.click(updateBranchButton)
    expect(screen.getByText('Updating branch...')).toBeInTheDocument()
  })
})

describe('has no merge conflicts', () => {
  test('when the user can push to the base branch, we render a message indicating that the user can merge the pull request', async () => {
    const props: ConflictsSectionProps = {
      ...conflictSectionPullRequest,
      ...conflictsSectionCleanMergeState,
      canUserPushToBase: true,
    }
    renderWithClient(<TestComponent {...props} />)

    expect(screen.getByText('Merging can be performed automatically.')).toBeInTheDocument()
  })
})

jest.mock('@github-ui/fetch-utils')
const fetchPollMock = jest.mocked(fetchPoll)
describe('ConflictsSection - Interactions', () => {
  const updatePullRequestBranchRoute = `${BASE_PAGE_DATA_URL}/page_data/${PageData.updatePullRequestBranch}`
  const orchestrationUrl = 'https://github.com/orchestration/1234'

  test('on success, calls the onSuccess callback and refetches the merge box query', async () => {
    const props: ConflictsSectionProps = {
      ...conflictSectionPullRequest,
      mergeStateStatus: 'BEHIND',
      conflictsCondition: {
        conflicts: [],
        isConflictResolvableInWeb: false,
        result: 'PASSED',
        message: null,
      },
      viewerCanUpdateBranch: true,
    }
    const {user} = renderWithClient(<TestComponent {...props} />)

    // Mock the update branch request
    mockFetch.mockRouteOnce(
      updatePullRequestBranchRoute,
      {orchestration: {url: orchestrationUrl}},
      {
        ok: true,
        status: 200,
      },
    )

    // Mock the orchestration polling
    fetchPollMock.mockReturnValue(
      Promise.resolve({
        ok: true,
        status: 200,
        json: async () => {
          return {orchestration: {}}
        },
      } as Response),
    )

    const updateBranchButton = screen.getByRole('button', {name: 'Update branch'})
    user.click(updateBranchButton)

    const updateInProgress = await screen.findByText('Updating branch...')
    expect(updateInProgress).toBeInTheDocument()
    const outerUpdateBranchButtonElement = screen
      .getAllByRole('button')
      .find(element => element.innerHTML.includes('Updating branch...'))
    expect(outerUpdateBranchButtonElement).toHaveAttribute('aria-disabled', 'true')

    expect(await screen.findByText('Update branch')).toBeInTheDocument()
  })

  test('on error due to orchestration failure, calls the onError callback and does not refetch the merge box query', async () => {
    const props: ConflictsSectionProps = {
      ...conflictSectionPullRequest,
      mergeStateStatus: 'BEHIND',
      conflictsCondition: {
        conflicts: [],
        isConflictResolvableInWeb: false,
        result: 'PASSED',
        message: null,
      },
      viewerCanUpdateBranch: true,
    }
    const {user} = renderWithClient(<TestComponent {...props} />)

    // Mock the update branch request
    mockFetch.mockRouteOnce(
      updatePullRequestBranchRoute,
      {orchestration: {url: orchestrationUrl}},
      {
        ok: true,
        status: 200,
      },
    )

    const errorMessage = 'Could not update branch.'
    // Mock the orchestration polling
    fetchPollMock.mockReturnValue(
      Promise.resolve({
        ok: true,
        status: 200,
        json: async () => {
          return {orchestration: {error_message: errorMessage}}
        },
      } as Response),
    )

    const updateBranchButton = screen.getByRole('button', {name: 'Update branch'})
    user.click(updateBranchButton)

    const updateInProgress = await screen.findByText('Updating branch...')
    expect(updateInProgress).toBeInTheDocument()
    const outerUpdateBranchButtonElement = screen
      .getAllByRole('button')
      .find(element => element.innerHTML.includes('Updating branch...'))
    expect(outerUpdateBranchButtonElement).toHaveAttribute('aria-disabled', 'true')

    expect(await screen.findByText(errorMessage)).toBeInTheDocument()
  })

  test('on error due to API failure, calls the onError callback and does not refetch the merge box query', async () => {
    const props: ConflictsSectionProps = {
      ...conflictSectionPullRequest,
      mergeStateStatus: 'BEHIND',
      conflictsCondition: {
        conflicts: [],
        isConflictResolvableInWeb: false,
        result: 'PASSED',
        message: null,
      },
      viewerCanUpdateBranch: true,
    }
    const {user} = renderWithClient(<TestComponent {...props} />)

    const errorMessage = 'Update branch already in progress.'
    // Mock the update branch request
    mockFetch.mockRouteOnce(
      updatePullRequestBranchRoute,
      {error: errorMessage},
      {
        ok: false,
        status: 422,
      },
    )

    const updateBranchButton = screen.getByRole('button', {name: 'Update branch'})
    user.click(updateBranchButton)

    const updateInProgress = await screen.findByText('Updating branch...')
    expect(updateInProgress).toBeInTheDocument()
    const outerUpdateBranchButtonElement = screen
      .getAllByRole('button')
      .find(element => element.innerHTML.includes('Updating branch...'))
    expect(outerUpdateBranchButtonElement).toHaveAttribute('aria-disabled', 'true')

    expect(await screen.findByText(errorMessage)).toBeInTheDocument()
  })
})
