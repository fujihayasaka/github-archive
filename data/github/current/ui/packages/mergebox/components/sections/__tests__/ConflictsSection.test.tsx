import {expectAnalyticsEvents} from '@github-ui/analytics-test-utils'
import {screen} from '@testing-library/react'

import {ConflictsSection as TestComponent} from '../ConflictsSection'
import type {ConflictsSectionProps} from '../ConflictsSection'
import {BASE_PAGE_DATA_URL, renderWithClient} from '@github-ui/pull-request-page-data-tooling/render-with-query-client'
import {PageData} from '@github-ui/pull-request-page-data-tooling/page-data'
import {mockFetch} from '@github-ui/mock-fetch'
import {fetchPoll} from '@github-ui/fetch-utils'
import {
  conflictsSectionAdminDisabled,
  conflictsSectionBehindMergeState,
  conflictsSectionBlockedMergeState,
  conflictsSectionCleanMergeState,
  conflictsSectionComplexConflictsMergeState,
  conflictsSectionHasRebaseConflicts,
  conflictsSectionHeadBranchProtected,
  conflictsSectionInsufficientAccessToResolve,
  conflictsSectionPendingMergeState,
  conflictsSectionStandardConflictsMergeState,
} from '../../../test-utils/mocks/conflicts-condition-mock'
import {
  assertButtonEnabled,
  assertButtonInLoadingState,
  assertWaitForButtonToBeEnabled,
  assertWaitForButtonToBeInLoadingState,
} from '../../../test-utils/loading-button-asserts'

const conflictSectionPullRequest = {
  baseRefName: 'main',
  headRefOid: 'abc123',
  id: 'pr-123',
  resourcePath: '/octocat/Hello-World/pull/123',
  viewerCanUpdateBranch: false,
  viewerLogin: 'monalisa',
  canUserPushToBase: true,
  advisoryWorkspace: null,
  viewerUpdateMethods: null,
}

afterEach(() => {
  jest.clearAllMocks()
})

describe('CLEAN, UNSTABLE, and HAS_HOOKS merge state status map to clean state of the conflicts section', () => {
  test('when mergeStateStatus is CLEAN, renders clean merge state', async () => {
    const props: ConflictsSectionProps = {
      ...conflictSectionPullRequest,
      ...conflictsSectionCleanMergeState,
      conflictsState: 'NO_CONFLICTS',
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
      conflictsState: 'NO_CONFLICTS',
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
      conflictsState: 'NO_CONFLICTS',
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
      conflictsState: 'NO_CONFLICTS',
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
      conflictsState: 'NO_CONFLICTS',
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
      conflictsState: 'PENDING',
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
      conflictsState: 'PENDING',
    }
    renderWithClient(<TestComponent {...props} />)

    expect(screen.getByText("Hang in there while we check the branch's status.")).toBeInTheDocument()
    expect(screen.getByText('Checking for the ability to merge automatically...')).toBeInTheDocument()
    expect(screen.getByText('Update branch')).toBeInTheDocument()
    expect(screen.getByLabelText('Update branch options')).toBeInTheDocument()
  })
})

describe('has merge conflicts', () => {
  test('when the conflicts condition has failed and the conflict files length is 0, it is a rebase conflict', () => {
    const props: ConflictsSectionProps = {
      ...conflictSectionPullRequest,
      ...conflictsSectionHasRebaseConflicts,
      conflictsState: 'HAS_REBASE_CONFLICTS',
    }
    renderWithClient(<TestComponent {...props} />)

    const title = screen.getByText('This branch cannot be rebased due to conflicts')
    expect(title).toBeInTheDocument()

    const linkButton = screen.queryByRole('link', {name: 'Resolve conflicts'})
    expect(linkButton).not.toBeInTheDocument()
  })

  test('when mergeStateStatus is DIRTY and the user can use the web editor to resolve the conflicts, renders the resolve conflicts button and the list of files', async () => {
    const props: ConflictsSectionProps = {
      ...conflictSectionPullRequest,
      ...conflictsSectionStandardConflictsMergeState,
      conflictsState: 'HAS_CONFLICTS',
    }
    renderWithClient(<TestComponent {...props} />)

    const title = screen.getByText('This branch has conflicts that must be resolved')
    expect(title).toBeInTheDocument()

    const partialSubtitle = screen.getByText('web editor')
    expect(partialSubtitle).toBeInTheDocument()

    const linkButton = screen.getByRole('link', {name: 'Resolve conflicts'})
    expect(linkButton).toBeInTheDocument()

    // list files
    expect(screen.getByText('conflict.md')).toBeInTheDocument()
    expect(screen.getByText('conflict2.md')).toBeInTheDocument()
  })

  test('when mergeStateStatus is DIRTY and the user cannot resolve the conflicts via the web editor because they cannot push to the head, renders an inactive button with a tooltip and does not list the files', async () => {
    const props: ConflictsSectionProps = {
      ...conflictSectionPullRequest,
      ...conflictsSectionInsufficientAccessToResolve,
      conflictsState: 'HAS_CONFLICTS',
    }
    const {user} = renderWithClient(<TestComponent {...props} />)

    const title = screen.getByText('This branch has conflicts that must be resolved')
    expect(title).toBeInTheDocument()

    // no subtitle if user cannot push
    expect(screen.queryByText('web editor')).not.toBeInTheDocument()
    expect(screen.queryByText('Use the command line to resolve conflicts before continuing.')).not.toBeInTheDocument()

    // resolve conflicts button is inactive
    const button = screen.getByRole('button', {name: 'Resolve conflicts'})
    expect(button).toHaveAttribute('data-inactive', 'true')
    await user.hover(button)
    const tooltip = screen.getByText('You do not have permission to push to the head branch.')
    expect(tooltip).toHaveAttribute('role', 'tooltip')
    expect(tooltip).toBeInTheDocument()

    // no files listed
    expect(screen.queryByText('conflict.md')).not.toBeInTheDocument()
    expect(screen.queryByText('conflict2.md')).not.toBeInTheDocument()
  })

  test('when mergeStateStatus is DIRTY and the conflicts are too complex to resolve in the web, renders an inactive button and does list the files', async () => {
    const props: ConflictsSectionProps = {
      ...conflictSectionPullRequest,
      ...conflictsSectionComplexConflictsMergeState,
      conflictsState: 'HAS_CONFLICTS',
    }
    renderWithClient(<TestComponent {...props} />)

    const title = screen.getByText('This branch has conflicts that must be resolved')
    expect(title).toBeInTheDocument()

    const subtitle = screen.getByText('Use the command line to resolve conflicts before continuing.')
    expect(subtitle).toBeInTheDocument()

    const linkButton = screen.queryByRole('link', {name: 'Resolve conflicts'})
    expect(linkButton).not.toBeInTheDocument()

    // list files
    expect(screen.getByText('conflict.md')).toBeInTheDocument()
    expect(screen.getByText('conflict2.md')).toBeInTheDocument()
  })

  test('when mergeStateStatus is DIRTY and the user cannot push because the head branch is protected, renders an inactive button and lists the files', async () => {
    const props: ConflictsSectionProps = {
      ...conflictSectionPullRequest,
      ...conflictsSectionHeadBranchProtected,
      conflictsState: 'HAS_CONFLICTS',
    }
    const {user} = renderWithClient(<TestComponent {...props} />)

    const title = screen.getByText('This branch has conflicts that must be resolved')
    expect(title).toBeInTheDocument()

    const subtitle = screen.getByText('Use the command line to resolve conflicts before continuing.')
    expect(subtitle).toBeInTheDocument()

    // resolve conflicts button is inactive
    const button = screen.getByRole('button', {name: 'Resolve conflicts'})
    expect(button).toHaveAttribute('data-inactive', 'true')
    await user.hover(button)
    const tooltip = screen.getByText('main is a protected branch.')
    expect(tooltip).toHaveAttribute('role', 'tooltip')
    expect(tooltip).toBeInTheDocument()

    // list files
    expect(screen.getByText('conflict.md')).toBeInTheDocument()
    expect(screen.getByText('conflict2.md')).toBeInTheDocument()
  })

  test('when mergeStateStatus is DIRTY and editor is disabled, renders an inactive button and lists the files', async () => {
    const props: ConflictsSectionProps = {
      ...conflictSectionPullRequest,
      ...conflictsSectionAdminDisabled,
      conflictsState: 'HAS_CONFLICTS',
    }
    const {user} = renderWithClient(<TestComponent {...props} />)

    const title = screen.getByText('This branch has conflicts that must be resolved')
    expect(title).toBeInTheDocument()

    const subtitle = screen.getByText('Use the command line to resolve conflicts before continuing.')
    expect(subtitle).toBeInTheDocument()

    // resolve conflicts button is inactive
    const button = screen.getByRole('button', {name: 'Resolve conflicts'})
    expect(button).toHaveAttribute('data-inactive', 'true')
    await user.hover(button)
    const tooltip = screen.getByText(
      'Web conflict resolution across forked repositories has been disabled by your site administrator.',
    )
    expect(tooltip).toHaveAttribute('role', 'tooltip')
    expect(tooltip).toBeInTheDocument()

    // list files
    expect(screen.getByText('conflict.md')).toBeInTheDocument()
    expect(screen.getByText('conflict2.md')).toBeInTheDocument()
  })
})

describe('out of date state', () => {
  test('when mergeStateStatus is BEHIND and viewer can update branch, renders branch out of date merge state with update button', async () => {
    const props: ConflictsSectionProps = {
      ...conflictSectionPullRequest,
      ...conflictsSectionBehindMergeState,
      viewerCanUpdateBranch: true,
      conflictsState: 'OUT_OF_DATE',
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
      ...conflictsSectionBehindMergeState,
      viewerCanUpdateBranch: false,
      conflictsState: 'OUT_OF_DATE',
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
      ...conflictsSectionBlockedMergeState,
      viewerCanUpdateBranch: true,
      conflictsState: 'OUT_OF_DATE',
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

  test('when rebase is not allowed, only shows merge option', async () => {
    const props: ConflictsSectionProps = {
      ...conflictSectionPullRequest,
      ...conflictsSectionCleanMergeState,
      mergeStateStatus: 'BEHIND',
      viewerCanUpdateBranch: true,
      conflictsState: 'OUT_OF_DATE',
      viewerUpdateMethods: [
        {
          allowableStatus: 'ALLOWED',
          name: 'MERGE',
          failureReason: null,
          isDefault: true,
        },
        {
          allowableStatus: 'BLOCKED',
          name: 'REBASE',
          failureReason: null,
          isDefault: false,
        },
      ],
    }

    renderWithClient(<TestComponent {...props} />)

    expect(
      screen.getByText(
        'Merge the latest changes from main into this branch. This merge commit will be associated with monalisa.',
      ),
    ).toBeInTheDocument()
    expect(screen.getByText('This branch is out-of-date with the base branch')).toBeInTheDocument()
    expect(screen.getByText('Update branch')).toBeInTheDocument()
    expect(screen.queryByText('Update with rebase')).not.toBeInTheDocument()
  })

  test('when rebase is not available, shows inactive text for rebase', async () => {
    const props: ConflictsSectionProps = {
      ...conflictSectionPullRequest,
      ...conflictsSectionCleanMergeState,
      mergeStateStatus: 'BEHIND',
      viewerCanUpdateBranch: true,
      conflictsState: 'OUT_OF_DATE',
      viewerUpdateMethods: [
        {
          allowableStatus: 'ALLOWED',
          name: 'MERGE',
          failureReason: null,
          isDefault: true,
        },
        {
          allowableStatus: 'UNAVAILABLE',
          name: 'REBASE',
          failureReason: 'There was a problem generating the rebase commit.',
          isDefault: false,
        },
      ],
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
    expect(screen.getByText('Update with rebase')).toBeInTheDocument()
    expect(screen.getByText('There was a problem generating the rebase commit.')).toBeInTheDocument()
  })
})

describe('updating the branch', () => {
  test('sends analytics events for updating branch', async () => {
    const props: ConflictsSectionProps = {
      ...conflictSectionPullRequest,
      ...conflictsSectionBehindMergeState,
      viewerCanUpdateBranch: true,
      conflictsState: 'OUT_OF_DATE',
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
      ...conflictsSectionBehindMergeState,
      viewerCanUpdateBranch: true,
      conflictsState: 'OUT_OF_DATE',
    }
    const {user} = renderWithClient(<TestComponent {...props} />)

    const updateBranchButton = screen.getByRole('button', {name: 'Update branch'})
    assertButtonEnabled(updateBranchButton)

    await user.click(updateBranchButton)

    assertButtonInLoadingState(updateBranchButton, 'Updating branch')
    expect.hasAssertions()
  })
})

describe('has no merge conflicts', () => {
  test('when the user can push to the base branch, we render a message indicating that the user can merge the pull request', async () => {
    const props: ConflictsSectionProps = {
      ...conflictSectionPullRequest,
      ...conflictsSectionCleanMergeState,
      canUserPushToBase: true,
      conflictsState: 'NO_CONFLICTS',
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
      ...conflictsSectionBehindMergeState,
      viewerCanUpdateBranch: true,
      conflictsState: 'OUT_OF_DATE',
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
    assertButtonEnabled(updateBranchButton)

    user.click(updateBranchButton)

    // pre-success state (pending)
    await assertWaitForButtonToBeInLoadingState(updateBranchButton, 'Updating branch')

    // post success state (no longer pending)
    await assertWaitForButtonToBeEnabled(updateBranchButton)

    expect.hasAssertions()
  })

  test('on error due to orchestration failure, calls the onError callback and does not refetch the merge box query', async () => {
    const props: ConflictsSectionProps = {
      ...conflictSectionPullRequest,
      ...conflictsSectionBehindMergeState,
      viewerCanUpdateBranch: true,
      conflictsState: 'OUT_OF_DATE',
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
    assertButtonEnabled(updateBranchButton)

    user.click(updateBranchButton)

    await assertWaitForButtonToBeInLoadingState(updateBranchButton, 'Updating branch')

    expect(await screen.findByText(errorMessage)).toBeInTheDocument()

    assertButtonEnabled(updateBranchButton)
  })

  test('on error due to API failure, calls the onError callback and does not refetch the merge box query', async () => {
    const props: ConflictsSectionProps = {
      ...conflictSectionPullRequest,
      ...conflictsSectionBehindMergeState,
      viewerCanUpdateBranch: true,
      conflictsState: 'OUT_OF_DATE',
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
    assertButtonEnabled(updateBranchButton)

    user.click(updateBranchButton)

    await assertWaitForButtonToBeInLoadingState(updateBranchButton, 'Updating branch')

    expect(await screen.findByText(errorMessage)).toBeInTheDocument()
    assertButtonEnabled(updateBranchButton)
  })

  test('for advisory workspace Prs, shows the proper link and heading', async () => {
    const props: ConflictsSectionProps = {
      ...conflictSectionPullRequest,
      ...conflictsSectionCleanMergeState,
      advisoryWorkspace: {
        advisoryWorkspacePath: 'smile/monalisa/security/advisory/123',
        advisoryWorkspaceId: '123',
      },
      conflictsState: 'HAS_ADVISORY_WORKSPACE',
    }
    renderWithClient(<TestComponent {...props} />)
    const link = screen.queryByRole('link', {name: '123'})
    expect(link).toBeInTheDocument()
    expect(link).toHaveAttribute('href', 'smile/monalisa/security/advisory/123')
    expect(screen.getByText('No conflicts with base branch')).toBeInTheDocument()
  })
})
