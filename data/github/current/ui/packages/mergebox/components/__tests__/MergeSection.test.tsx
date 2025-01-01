import {expectAnalyticsEvents} from '@github-ui/analytics-test-utils'
import {screen, waitFor, within} from '@testing-library/react'

import type {MergeSectionProps} from '../sections/merge-section/MergeSection'
import {MergeAction, MergeMethod, type PullRequestMergeRequirementsState} from '../../types'
import type {PullRequestMergeRequirementsPayload} from '../../page-data/payloads/merge-box'
import {PageData} from '@github-ui/pull-request-page-data-tooling/page-data'
import {BASE_PAGE_DATA_URL, renderWithClient} from '@github-ui/pull-request-page-data-tooling/render-with-query-client'
// eslint-disable-next-line no-restricted-imports
import {expectMockFetchCalledWith, mockFetch} from '@github-ui/mock-fetch'
import {MergeMethodContextProvider} from '../../contexts/MergeMethodContext'
import {MergeSection as MergeSectionInner} from '../sections/merge-section/MergeSection'
import {
  defaultMergeRequirements,
  mockMergeRequirementCondition,
  mockViewerMergeActions,
} from '../../test-utils/mocks/json-api-response.mock'
import {Status} from '../../helpers/mergeability-status'
import {defaultMergeInstructionsApiResponse} from '../../test-utils/mocks/merge-instructions-mock'
import {
  assertButtonEnabled,
  assertButtonInLoadingState,
  assertWaitForButtonToBeEnabled,
} from '../../test-utils/loading-button-asserts'
import {FeatureFlagProvider} from '@github-ui/react-core/feature-flag-provider'
import type {EnabledFeatures} from '@github-ui/react-core/use-feature-flag'

const MergeSection = ({
  defaultMergeMethod = MergeMethod.MERGE,
  enabledFeatures,
  ...rest
}: MergeSectionProps & {defaultMergeMethod?: MergeMethod; enabledFeatures?: EnabledFeatures}) => {
  return (
    <FeatureFlagProvider features={enabledFeatures ?? {}}>
      <MergeMethodContextProvider defaultMergeMethod={defaultMergeMethod}>
        <div id="js-global-screen-reader-notice" />
        <MergeSectionInner {...rest} />
      </MergeMethodContextProvider>
    </FeatureFlagProvider>
  )
}

const disableAutoMergePageDataRoute = `${BASE_PAGE_DATA_URL}/page_data/${PageData.disableAutoMerge}`
const enableAutoMergePageDataRoute = `${BASE_PAGE_DATA_URL}/page_data/${PageData.enableAutoMerge}`

const defaultCleanConflictsCondition: PullRequestMergeRequirementsPayload['conditions'][number] =
  mockMergeRequirementCondition.PULL_REQUEST_MERGE_CONFLICT_STATE({result: 'PASSED'})

const pullRequestWithDefaultMergeActionsAndMethods: MergeSectionProps = {
  ...defaultMergeRequirements,
  advisoryWorkspace: null,
  autoMergeRequest: null,
  baseRefName: 'main',
  canUserPushToBase: true,
  defaultCommitAuthorEmail: defaultMergeRequirements.defaultCommitAuthorEmail,
  conflictsCondition: defaultCleanConflictsCondition,
  headRepository: {ownerLogin: 'monalisa', name: 'smile'},
  helpUrl: 'http://github.localhost.com/help',
  id: 'pullRequest:1',
  isCrossRepo: false,
  isDraft: false,
  isInMergeQueue: false,
  mergeBoxRollupStatus: 'NEUTRAL',
  mergeQueue: null,
  mergeRequirementsState: defaultMergeRequirements.state,
  mergeStateStatus: 'CLEAN',
  numberOfCommits: 2,
  setShouldFocusPrimaryMergeButton: jest.fn(),
  shouldFocusPrimaryMergeButton: false,
  status: Status.Unknown,
  viewerCanAddAndRemoveFromMergeQueue: true,
  viewerCanAddToMergeQueueSolo: false,
  viewerCanAdminBypassMergeRequirements: false,
  viewerCanDisableAutoMerge: false,
  viewerCanEnableAutoMerge: false,
  viewerMergeActions: mockViewerMergeActions['defaultDirectMerge'],
  possibleCommitAuthorEmails: [],
}

afterEach(() => {
  jest.clearAllMocks()
})

describe('Merge section', () => {
  describe('disabled', () => {
    test('it renders an aria-disabled merge button when either merge action is not allowable (if PR is draft, closed or user does not have permissions to merge)', async () => {
      const {user} = renderWithClient(<MergeSection {...pullRequestWithDefaultMergeActionsAndMethods} />)

      const primaryButton = screen.getByRole('button', {name: 'Merge pull request'})
      expect(primaryButton).toHaveAttribute('aria-disabled', 'true')

      await user.click(primaryButton)

      const tooltip = screen.getByText('Merging is blocked due to failing merge requirements')
      expect(tooltip).toHaveAttribute('role', 'tooltip')
      expect(tooltip).toBeInTheDocument()
    })

    test('button is disabled when the user does not have write access to the repo', async () => {
      const pullRequest: MergeSectionProps = {
        ...pullRequestWithDefaultMergeActionsAndMethods,
        mergeRequirementsState: 'UNKNOWN',
        canUserPushToBase: false,
      }
      const {user} = renderWithClient(<MergeSection defaultMergeMethod={MergeMethod.MERGE} {...pullRequest} />)

      const mergeButton = screen.getByRole('button', {name: 'Merge pull request'})
      expect(mergeButton).toHaveAttribute('aria-disabled', 'true')

      const text = await screen.findByText((_, element) => {
        return element?.textContent === 'Only those with write access to this repository can merge pull requests.'
      })
      expect(text).toBeInTheDocument()

      await user.hover(mergeButton)
      const tooltip = screen.getByText('Merging is blocked due to failing merge requirements')
      expect(tooltip).toHaveAttribute('role', 'tooltip')
      expect(tooltip).toBeInTheDocument()
    })

    test('tooltip shows Checking for the ability to merge automatically when the merge requirements state is unknown', async () => {
      const pullRequest: MergeSectionProps = {
        ...pullRequestWithDefaultMergeActionsAndMethods,
        mergeStateStatus: 'UNKNOWN',
        mergeRequirementsState: 'UNKNOWN',
        viewerMergeActions: mockViewerMergeActions['defaultMergeQueue'],
      }
      const {user} = renderWithClient(<MergeSection {...pullRequest} />)

      const primaryButton = screen.getByRole('button', {name: 'Merge when ready'})
      expect(primaryButton).toHaveAttribute('aria-disabled', 'true')

      await user.click(primaryButton)

      const tooltip = screen.getByText('Checking for the ability to merge automatically')
      expect(tooltip).toHaveAttribute('role', 'tooltip')
      expect(tooltip).toBeInTheDocument()
    })
  })

  describe('auto merge', () => {
    test('shows "auto-merge" when the repo has auto-merge enabled and viewer can enable auto-merge', async () => {
      const pullRequest: MergeSectionProps = {
        ...pullRequestWithDefaultMergeActionsAndMethods,
        viewerCanEnableAutoMerge: true,
      }

      renderWithClient(<MergeSection {...pullRequest} />)

      const button = screen.getByRole('button', {name: 'Enable auto-merge'})
      expect(button).toBeInTheDocument()
    })

    test('"Enable auto-merge" button is not visible if pr is mergeable', async () => {
      const pullRequest: MergeSectionProps = {
        ...pullRequestWithDefaultMergeActionsAndMethods,
        mergeRequirementsState: 'MERGEABLE_IF_STATUSES_PASS',
        viewerMergeActions: mockViewerMergeActions['directMergeWithBypassAllowed'],
        viewerCanEnableAutoMerge: true,
        status: Status.Mergeable,
      }

      renderWithClient(<MergeSection {...pullRequest} />)

      const button = screen.queryByRole('button', {name: 'Enable auto-merge'})
      expect(button).not.toBeInTheDocument()

      const mergePullRequestButton = screen.getByRole('button', {name: 'Merge pull request'})
      expect(mergePullRequestButton).toBeInTheDocument()
    })

    test('"Enable auto-merge" button is visible if pr is not mergable and user can enable auto-merge', async () => {
      const pullRequest: MergeSectionProps = {
        ...pullRequestWithDefaultMergeActionsAndMethods,
        mergeRequirementsState: 'MERGEABLE_IF_STATUSES_PASS',
        viewerMergeActions: mockViewerMergeActions['directMergeWithBypassAllowed'],
        viewerCanEnableAutoMerge: true,
        status: Status.ChecksFailing,
      }

      renderWithClient(<MergeSection {...pullRequest} />)

      const button = screen.queryByRole('button', {name: 'Enable auto-merge'})
      expect(button).toBeInTheDocument()
    })

    test('"Enable auto-merge" button is not visible if the user cannot enable auto-merge', async () => {
      const pullRequest: MergeSectionProps = {
        ...pullRequestWithDefaultMergeActionsAndMethods,
        viewerCanEnableAutoMerge: false,
      }

      renderWithClient(<MergeSection {...pullRequest} />)

      const button = screen.queryByRole('button', {name: 'Enable auto-merge'})
      expect(button).not.toBeInTheDocument()

      const mergePullRequestButton = screen.getByRole('button', {name: 'Merge pull request'})
      expect(mergePullRequestButton).toBeInTheDocument()
    })

    test('"Enable auto-merge" button click sends analytics event', async () => {
      const pullRequest: MergeSectionProps = {
        ...pullRequestWithDefaultMergeActionsAndMethods,
        viewerCanEnableAutoMerge: true,
      }
      const {user} = renderWithClient(<MergeSection {...pullRequest} />)

      const button = screen.getByRole('button', {name: 'Enable auto-merge'})
      await user.click(button)

      expectAnalyticsEvents({
        type: 'direct_merge_section.auto_merge_click',
        target: 'MERGEBOX_AUTO_MERGE_SECTION_MERGE_BUTTON',
      })
    })

    test('shows pending state when enabling auto-merge until the mutation is successful', async () => {
      const pullRequest: MergeSectionProps = {
        ...pullRequestWithDefaultMergeActionsAndMethods,
        viewerCanEnableAutoMerge: true,
      }
      const {user} = renderWithClient(<MergeSection {...pullRequest} />)

      const enableAutoMergeButton = screen.getByRole('button', {name: 'Enable auto-merge'})
      await user.click(enableAutoMergeButton)

      const confirmAutoMergeButton = screen.getByRole('button', {name: 'Confirm auto-merge'})

      assertButtonEnabled(confirmAutoMergeButton)

      await user.click(confirmAutoMergeButton)

      assertButtonInLoadingState(confirmAutoMergeButton, 'Confirming...')
      expect.hasAssertions()
    })

    test('when enabling auto-merge, we always pass in mergeMethod, commitMessage, commitTitle', async () => {
      const enableAutoMergeRoute = `${BASE_PAGE_DATA_URL}/page_data/${PageData.enableAutoMerge}`
      const pullRequest: MergeSectionProps = {
        ...pullRequestWithDefaultMergeActionsAndMethods,
        viewerCanEnableAutoMerge: true,
        commitMessageHeadline: 'PR title',
        commitMessageBody: 'PR body',
      }

      const {user} = renderWithClient(<MergeSection {...pullRequest} />)

      const enableAutoMergeButton = screen.getByRole('button', {name: 'Enable auto-merge'})
      await user.click(enableAutoMergeButton)

      const confirmAutoMergeButton = screen.getByRole('button', {name: 'Confirm auto-merge'})
      await user.click(confirmAutoMergeButton)

      await waitFor(() =>
        expectMockFetchCalledWith(enableAutoMergeRoute, {
          commitMessage: 'PR body',
          commitTitle: 'PR title',
          mergeMethod: 'MERGE',
        }),
      )
    })

    test('when enabling auto-merge, we always pass in mergeMethod, commitMessage, commitTitle, and authorEmail when user selects', async () => {
      const enableAutoMergeRoute = `${BASE_PAGE_DATA_URL}/page_data/${PageData.enableAutoMerge}`
      const pullRequest: MergeSectionProps = {
        ...pullRequestWithDefaultMergeActionsAndMethods,
        viewerCanEnableAutoMerge: true,
        commitMessageHeadline: 'PR title',
        commitMessageBody: 'PR body',
        defaultCommitAuthorEmail: 'test@github.com',
        possibleCommitAuthorEmails: ['mona@github.com', 'test@github.com'],
      }

      const {user} = renderWithClient(<MergeSection {...pullRequest} />)

      const enableAutoMergeButton = screen.getByRole('button', {name: 'Enable auto-merge'})
      await user.click(enableAutoMergeButton)

      const confirmAutoMergeButton = screen.getByRole('button', {name: 'Confirm auto-merge'})
      await user.click(confirmAutoMergeButton)

      await waitFor(() =>
        expectMockFetchCalledWith(enableAutoMergeRoute, {
          authorEmail: 'test@github.com',
          commitMessage: 'PR body',
          commitTitle: 'PR title',
          mergeMethod: 'MERGE',
        }),
      )
    })

    test('renders error message if enabling auto-merge fails', async () => {
      const errorMessage = 'Failed enabling auto-merge for pull request.'

      const pullRequest: MergeSectionProps = {
        ...pullRequestWithDefaultMergeActionsAndMethods,
        viewerCanEnableAutoMerge: true,
      }
      const {user} = renderWithClient(<MergeSection {...pullRequest} />)

      const enableAutoMergeButton = screen.getByRole('button', {name: 'Enable auto-merge'})
      await user.click(enableAutoMergeButton)

      const confirmAutoMergeButton = screen.getByRole('button', {name: 'Confirm auto-merge'})

      assertButtonEnabled(confirmAutoMergeButton)

      await user.click(confirmAutoMergeButton)

      assertButtonInLoadingState(confirmAutoMergeButton, 'Confirming...')

      mockFetch.resolvePendingRequest(enableAutoMergePageDataRoute, {error: errorMessage}, {status: 422, ok: false})

      expect(
        within(await screen.findByLabelText('Merge error warning banner')).getByText(errorMessage),
      ).toBeInTheDocument()
      assertButtonEnabled(confirmAutoMergeButton)
    })

    test('shows the "Disable auto-merge" button when auto-merge is active', async () => {
      const pullRequest: MergeSectionProps = {
        ...pullRequestWithDefaultMergeActionsAndMethods,
        autoMergeRequest: {
          mergeMethod: 'MERGE',
        },
        viewerCanDisableAutoMerge: true,
      }

      renderWithClient(<MergeSection {...pullRequest} />)

      const button = screen.getByRole('button', {name: 'Disable auto-merge'})
      expect(button).toBeInTheDocument()
    })

    test('the "Disable auto-merge" button is disabled when the user cannot disable auto-merge', async () => {
      const pullRequest: MergeSectionProps = {
        ...pullRequestWithDefaultMergeActionsAndMethods,
        autoMergeRequest: {
          mergeMethod: 'MERGE',
        },
        viewerCanDisableAutoMerge: false,
      }

      renderWithClient(<MergeSection {...pullRequest} />)

      const button = screen.getByRole('button', {name: 'Disable auto-merge'})
      expect(button).toBeDisabled()
    })

    test('shows pending state when disabling auto-merge until the mutation is successful', async () => {
      const pullRequest: MergeSectionProps = {
        ...pullRequestWithDefaultMergeActionsAndMethods,
        autoMergeRequest: {
          mergeMethod: 'MERGE',
        },
        viewerCanDisableAutoMerge: true,
      }
      const {user} = renderWithClient(<MergeSection {...pullRequest} />)

      const disableAutoMergeButton = screen.getByRole('button', {name: 'Disable auto-merge'})

      assertButtonEnabled(disableAutoMergeButton)

      await user.click(disableAutoMergeButton)

      assertButtonInLoadingState(disableAutoMergeButton, 'Disabling auto-merge')

      mockFetch.resolvePendingRequest(disableAutoMergePageDataRoute, {}, {status: 200, ok: true})

      await assertWaitForButtonToBeEnabled(disableAutoMergeButton)

      expect.hasAssertions()
    })

    test('renders error message if disabling auto-merge fails', async () => {
      const errorMessage = 'Failed to disable auto-merge for pull request.'

      const pullRequest: MergeSectionProps = {
        ...pullRequestWithDefaultMergeActionsAndMethods,
        autoMergeRequest: {
          mergeMethod: 'MERGE',
        },
        viewerCanDisableAutoMerge: true,
      }
      const {user} = renderWithClient(<MergeSection {...pullRequest} />)

      const disableAutoMergeButton = screen.getByRole('button', {name: 'Disable auto-merge'})

      assertButtonEnabled(disableAutoMergeButton)

      await user.click(disableAutoMergeButton)

      assertButtonInLoadingState(disableAutoMergeButton, 'Disabling auto-merge')

      mockFetch.resolvePendingRequest(disableAutoMergePageDataRoute, {error: errorMessage}, {status: 422, ok: false})

      await assertWaitForButtonToBeEnabled(disableAutoMergeButton)

      expect.hasAssertions()
    })

    test('sends analytics event when the cancel button is clicked', async () => {
      const pullRequest: MergeSectionProps = {
        ...pullRequestWithDefaultMergeActionsAndMethods,
        viewerCanEnableAutoMerge: true,
      }
      const {user} = renderWithClient(<MergeSection {...pullRequest} />)

      const enableAutoMergeButton = screen.getByRole('button', {name: 'Enable auto-merge'})

      await user.click(enableAutoMergeButton)

      const cancelButton = screen.getByRole('button', {name: 'Cancel'})
      await user.click(cancelButton)

      expectAnalyticsEvents(
        {
          type: 'direct_merge_section.auto_merge_click',
          target: 'MERGEBOX_AUTO_MERGE_SECTION_MERGE_BUTTON',
        },
        {
          type: 'direct_merge_section.cancel_auto_merge',
          target: 'MERGEBOX_AUTO_MERGE_CANCEL_CONFIRMATION_BUTTON',
        },
      )
    })

    test('sends analytics event when the "Disable auto-merge" button is clicked', async () => {
      const pullRequest: MergeSectionProps = {
        ...pullRequestWithDefaultMergeActionsAndMethods,
        autoMergeRequest: {
          mergeMethod: 'MERGE',
        },
        viewerCanDisableAutoMerge: true,
      }
      const {user} = renderWithClient(<MergeSection {...pullRequest} />)

      const disableAutoMergeButton = screen.getByRole('button', {name: 'Disable auto-merge'})

      await user.click(disableAutoMergeButton)

      expectAnalyticsEvents({
        type: 'auto_merge_section.disable_auto_merge',
        target: 'MERGEBOX_AUTO_MERGE_DISABLE_BUTTON',
      })
    })
  })

  describe('merge queue', () => {
    test('shows "merge when ready" when the repo uses the merge queue', async () => {
      const pullRequest = {
        ...pullRequestWithDefaultMergeActionsAndMethods,
        viewerMergeActions: mockViewerMergeActions['defaultMergeQueue'],
      }

      renderWithClient(<MergeSection {...pullRequest} />)

      const button = screen.getByRole('button', {name: 'Merge when ready'})
      expect(button).toBeInTheDocument()
    })

    describe('button actions', () => {
      test('are enabled when the merge requirement state is UNMERGEABLE', async () => {
        const pullRequest: MergeSectionProps = {
          ...pullRequestWithDefaultMergeActionsAndMethods,
          viewerMergeActions: mockViewerMergeActions['defaultMergeQueue'],
          viewerCanAddToMergeQueueSolo: true,
          mergeRequirementsState: 'UNMERGEABLE',
        }
        renderWithClient(<MergeSection {...pullRequest} />)

        const mergeWhenReadyButton = screen.getByRole('button', {name: 'Merge when ready'})
        expect(mergeWhenReadyButton).toHaveAttribute('aria-disabled', 'false')

        const selectMethodQueueMethodButton = screen.getByRole('button', {name: 'Select merge queue method'})
        expect(selectMethodQueueMethodButton).toHaveAttribute('aria-disabled', 'false')
      })

      test('when aria-disabled, does not perform action and shows tooltip instead', async () => {
        const pullRequest: MergeSectionProps = {
          ...pullRequestWithDefaultMergeActionsAndMethods,
          viewerMergeActions: mockViewerMergeActions['defaultMergeQueue'],
          viewerCanAddToMergeQueueSolo: true,
          mergeStateStatus: 'UNKNOWN',
          mergeRequirementsState: 'UNKNOWN',
        }

        const {user} = renderWithClient(<MergeSection {...pullRequest} />)

        const button = screen.getByRole('button', {name: 'Merge when ready'})
        expect(button).toHaveAttribute('aria-disabled', 'true')

        // Expect confirmation does not appear
        await user.click(button)

        let tooltip = screen.getByText('Checking for the ability to merge automatically')
        expect(tooltip).toHaveAttribute('role', 'tooltip')
        expect(tooltip).toBeInTheDocument()
        expect(screen.queryByRole('button', {name: 'Confirm merge when ready'})).not.toBeInTheDocument()

        const mergeQueueOptionsButton = screen.getByRole('button', {name: 'Select merge queue method'})
        expect(mergeQueueOptionsButton).toHaveAttribute('aria-disabled', 'true')

        await user.hover(mergeQueueOptionsButton)

        tooltip = screen.getByText('Checking for the ability to merge automatically')
        expect(tooltip).toHaveAttribute('role', 'tooltip')
        expect(tooltip).toBeInTheDocument()

        // Expect action list does not appear
        await user.click(mergeQueueOptionsButton)
        expect(screen.queryByText('Queue and merge in a group')).not.toBeInTheDocument()
        expect(screen.queryByText('Queue and force solo merge')).not.toBeInTheDocument()
      })

      test('are aria-disabled when the merge requirement state is UNKNOWN', async () => {
        const pullRequest: MergeSectionProps = {
          ...pullRequestWithDefaultMergeActionsAndMethods,
          viewerMergeActions: mockViewerMergeActions['defaultMergeQueue'],
          viewerCanAddToMergeQueueSolo: true,
          mergeStateStatus: 'UNKNOWN',
          mergeRequirementsState: 'UNKNOWN',
        }

        renderWithClient(<MergeSection {...pullRequest} />)

        const button = screen.getByRole('button', {name: 'Merge when ready'})
        expect(button).toHaveAttribute('aria-disabled', 'true')

        const selectMethodQueueMethodButton = screen.getByRole('button', {name: 'Select merge queue method'})
        expect(selectMethodQueueMethodButton).toHaveAttribute('aria-disabled', 'true')
      })

      test('are aria-disabled in draft mode', async () => {
        const pullRequest: MergeSectionProps = {
          ...pullRequestWithDefaultMergeActionsAndMethods,
          isDraft: true,
          viewerMergeActions: mockViewerMergeActions['defaultMergeQueue'],
          viewerCanAddToMergeQueueSolo: true,
          mergeStateStatus: 'UNKNOWN',
          mergeRequirementsState: 'UNKNOWN',
        }

        renderWithClient(<MergeSection {...pullRequest} />)

        const button = screen.getByRole('button', {name: 'Merge when ready'})
        expect(button).toHaveAttribute('aria-disabled', 'true')

        const selectMethodQueueMethodButton = screen.getByRole('button', {name: 'Select merge queue method'})
        expect(selectMethodQueueMethodButton).toHaveAttribute('aria-disabled', 'true')
      })

      test('are enabled when the merge requirement state is MERGEABLE', async () => {
        const pullRequest: MergeSectionProps = {
          ...pullRequestWithDefaultMergeActionsAndMethods,
          isDraft: false,
          viewerMergeActions: mockViewerMergeActions['defaultMergeQueue'],
          viewerCanAddToMergeQueueSolo: true,
          mergeStateStatus: 'CLEAN',
          mergeRequirementsState: 'MERGEABLE',
        }
        renderWithClient(<MergeSection {...pullRequest} />)

        const button = screen.getByRole('button', {name: 'Merge when ready'})
        expect(button).toHaveAttribute('aria-disabled', 'false')

        const selectMethodQueueMethodButton = screen.getByRole('button', {name: 'Select merge queue method'})
        expect(selectMethodQueueMethodButton).toHaveAttribute('aria-disabled', 'false')
      })
    })

    test('shows link to merge queue in messaging', async () => {
      const mergeQueueUrl = 'http://github.localhost.com/monalisa/smile/queue'
      const pullRequest: MergeSectionProps = {
        ...pullRequestWithDefaultMergeActionsAndMethods,
        viewerMergeActions: mockViewerMergeActions['defaultMergeQueue'],
        mergeQueue: {
          url: mergeQueueUrl,
        },
      }

      renderWithClient(<MergeSection {...pullRequest} />)

      const link = screen.getByRole('link', {name: 'merge queue'})
      expect(link).toBeInTheDocument()
      expect((link as HTMLAnchorElement).href).toBe(mergeQueueUrl)
    })

    test('displaying merge when ready method options', async () => {
      const pullRequest: MergeSectionProps = {
        ...pullRequestWithDefaultMergeActionsAndMethods,
        viewerMergeActions: mockViewerMergeActions['defaultMergeQueue'],
        viewerCanAddToMergeQueueSolo: true,
        mergeQueue: {
          url: 'http://github.localhost.com/monalisa/smile/queue',
        },
      }

      const {user} = renderWithClient(<MergeSection {...pullRequest} />)

      const primaryButton = screen.getByRole('button', {name: 'Merge when ready'})
      expect(primaryButton).toBeInTheDocument()

      const mergeQueueOptionsButton = screen.getByRole('button', {name: 'Select merge queue method'})
      expect(mergeQueueOptionsButton).toBeInTheDocument()

      await user.click(mergeQueueOptionsButton)
      expect(screen.getByText('Queue and merge in a group')).toBeInTheDocument()
      expect(
        screen.getByText(
          `This pull request will be automatically grouped with other pull requests and merged into main.`,
        ),
      ).toBeInTheDocument()
      expect(screen.getByText('Queue and force solo merge')).toBeInTheDocument()
      expect(screen.getByText(`This pull request will be merged into main by itself.`)).toBeInTheDocument()
    })

    test('selecting merge queue methods', async () => {
      const pullRequest: MergeSectionProps = {
        ...pullRequestWithDefaultMergeActionsAndMethods,
        viewerMergeActions: mockViewerMergeActions['defaultMergeQueue'],
        viewerCanAddToMergeQueueSolo: true,
        mergeQueue: {
          url: 'http://github.localhost.com/monalisa/smile/queue',
        },
      }
      const {user} = renderWithClient(<MergeSection {...pullRequest} />)

      const primaryButton = screen.getByRole('button', {name: 'Merge when ready'})
      expect(primaryButton).toBeInTheDocument()

      const mergeQueueOptionsButton = screen.getByRole('button', {name: 'Select merge queue method'})
      expect(mergeQueueOptionsButton).toBeInTheDocument()

      await user.click(mergeQueueOptionsButton)
      let checkedOption = screen.getByRole('menuitemradio', {checked: true})

      expect(checkedOption.textContent).toContain('Queue and merge in a group')

      await user.click(screen.getByText('Queue and force solo merge'))

      // open options again to check for selected option since selection closes the menu
      await user.click(mergeQueueOptionsButton)

      checkedOption = screen.getByRole('menuitemradio', {checked: true})
      expect(checkedOption.textContent).toContain('Queue and force solo merge')

      // Select original merge queue method
      await user.click(screen.getByText('Queue and merge in a group'))

      // assert that both selecting both merge options send analytic events
      expectAnalyticsEvents(
        {
          type: 'merqe_queue_section.select_queue_and_force_solo_merge',
          target: 'MERGEBOX_MERGE_QUEUE_SECTION_MERGE_METHOD_MENU_ITEM',
        },
        {
          type: 'merqe_queue_section.select_queue_and_merge_in_a_group',
          target: 'MERGEBOX_MERGE_QUEUE_SECTION_MERGE_METHOD_MENU_ITEM',
        },
      )

      // open options again to check for selected option since selection closes the menu
      await user.click(mergeQueueOptionsButton)

      checkedOption = screen.getByRole('menuitemradio', {checked: true})
      expect(checkedOption.textContent).toContain('Queue and merge in a group')
    })

    test('confirming adding to merge queue', async () => {
      const pullRequest: MergeSectionProps = {
        ...pullRequestWithDefaultMergeActionsAndMethods,
        viewerMergeActions: mockViewerMergeActions['defaultMergeQueue'],
        mergeQueue: {
          url: 'http://github.localhost.com/monalisa/smile/queue',
        },
      }
      const {user} = renderWithClient(<MergeSection {...pullRequest} />)

      const primaryButton = screen.getByRole('button', {name: 'Merge when ready'})
      expect(primaryButton).toBeInTheDocument()
      await user.click(primaryButton)

      const confirmAddToQueueButton = screen.getByRole('button', {name: 'Confirm merge when ready'})
      expect(confirmAddToQueueButton).toBeInTheDocument()
      expect(confirmAddToQueueButton).toHaveFocus()
      expect(primaryButton).not.toBeInTheDocument()
    })

    test('"Merge when ready" button, confirmation and cancellation actions send analytics events', async () => {
      const pullRequest: MergeSectionProps = {
        ...pullRequestWithDefaultMergeActionsAndMethods,
        viewerMergeActions: mockViewerMergeActions['defaultMergeQueue'],
        mergeQueue: {
          url: 'http://github.localhost.com/monalisa/smile/queue',
        },
      }
      mockFetch.mockRouteOnce(enableAutoMergePageDataRoute, {}, {status: 200, ok: true})
      const {user} = renderWithClient(<MergeSection {...pullRequest} />)

      await user.click(screen.getByRole('button', {name: 'Merge when ready'}))
      await user.click(screen.getByRole('button', {name: 'Cancel'}))
      await user.click(screen.getByRole('button', {name: 'Merge when ready'}))
      await user.click(screen.getByRole('button', {name: 'Confirm merge when ready'}))

      // Assert analytics calls
      // (1x for cancel, 1x for confirmation, and 2x opening direct merge confirmation)
      expectAnalyticsEvents(
        {type: 'auto_merge_section.merge_click', target: 'MERGEBOX_AUTO_MERGE_BUTTON'},
        {type: 'auto_merge_section.cancel_auto_merge', target: 'MERGEBOX_AUTO_MERGE_CANCEL_CONFIRMATION_BUTTON'},
        {type: 'auto_merge_section.merge_click', target: 'MERGEBOX_AUTO_MERGE_BUTTON'},
        {type: 'auto_merge_section.confirm_direct_merge', target: 'MERGEBOX_AUTO_MERGE_CONFIRMATION_BUTTON'},
      )
    })

    test('On confirming add to merge queue, shows a pending state until the mutation is successful', async () => {
      const pullRequest: MergeSectionProps = {
        ...pullRequestWithDefaultMergeActionsAndMethods,
        viewerMergeActions: mockViewerMergeActions['defaultMergeQueue'],
        mergeQueue: {
          url: 'http://github.localhost.com/monalisa/smile/queue',
        },
      }
      const {user} = renderWithClient(<MergeSection {...pullRequest} />)

      await user.click(screen.getByRole('button', {name: 'Merge when ready'}))

      const confirmAddToQueueButton = screen.getByRole('button', {name: 'Confirm merge when ready'})

      assertButtonEnabled(confirmAddToQueueButton)

      await user.click(confirmAddToQueueButton)

      assertButtonInLoadingState(confirmAddToQueueButton, 'Adding to merge queue...')

      mockFetch.resolvePendingRequest(enableAutoMergePageDataRoute, {}, {status: 200, ok: true})

      await assertWaitForButtonToBeEnabled(confirmAddToQueueButton)
      expect.hasAssertions()
    })

    test('On confirming add to merge queue, displays an error if the mutation is unsuccessful', async () => {
      const autoMergeError = 'Failed to add to merge queue'
      const pullRequest: MergeSectionProps = {
        ...pullRequestWithDefaultMergeActionsAndMethods,
        viewerMergeActions: mockViewerMergeActions['defaultMergeQueue'],
        mergeQueue: {
          url: 'http://github.localhost.com/monalisa/smile/queue',
        },
      }
      const {user} = renderWithClient(<MergeSection {...pullRequest} />)

      await user.click(screen.getByRole('button', {name: 'Merge when ready'}))

      const confirmAddToQueueButton = screen.getByRole('button', {name: 'Confirm merge when ready'})

      assertButtonEnabled(confirmAddToQueueButton)

      user.click(confirmAddToQueueButton)

      await screen.findByText('Adding to merge queue...')

      assertButtonInLoadingState(confirmAddToQueueButton, 'Adding to merge queue...')

      mockFetch.resolvePendingRequest(enableAutoMergePageDataRoute, {error: autoMergeError}, {status: 422, ok: false})

      expect(await screen.findByText(autoMergeError)).toBeInTheDocument()

      assertButtonEnabled(confirmAddToQueueButton)
    })

    describe('auto merge', () => {
      test('shows "Disable auto-merge" button when auto merge is active', async () => {
        const pullRequest: MergeSectionProps = {
          ...pullRequestWithDefaultMergeActionsAndMethods,
          autoMergeRequest: {
            mergeMethod: 'MERGE',
          },
          viewerMergeActions: mockViewerMergeActions['defaultMergeQueue'],
          mergeQueue: {
            url: 'http://github.localhost.com/monalisa/smile/queue',
          },
          viewerCanDisableAutoMerge: true,
        }

        renderWithClient(<MergeSection {...pullRequest} />)

        const button = screen.getByRole('button', {name: 'Disable auto-merge'})
        expect(button).toBeEnabled()
        expect(screen.getByText('be added to the merge queue')).toBeVisible()
      })

      test('"Disable auto-merge" button click sends analytics event', async () => {
        const pullRequest: MergeSectionProps = {
          ...pullRequestWithDefaultMergeActionsAndMethods,
          autoMergeRequest: {
            mergeMethod: 'MERGE',
          },
          viewerMergeActions: mockViewerMergeActions['defaultMergeQueue'],
          mergeQueue: {
            url: 'http://github.localhost.com/monalisa/smile/queue',
          },
          viewerCanDisableAutoMerge: true,
        }
        const {user} = renderWithClient(<MergeSection {...pullRequest} />)

        await user.click(screen.getByRole('button', {name: 'Disable auto-merge'}))
        expectAnalyticsEvents({
          type: 'auto_merge_section.disable_auto_merge',
          target: 'MERGEBOX_AUTO_MERGE_DISABLE_BUTTON',
        })
      })

      test('shows error banner when disabling auto merge fails', async () => {
        const errorMessage = 'Failed to disable auto-merge for pull request.'
        mockFetch.mockRouteOnce(disableAutoMergePageDataRoute, {error: errorMessage}, {status: 422, ok: false})

        const pullRequest: MergeSectionProps = {
          ...pullRequestWithDefaultMergeActionsAndMethods,
          autoMergeRequest: {
            mergeMethod: 'MERGE',
          },
          viewerMergeActions: mockViewerMergeActions['defaultMergeQueue'],
          mergeQueue: {
            url: 'http://github.localhost.com/monalisa/smile/queue',
          },
          viewerCanDisableAutoMerge: true,
        }
        const {user} = renderWithClient(<MergeSection {...pullRequest} />)

        await user.click(screen.getByRole('button', {name: 'Disable auto-merge'}))

        expect(screen.getByText(errorMessage)).toBeVisible()
      })
    })
  })

  describe('direct merge options', () => {
    beforeAll(async () => {
      // preload to prevent timeout when lazy-loading component within tests
      await import('../sections/merge-section/command-line-instructions/CommandLineInstructionsDialog')
    })

    test('renders alternate instructions and returns focus to the command line instructions button', async () => {
      const mergeInstructionsPageDataRoute = `${BASE_PAGE_DATA_URL}/page_data/${PageData.mergeInstructions}`
      const {user} = renderWithClient(<MergeSection {...pullRequestWithDefaultMergeActionsAndMethods} />)

      expect(screen.getByText(/You can also merge this with the command line./)).toBeVisible()
      const instructionsButton = screen.getByRole('button', {name: 'View command line instructions.'})

      expect(instructionsButton).toBeInTheDocument()

      mockFetch.mockRouteOnce(mergeInstructionsPageDataRoute, defaultMergeInstructionsApiResponse)

      await user.click(instructionsButton)

      expect(await screen.findByText('Merging via command line', {}, {timeout: 5000})).toBeInTheDocument()
      expectAnalyticsEvents({
        type: 'direct_merge_section.view_command_line_instructions',
        target: 'MERGEBOX_DIRECT_MERGE_SECTION_VIEW_COMMAND_LINE_INSTRUCTIONS_BUTTON',
      })

      const closeButton = screen.getByRole('button', {name: 'Close'})
      await user.click(closeButton)

      expect(screen.getByRole('button', {name: 'View command line instructions.'})).toHaveFocus()
    })

    test('sets selected merge method to preferred merge method based on context value', async () => {
      renderWithClient(
        <MergeSection defaultMergeMethod={MergeMethod.SQUASH} {...pullRequestWithDefaultMergeActionsAndMethods} />,
      )

      const primaryButton = screen.getByRole('button', {name: 'Squash and merge'})
      expect(primaryButton).toBeInTheDocument()
    })

    test('renders all allowed merge methods and sends analytics when selecting them', async () => {
      const pullRequest: MergeSectionProps = {
        ...pullRequestWithDefaultMergeActionsAndMethods,
        mergeRequirementsState: 'MERGEABLE',
        numberOfCommits: 22,
      }
      const {user} = renderWithClient(<MergeSection {...pullRequest} />)

      const mergeButtonOptions = screen.getByLabelText('Select merge method')
      await user.click(mergeButtonOptions)
      const mergeCommitOption = screen.getByText('Create a merge commit')
      screen.getByText('All commits from this branch will be added to the base branch via a merge commit.')
      await user.click(mergeCommitOption)
      // reopen menu
      await user.click(mergeButtonOptions)
      const squashAndMergeOption = screen.getByText('Squash and merge')
      screen.getByText('The 22 commits from this branch will be combined into one commit in the base branch.')
      await user.click(squashAndMergeOption)
      // reopen menu
      await user.click(mergeButtonOptions)
      const rebaseAndMergeOption = screen.getByText('Rebase and merge')
      screen.queryByText('The 22 commits from this branch will be rebased and added to the base branch.')
      await user.click(rebaseAndMergeOption)

      expectAnalyticsEvents(
        {
          type: 'direct_merge_section.select_create_a_merge_commit',
          target: 'MERGEBOX_DIRECT_MERGE_SECTION_MERGE_METHOD_MENU_ITEM',
        },
        {
          type: 'direct_merge_section.select_squash_and_merge',
          target: 'MERGEBOX_DIRECT_MERGE_SECTION_MERGE_METHOD_MENU_ITEM',
        },
        {
          type: 'direct_merge_section.select_rebase_and_merge',
          target: 'MERGEBOX_DIRECT_MERGE_SECTION_MERGE_METHOD_MENU_ITEM',
        },
      )
    })

    test('renders all the allowed merge methods, messaging handles single commits', async () => {
      const pullRequest: MergeSectionProps = {
        ...pullRequestWithDefaultMergeActionsAndMethods,
        mergeRequirementsState: 'MERGEABLE',
        numberOfCommits: 1,
      }
      const {user} = renderWithClient(<MergeSection {...pullRequest} />)

      const mergeButtonOptions = screen.getByLabelText('Select merge method')
      expect(mergeButtonOptions).toBeInTheDocument()
      await user.click(mergeButtonOptions)

      const mergeCommitOption = screen.getByText('Create a merge commit')
      expect(mergeCommitOption).toBeInTheDocument()
      const mergeCommitText = screen.getByText(
        'All commits from this branch will be added to the base branch via a merge commit.',
      )
      expect(mergeCommitText).toBeInTheDocument()
      const squashAndMergeOption = screen.getByText('Squash and merge')
      expect(squashAndMergeOption).toBeInTheDocument()
      const squashAndMergeText = screen.getByText('The 1 commit from this branch will be added to the base branch.')
      expect(squashAndMergeText).toBeInTheDocument()
      const rebaseAndMergeOption = screen.getByText('Rebase and merge')
      expect(rebaseAndMergeOption).toBeInTheDocument()
      const rebaseAndMergeText = screen.queryByText(
        'The 1 commit from this branch will be rebased and added to the base branch.',
      )
      expect(rebaseAndMergeText).toBeInTheDocument()
    })

    test('does not render create merge commit option when it is not an allowed merge method', async () => {
      const pullRequest: MergeSectionProps = {
        ...pullRequestWithDefaultMergeActionsAndMethods,
        mergeRequirementsState: 'MERGEABLE',
        viewerMergeActions: [
          {
            name: MergeAction.DIRECT_MERGE,
            allowableStatus: 'ALLOWED',
            mergeMethods: [
              {
                name: MergeMethod.MERGE,
                allowableStatus: 'BLOCKED',
              },
              {
                name: MergeMethod.SQUASH,
                allowableStatus: 'ALLOWED',
              },
              {
                name: MergeMethod.REBASE,
                allowableStatus: 'ALLOWED',
              },
            ],
          },
        ],
      }

      const {user} = renderWithClient(<MergeSection {...pullRequest} />)

      const mergeButtonOptions = screen.getByRole('button', {name: 'Select merge method'})
      expect(mergeButtonOptions).toBeInTheDocument()
      await user.click(mergeButtonOptions)

      const mergeCommitOption = screen.queryByText('Create a merge commit')
      expect(mergeCommitOption).not.toBeInTheDocument()
    })

    test('sets merge method and does not render select merge method if there is only one allowed merge method', async () => {
      const pullRequest: MergeSectionProps = {
        ...pullRequestWithDefaultMergeActionsAndMethods,
        mergeRequirementsState: 'MERGEABLE',
        viewerMergeActions: [
          {
            name: MergeAction.DIRECT_MERGE,
            allowableStatus: 'ALLOWED',
            mergeMethods: [
              {
                name: MergeMethod.MERGE,
                allowableStatus: 'BLOCKED',
              },
              {
                name: MergeMethod.SQUASH,
                allowableStatus: 'ALLOWED',
              },
              {
                name: MergeMethod.REBASE,
                allowableStatus: 'BLOCKED',
              },
            ],
          },
        ],
      }

      renderWithClient(<MergeSection defaultMergeMethod={MergeMethod.SQUASH} {...pullRequest} />)

      const mergeButtonOptions = screen.queryByRole('button', {name: 'Select merge method'})
      expect(mergeButtonOptions).not.toBeInTheDocument()
      const squashMergeButton = screen.queryByRole('button', {name: 'Squash and merge'})
      expect(squashMergeButton).toBeInTheDocument()
    })

    test('can set the selected merge method from available options', async () => {
      const pullRequest: MergeSectionProps = {
        ...pullRequestWithDefaultMergeActionsAndMethods,
        mergeRequirementsState: 'MERGEABLE',
      }
      const {user} = renderWithClient(<MergeSection defaultMergeMethod={MergeMethod.MERGE} {...pullRequest} />)

      const mergeButtonOptions = screen.getByRole('button', {name: 'Select merge method'})
      expect(mergeButtonOptions).toBeInTheDocument()
      const selectedMergeMethodButton = screen.getByRole('button', {name: 'Merge pull request'})
      expect(selectedMergeMethodButton).toBeInTheDocument()
      await user.click(mergeButtonOptions)
      const squashAndMergeOption = screen.getByText('Squash and merge')
      expect(squashAndMergeOption).toBeInTheDocument()
      await user.click(squashAndMergeOption)
      const squashAndMergeButton = screen.getByRole('button', {name: 'Squash and merge'})
      expect(squashAndMergeButton).toBeInTheDocument()
    })

    test.each<[PullRequestMergeRequirementsState]>([['UNKNOWN'], ['UNMERGEABLE']])(
      'ability to click merge methods is blocked when merge requirement state is %s',
      async state => {
        const pullRequest: MergeSectionProps = {
          ...pullRequestWithDefaultMergeActionsAndMethods,
          mergeRequirementsState: state,
        }

        const {user} = renderWithClient(<MergeSection defaultMergeMethod={MergeMethod.MERGE} {...pullRequest} />)

        const selectedMergeMethodButton = screen.getByRole('button', {name: 'Merge pull request'})
        expect(selectedMergeMethodButton).toBeInTheDocument()
        await user.click(selectedMergeMethodButton)

        let tooltip = screen.getByText('Merging is blocked due to failing merge requirements')
        expect(tooltip).toBeInTheDocument()

        const mergeButtonOptions = screen.getByRole('button', {name: 'Select merge method'})
        expect(mergeButtonOptions).toHaveAttribute('aria-disabled', 'false')
        await user.click(mergeButtonOptions)

        await user.click(screen.getByText('Squash and merge'))

        const squashAndMergeButton = screen.getByRole('button', {name: 'Squash and merge'})
        expect(squashAndMergeButton).toBeInTheDocument()
        await user.click(squashAndMergeButton)

        tooltip = screen.getByText('Merging is blocked due to failing merge requirements')
        expect(tooltip).toBeInTheDocument()
      },
    )
  })

  describe('engaging a direct merge option', () => {
    test('when merge is inactive, show tooltip only when activated (focus, hover, click)', async () => {
      const pullRequest: MergeSectionProps = {
        ...pullRequestWithDefaultMergeActionsAndMethods,
        mergeRequirementsState: 'UNKNOWN',
      }
      const {user} = renderWithClient(<MergeSection defaultMergeMethod={MergeMethod.MERGE} {...pullRequest} />)

      const traditionalMergeButton = screen.getByRole('button', {name: 'Merge pull request'})
      expect(traditionalMergeButton).toBeInTheDocument()
      await user.hover(traditionalMergeButton)

      const tooltip = screen.getByText('Merging is blocked due to failing merge requirements')
      expect(tooltip).toHaveAttribute('role', 'tooltip')
      expect(tooltip).toBeInTheDocument()

      // Do not show confirmation screen
      expect(screen.queryByText('Commit header')).not.toBeInTheDocument()
      expect(screen.queryByText('Commit message')).not.toBeInTheDocument()
      expect(screen.queryByRole('button', {name: 'Confirm merge'})).not.toBeInTheDocument()
    })

    test('for traditional merge, shows commit header and message input containing placeholder text with button to confirm', async () => {
      const pullRequest: MergeSectionProps = {
        ...pullRequestWithDefaultMergeActionsAndMethods,
        mergeRequirementsState: 'MERGEABLE',
        commitMessageHeadline: 'Making an update to the branch.',
        commitMessageBody: 'Extra commit info.',
        defaultCommitAuthorEmail: 'monalisa@github.com',
      }
      const {user} = renderWithClient(<MergeSection defaultMergeMethod={MergeMethod.MERGE} {...pullRequest} />)

      const traditionalMergeButton = screen.getByRole('button', {name: 'Merge pull request'})
      expect(traditionalMergeButton).toBeInTheDocument()
      await user.click(traditionalMergeButton)
      expect(screen.getByLabelText('Commit message')).toBeInTheDocument()
      expect(screen.getByLabelText('Extended description')).toBeInTheDocument()

      const defaultCommitHeader = screen.getByDisplayValue('Making an update to the branch.')
      expect(defaultCommitHeader).toBeInTheDocument()
      const defaultCommitMessage = screen.getByDisplayValue('Extra commit info.')
      expect(defaultCommitMessage).toBeInTheDocument()
      expect(screen.getByRole('button', {name: 'Confirm merge'})).toBeInTheDocument()
    })

    test('send analytics events when clicking on direct merge method button, canceling and confirming', async () => {
      const pullRequest: MergeSectionProps = {
        ...pullRequestWithDefaultMergeActionsAndMethods,
        mergeRequirementsState: 'MERGEABLE',
        commitMessageHeadline: 'PR title',
        commitMessageBody: 'PR body',
        defaultCommitAuthorEmail: 'monalisa@github.com',
      }
      const {user} = renderWithClient(<MergeSection defaultMergeMethod={MergeMethod.MERGE} {...pullRequest} />)

      await user.click(screen.getByRole('button', {name: 'Merge pull request'}))

      // Ensure Commit message confirmation
      screen.getByLabelText('Commit message')
      await user.click(screen.getByRole('button', {name: 'Cancel'}))
      await user.click(screen.getByRole('button', {name: 'Merge pull request'}))

      // Ensure Commit message confirmation
      await screen.findByLabelText('Commit message')
      await user.click(screen.getByRole('button', {name: 'Confirm merge'}))

      // Assert analytics calls
      // (1x for cancel, 1x for confirmation, and 2x opening diret merge confirmation)
      expectAnalyticsEvents(
        {type: 'direct_merge_section.direct_merge_click', target: 'MERGEBOX_DIRECT_MERGE_SECTION_MERGE_BUTTON'},
        {type: 'direct_merge_section.cancel_direct_merge', target: 'MERGEBOX_DIRECT_MERGE_CANCEL_CONFIRMATION_BUTTON'},
        {type: 'direct_merge_section.direct_merge_click', target: 'MERGEBOX_DIRECT_MERGE_SECTION_MERGE_BUTTON'},
        {type: 'direct_merge_section.confirm_direct_merge', target: 'MERGEBOX_DIRECT_MERGE_CONFIRMATION_BUTTON'},
      )
    })

    test('for traditional merge, focuses commit header input on render', async () => {
      const pullRequest: MergeSectionProps = {
        ...pullRequestWithDefaultMergeActionsAndMethods,
        mergeRequirementsState: 'MERGEABLE',
        commitMessageHeadline: 'Making an update to the branch.',
        commitMessageBody: 'Extra commit info.',
        defaultCommitAuthorEmail: 'monalisa@github.com',
      }

      const {user} = renderWithClient(<MergeSection defaultMergeMethod={MergeMethod.MERGE} {...pullRequest} />)

      const traditionalMergeButton = screen.getByRole('button', {name: 'Merge pull request'})
      expect(traditionalMergeButton).toBeInTheDocument()
      await user.click(traditionalMergeButton)
      const commitMessageInput = screen.getByLabelText('Commit message')

      expect(commitMessageInput).toBeInTheDocument()
      expect(commitMessageInput).toHaveFocus()
    })

    test('for squash and merge, shows commit header and message input containing default values with button to confirm', async () => {
      const userEmail = 'monalisa@github.com'
      const pullRequest: MergeSectionProps = {
        ...pullRequestWithDefaultMergeActionsAndMethods,
        mergeRequirementsState: 'MERGEABLE',
        commitMessageHeadline: 'Making an update to the branch.',
        commitMessageBody: 'Additional content for commit.',
        defaultCommitAuthorEmail: userEmail,
      }
      const {user} = renderWithClient(<MergeSection defaultMergeMethod={MergeMethod.SQUASH} {...pullRequest} />)

      const squashAndMergeButton = screen.getByRole('button', {name: 'Squash and merge'})
      expect(squashAndMergeButton).toBeInTheDocument()
      await user.click(squashAndMergeButton)
      expect(screen.getByLabelText('Commit message')).toBeInTheDocument()
      expect(screen.getByLabelText('Extended description')).toBeInTheDocument()

      expect(screen.getByDisplayValue('Making an update to the branch.')).toBeInTheDocument()
      expect(screen.getByDisplayValue('Additional content for commit.')).toBeInTheDocument()

      expect(screen.getByRole('button', {name: 'Confirm squash and merge'})).toBeInTheDocument()
      expect(screen.getByText(`This commit will be authored by ${userEmail}.`)).toBeInTheDocument()
    })

    test('for multiple author emails, shows selector component', async () => {
      const userEmail = 'monalisa@github.com'
      const mergeMutationRoute = `${BASE_PAGE_DATA_URL}/page_data/${PageData.merge}`
      const pullRequest: MergeSectionProps = {
        ...pullRequestWithDefaultMergeActionsAndMethods,
        mergeRequirementsState: 'MERGEABLE',
        commitMessageHeadline: 'Commit message headline',
        commitMessageBody: 'Commit message body',
        defaultCommitAuthorEmail: userEmail,
        possibleCommitAuthorEmails: ['monalisa@github.com', 'mona@github.com', 'test@github.com'],
      }
      const {user} = renderWithClient(<MergeSection defaultMergeMethod={MergeMethod.SQUASH} {...pullRequest} />)

      const squashAndMergeButton = screen.getByRole('button', {name: 'Squash and merge'})
      expect(squashAndMergeButton).toBeInTheDocument()
      await user.click(squashAndMergeButton)

      expect(screen.getByRole('option', {name: 'test@github.com'})).toBeInTheDocument()
      expect(screen.getByRole('option', {name: 'mona@github.com'})).toBeInTheDocument()
      expect(screen.getByRole('option', {name: 'monalisa@github.com'})).toBeInTheDocument()

      await user.selectOptions(screen.getByRole('combobox'), screen.getByRole('option', {name: 'test@github.com'}))

      const confirmButton = screen.getByRole('button', {name: 'Confirm squash and merge'})
      expect(confirmButton).toBeInTheDocument()
      await user.click(confirmButton)

      await waitFor(() =>
        expectMockFetchCalledWith(mergeMutationRoute, {
          bypassBranchProtections: false,
          commitMessage: 'Commit message body',
          commitTitle: 'Commit message headline',
          mergeMethod: 'SQUASH',
          authorEmail: 'test@github.com',
        }),
      )
    })

    test('for squash and merge, focuses commit header input on render', async () => {
      const pullRequest: MergeSectionProps = {
        ...pullRequestWithDefaultMergeActionsAndMethods,
        mergeRequirementsState: 'MERGEABLE',
        commitMessageHeadline: 'Making an update to the branch.',
        commitMessageBody: 'Additional commit info.',
      }
      const {user} = renderWithClient(<MergeSection defaultMergeMethod={MergeMethod.SQUASH} {...pullRequest} />)

      const squashAndMergeButton = screen.getByRole('button', {name: 'Squash and merge'})
      expect(squashAndMergeButton).toBeInTheDocument()
      await user.click(squashAndMergeButton)
      const commitMessageBody = screen.getByLabelText('Commit message')
      expect(commitMessageBody).toBeInTheDocument()
      expect(commitMessageBody).toHaveFocus()
    })

    test('for rebase and merge, shows confirmation message with button to confirm', async () => {
      const pullRequest: MergeSectionProps = {
        ...pullRequestWithDefaultMergeActionsAndMethods,
        mergeRequirementsState: 'MERGEABLE',
        commitMessageHeadline: 'PR title',
        commitMessageBody: 'PR body',
      }
      const {user} = renderWithClient(<MergeSection defaultMergeMethod={MergeMethod.REBASE} {...pullRequest} />)

      const rebaseAndMergeButton = screen.getByRole('button', {name: 'Rebase and merge'})
      expect(rebaseAndMergeButton).toBeInTheDocument()
      await user.click(rebaseAndMergeButton)
      expect(screen.getByText(`This will rebase your changes and merge them into main.`)).toBeInTheDocument()
      expect(screen.getByRole('button', {name: 'Confirm rebase and merge'})).toBeInTheDocument()
    })

    test('cancel closes the confirmation screen, renders the primary action button and focuses it', async () => {
      const pullRequest: MergeSectionProps = {
        ...pullRequestWithDefaultMergeActionsAndMethods,
        mergeRequirementsState: 'MERGEABLE',
        commitMessageHeadline: 'PR title',
        commitMessageBody: 'PR body',
        shouldFocusPrimaryMergeButton: true,
      }
      const {user} = renderWithClient(<MergeSection defaultMergeMethod={MergeMethod.REBASE} {...pullRequest} />)

      const rebaseAndMergeButton = screen.getByRole('button', {name: 'Rebase and merge'})
      expect(rebaseAndMergeButton).toBeInTheDocument()
      await user.click(rebaseAndMergeButton)
      expect(screen.getByRole('button', {name: 'Confirm rebase and merge'})).toBeInTheDocument()
      const cancelButton = screen.getByRole('button', {name: 'Cancel'})
      expect(cancelButton).toBeInTheDocument()
      await user.click(cancelButton)
      const reRenderedRebaseAndMergeButton = screen.getByRole('button', {name: 'Rebase and merge'})
      expect(reRenderedRebaseAndMergeButton).toBeInTheDocument()
      expect(reRenderedRebaseAndMergeButton).toHaveFocus()
    })

    test('when user is in the commit message body, pressing cmd + enter confirms the merge', async () => {
      const mergeMutationRoute = `${BASE_PAGE_DATA_URL}/page_data/${PageData.merge}`
      const pullRequest: MergeSectionProps = {
        ...pullRequestWithDefaultMergeActionsAndMethods,
        mergeRequirementsState: 'MERGEABLE',
        commitMessageHeadline: 'Making an update to the branch.',
        commitMessageBody: 'Extra commit info.',
        defaultCommitAuthorEmail: 'monalisa@github.com',
      }

      const {user} = renderWithClient(<MergeSection defaultMergeMethod={MergeMethod.MERGE} {...pullRequest} />)
      const traditionalMergeButton = screen.getByRole('button', {name: 'Merge pull request'})
      expect(traditionalMergeButton).toBeInTheDocument()
      await user.click(traditionalMergeButton)
      const commitMessageInput = screen.getByLabelText('Extended description')
      const confirmButton = screen.getByRole('button', {name: 'Confirm merge'})

      await user.click(commitMessageInput)

      await user.keyboard('{Control>}{Enter}{/Control}')

      await screen.findAllByText('Merging...')

      assertButtonInLoadingState(confirmButton, 'Merging...')

      mockFetch.resolvePendingRequest(mergeMutationRoute, {}, {status: 200, ok: true})
    })

    test('shows a pending state until merge succeeds', async () => {
      const mergeMutationRoute = `${BASE_PAGE_DATA_URL}/page_data/${PageData.merge}`
      const pullRequest: MergeSectionProps = {
        ...pullRequestWithDefaultMergeActionsAndMethods,
        mergeRequirementsState: 'MERGEABLE',
        commitMessageHeadline: 'PR title',
        commitMessageBody: 'PR body',
      }
      const {user} = renderWithClient(<MergeSection defaultMergeMethod={MergeMethod.REBASE} {...pullRequest} />)

      const rebaseAndMergeButton = screen.getByRole('button', {name: 'Rebase and merge'})
      expect(rebaseAndMergeButton).toBeInTheDocument()
      await user.click(rebaseAndMergeButton)
      const confirmButton = screen.getByRole('button', {name: 'Confirm rebase and merge'})

      assertButtonEnabled(confirmButton)

      await user.click(confirmButton)
      await screen.findAllByText('Merging...')

      assertButtonInLoadingState(confirmButton, 'Merging...')

      mockFetch.resolvePendingRequest(mergeMutationRoute, {}, {status: 200, ok: true})

      await assertWaitForButtonToBeEnabled(confirmButton)
      expect.hasAssertions()
    })

    describe('commit data we pass in when user has one email', () => {
      test('when rebase is the default merge method, we always pass in mergeMethod, commitMessage, commitTitle, and bypassBranchProtections', async () => {
        const mergeMutationRoute = `${BASE_PAGE_DATA_URL}/page_data/${PageData.merge}`
        const pullRequest: MergeSectionProps = {
          ...pullRequestWithDefaultMergeActionsAndMethods,
          mergeRequirementsState: 'MERGEABLE',
          commitMessageHeadline: 'PR title',
          commitMessageBody: 'PR body',
        }

        const {user} = renderWithClient(<MergeSection defaultMergeMethod={MergeMethod.REBASE} {...pullRequest} />)
        const rebaseAndMergeButton = screen.getByRole('button', {name: 'Rebase and merge'})
        expect(rebaseAndMergeButton).toBeInTheDocument()
        await user.click(rebaseAndMergeButton)
        const confirmButton = screen.getByRole('button', {name: 'Confirm rebase and merge'})
        expect(confirmButton).toBeInTheDocument()
        await user.click(confirmButton)

        await waitFor(() =>
          expectMockFetchCalledWith(mergeMutationRoute, {
            bypassBranchProtections: false,
            commitMessage: 'PR body',
            commitTitle: 'PR title',
            mergeMethod: 'REBASE',
          }),
        )
      })

      test('when we select rebase from dropdown, we always pass in mergeMethod, commitMessage, commitTitle, and bypassBranchProtections', async () => {
        const mergeMutationRoute = `${BASE_PAGE_DATA_URL}/page_data/${PageData.merge}`
        const pullRequest: MergeSectionProps = {
          ...pullRequestWithDefaultMergeActionsAndMethods,
          mergeRequirementsState: 'MERGEABLE',
          commitMessageHeadline: 'PR title',
          commitMessageBody: 'PR body',
        }

        const {user} = renderWithClient(<MergeSection {...pullRequest} />)
        const defaultButton = screen.getByRole('button', {name: 'Merge pull request'})
        expect(defaultButton).toBeInTheDocument()

        const mergeButtonOptions = screen.getByRole('button', {name: 'Select merge method'})
        expect(mergeButtonOptions).toBeInTheDocument()
        await user.click(mergeButtonOptions)

        const rebaseCommitButton = screen.getByText('Rebase and merge')
        expect(rebaseCommitButton).toBeInTheDocument()
        await user.click(rebaseCommitButton)

        const rebaseAndMergeButton = screen.getByRole('button', {name: 'Rebase and merge'})
        expect(rebaseAndMergeButton).toBeInTheDocument()
        await user.click(rebaseAndMergeButton)

        const confirmButton = screen.getByRole('button', {name: 'Confirm rebase and merge'})
        expect(confirmButton).toBeInTheDocument()
        await user.click(confirmButton)

        await waitFor(() =>
          expectMockFetchCalledWith(mergeMutationRoute, {
            bypassBranchProtections: false,
            commitMessage: 'PR body',
            commitTitle: 'PR title',
            mergeMethod: 'REBASE',
          }),
        )
      })

      test('when merge is the default, we always pass in mergeMethod, commitMessage, commitTitle, and bypassBranchProtections', async () => {
        const mergeMutationRoute = `${BASE_PAGE_DATA_URL}/page_data/${PageData.merge}`
        const pullRequest: MergeSectionProps = {
          ...pullRequestWithDefaultMergeActionsAndMethods,
          mergeRequirementsState: 'MERGEABLE',
          commitMessageHeadline: 'PR title',
          commitMessageBody: 'PR body',
        }

        const {user} = renderWithClient(<MergeSection defaultMergeMethod={MergeMethod.MERGE} {...pullRequest} />)
        const mergeButton = screen.getByRole('button', {name: 'Merge pull request'})
        expect(mergeButton).toBeInTheDocument()
        await user.click(mergeButton)
        const confirmButton = screen.getByRole('button', {name: 'Confirm merge'})
        expect(confirmButton).toBeInTheDocument()
        await user.click(confirmButton)

        await waitFor(() =>
          expectMockFetchCalledWith(mergeMutationRoute, {
            bypassBranchProtections: false,
            commitMessage: 'PR body',
            commitTitle: 'PR title',
            mergeMethod: 'MERGE',
          }),
        )
      })

      test('when we select merge from the dropdown, we always pass in mergeMethod, commitMessage, commitTitle, and bypassBranchProtections', async () => {
        const mergeMutationRoute = `${BASE_PAGE_DATA_URL}/page_data/${PageData.merge}`
        const pullRequest: MergeSectionProps = {
          ...pullRequestWithDefaultMergeActionsAndMethods,
          mergeRequirementsState: 'MERGEABLE',
          commitMessageHeadline: 'PR title',
          commitMessageBody: 'PR body',
        }

        const {user} = renderWithClient(<MergeSection defaultMergeMethod={MergeMethod.SQUASH} {...pullRequest} />)
        const defaultButton = screen.getByRole('button', {name: 'Squash and merge'})
        expect(defaultButton).toBeInTheDocument()

        const mergeButtonOptions = screen.getByRole('button', {name: 'Select merge method'})
        expect(mergeButtonOptions).toBeInTheDocument()
        await user.click(mergeButtonOptions)

        const mergeCommitButton = screen.getByText('Create a merge commit')
        expect(mergeCommitButton).toBeInTheDocument()

        await user.click(mergeCommitButton)

        const mergeButton = screen.getByRole('button', {name: 'Merge pull request'})
        expect(mergeButton).toBeInTheDocument()
        await user.click(mergeButton)

        const confirmButton = screen.getByRole('button', {name: 'Confirm merge'})
        expect(confirmButton).toBeInTheDocument()
        await user.click(confirmButton)

        await waitFor(() =>
          expectMockFetchCalledWith(mergeMutationRoute, {
            bypassBranchProtections: false,
            commitMessage: 'PR body',
            commitTitle: 'PR title',
            mergeMethod: 'MERGE',
          }),
        )
      })

      test('when squash is the default, we always pass in mergeMethod, commitMessage, commitTitle, and bypassBranchProtections', async () => {
        const mergeMutationRoute = `${BASE_PAGE_DATA_URL}/page_data/${PageData.merge}`
        const pullRequest: MergeSectionProps = {
          ...pullRequestWithDefaultMergeActionsAndMethods,
          mergeRequirementsState: 'MERGEABLE',
          commitMessageHeadline: 'PR title',
          commitMessageBody: 'PR body',
        }

        const {user} = renderWithClient(<MergeSection defaultMergeMethod={MergeMethod.SQUASH} {...pullRequest} />)
        const mergeButton = screen.getByRole('button', {name: 'Squash and merge'})
        expect(mergeButton).toBeInTheDocument()
        await user.click(mergeButton)
        const confirmButton = screen.getByRole('button', {name: 'Confirm squash and merge'})
        expect(confirmButton).toBeInTheDocument()
        await user.click(confirmButton)

        await waitFor(() =>
          expectMockFetchCalledWith(mergeMutationRoute, {
            bypassBranchProtections: false,
            commitMessage: 'PR body',
            commitTitle: 'PR title',
            mergeMethod: 'SQUASH',
          }),
        )
      })

      test('when we select squash from the dropdown, we always pass in mergeMethod, commitMessage, commitTitle, and bypassBranchProtections', async () => {
        const mergeMutationRoute = `${BASE_PAGE_DATA_URL}/page_data/${PageData.merge}`
        const pullRequest: MergeSectionProps = {
          ...pullRequestWithDefaultMergeActionsAndMethods,
          mergeRequirementsState: 'MERGEABLE',
          commitMessageHeadline: 'PR title',
          commitMessageBody: 'PR body',
          possibleCommitAuthorEmails: [],
        }

        const {user} = renderWithClient(<MergeSection defaultMergeMethod={MergeMethod.MERGE} {...pullRequest} />)
        const defaultButton = screen.getByRole('button', {name: 'Merge pull request'})
        expect(defaultButton).toBeInTheDocument()

        const mergeButtonOptions = screen.getByRole('button', {name: 'Select merge method'})
        expect(mergeButtonOptions).toBeInTheDocument()
        await user.click(mergeButtonOptions)

        const squashCommitButton = screen.getByText('Squash and merge')
        expect(squashCommitButton).toBeInTheDocument()

        await user.click(squashCommitButton)

        const squashButton = screen.getByRole('button', {name: 'Squash and merge'})
        expect(squashButton).toBeInTheDocument()
        await user.click(squashButton)

        const confirmButton = screen.getByRole('button', {name: 'Confirm squash and merge'})
        expect(confirmButton).toBeInTheDocument()
        await user.click(confirmButton)

        await waitFor(() =>
          expectMockFetchCalledWith(mergeMutationRoute, {
            bypassBranchProtections: false,
            commitMessage: 'PR body',
            commitTitle: 'PR title',
            mergeMethod: 'SQUASH',
          }),
        )
      })
    })

    describe('commit data we pass in when user has multiple emails', () => {
      test('when squash is the default, we always pass in mergeMethod, commitMessage, commitTitle, authorEmail, and bypassBranchProtections', async () => {
        const mergeMutationRoute = `${BASE_PAGE_DATA_URL}/page_data/${PageData.merge}`
        const pullRequest: MergeSectionProps = {
          ...pullRequestWithDefaultMergeActionsAndMethods,
          mergeRequirementsState: 'MERGEABLE',
          commitMessageHeadline: 'PR title',
          commitMessageBody: 'PR body',
          defaultCommitAuthorEmail: 'test@github.com',
          possibleCommitAuthorEmails: ['mona@github.com', 'test@github.com', 'another@github.com'],
        }

        const {user} = renderWithClient(<MergeSection defaultMergeMethod={MergeMethod.SQUASH} {...pullRequest} />)
        const mergeButton = screen.getByRole('button', {name: 'Squash and merge'})
        expect(mergeButton).toBeInTheDocument()
        await user.click(mergeButton)
        const confirmButton = screen.getByRole('button', {name: 'Confirm squash and merge'})
        expect(confirmButton).toBeInTheDocument()
        await user.click(confirmButton)

        await waitFor(() =>
          expectMockFetchCalledWith(mergeMutationRoute, {
            bypassBranchProtections: false,
            commitMessage: 'PR body',
            commitTitle: 'PR title',
            mergeMethod: 'SQUASH',
            authorEmail: 'test@github.com',
          }),
        )
      })

      test('when merge is the default, we always pass in mergeMethod, commitMessage, commitTitle, authorEmail, and bypassBranchProtections', async () => {
        const mergeMutationRoute = `${BASE_PAGE_DATA_URL}/page_data/${PageData.merge}`
        const pullRequest: MergeSectionProps = {
          ...pullRequestWithDefaultMergeActionsAndMethods,
          mergeRequirementsState: 'MERGEABLE',
          commitMessageHeadline: 'PR title',
          commitMessageBody: 'PR body',
          defaultCommitAuthorEmail: 'test@github.com',
          possibleCommitAuthorEmails: ['mona@github.com', 'test@github.com', 'another@github.com'],
        }

        const {user} = renderWithClient(<MergeSection defaultMergeMethod={MergeMethod.MERGE} {...pullRequest} />)
        const mergeButton = screen.getByRole('button', {name: 'Merge pull request'})
        expect(mergeButton).toBeInTheDocument()
        await user.click(mergeButton)
        const confirmButton = screen.getByRole('button', {name: 'Confirm merge'})
        expect(confirmButton).toBeInTheDocument()
        await user.click(confirmButton)

        await waitFor(() =>
          expectMockFetchCalledWith(mergeMutationRoute, {
            authorEmail: 'test@github.com',
            bypassBranchProtections: false,
            commitMessage: 'PR body',
            commitTitle: 'PR title',
            mergeMethod: 'MERGE',
          }),
        )
      })
    })

    test('when merge fails, renders an error and focuses the header', async () => {
      const mergeMutationRoute = `${BASE_PAGE_DATA_URL}/page_data/${PageData.merge}`
      const pullRequest: MergeSectionProps = {
        ...pullRequestWithDefaultMergeActionsAndMethods,
        mergeRequirementsState: 'MERGEABLE',
        commitMessageHeadline: 'PR title',
        commitMessageBody: 'PR body',
      }
      const {user} = renderWithClient(<MergeSection defaultMergeMethod={MergeMethod.REBASE} {...pullRequest} />)

      const rebaseAndMergeButton = screen.getByRole('button', {name: 'Rebase and merge'})
      expect(rebaseAndMergeButton).toBeInTheDocument()
      await user.click(rebaseAndMergeButton)
      const confirmButton = screen.getByRole('button', {name: 'Confirm rebase and merge'})
      expect(confirmButton).toBeInTheDocument()

      await user.click(confirmButton)

      await screen.findAllByText('Merging...')

      assertButtonInLoadingState(confirmButton, 'Merging...')

      mockFetch.resolvePendingRequest(
        mergeMutationRoute,
        {error: 'Invalid email for web commit.'},
        {status: 422, ok: false},
      )

      const errorMessages = await screen.findAllByText('Invalid email for web commit.')
      // Intermittent test failures happen when we try to calculate an exact number; the aria-live region is
      // also updated, so we just check that there is at least one error message
      expect(errorMessages.length).toBeGreaterThan(0)
      // eslint-disable-next-line testing-library/no-node-access
      const announcements = document.querySelector('#js-global-screen-reader-notice') as HTMLDivElement
      await waitFor(() => expect(announcements.textContent).toEqual('Invalid email for web commit.'))
    })
  })

  describe('bypass merge requirements', () => {
    test('cannot bypass when there is a merge conflict', async () => {
      const pullRequest: MergeSectionProps = {
        ...pullRequestWithDefaultMergeActionsAndMethods,
        conflictsCondition: {
          result: 'FAILED',
        },
        viewerMergeActions: mockViewerMergeActions['directMergeWithBypassAllowed'],
      }
      renderWithClient(<MergeSection {...pullRequest} />)

      expect(
        screen.queryByText('Merge without waiting for requirements to be met (bypass rules)'),
      ).not.toBeInTheDocument()
      const primaryButton = screen.getByRole('button', {name: 'Merge pull request'})
      expect(primaryButton).toHaveAttribute('aria-disabled', 'true')
    })

    test('cannot bypass when the PR is in draft mode', async () => {
      const pullRequest: MergeSectionProps = {
        ...pullRequestWithDefaultMergeActionsAndMethods,
        isDraft: true,
        viewerMergeActions: mockViewerMergeActions['directMergeWithBypassAllowed'],
      }
      renderWithClient(<MergeSection {...pullRequest} />)

      expect(
        screen.queryByText('Merge without waiting for requirements to be met (bypass rules)'),
      ).not.toBeInTheDocument()
      const primaryButton = screen.getByRole('button', {name: 'Merge pull request'})
      expect(primaryButton).toHaveAttribute('aria-disabled', 'true')
    })

    test('cannot bypass when there is no merge conflict and user does not have permissions', async () => {
      const pullRequest: MergeSectionProps = {
        ...pullRequestWithDefaultMergeActionsAndMethods,
        mergeRequirementsState: 'UNMERGEABLE',
      }
      renderWithClient(<MergeSection {...pullRequest} />)

      expect(
        screen.queryByText('Merge without waiting for requirements to be met (bypass rules)'),
      ).not.toBeInTheDocument()

      const primaryButton = screen.getByRole('button', {name: 'Merge pull request'})
      expect(primaryButton).toHaveAttribute('aria-disabled', 'true')
    })

    test('does not show bypass checkbox when PR is mergeable', async () => {
      renderWithClient(<MergeSection {...pullRequestWithDefaultMergeActionsAndMethods} />)

      expect(
        screen.queryByText('Merge without waiting for requirements to be met (bypass rules)'),
      ).not.toBeInTheDocument()
    })

    test('does not show bypass checkbox when PR has an AutoMerge request', async () => {
      const pullRequest: MergeSectionProps = {
        ...pullRequestWithDefaultMergeActionsAndMethods,
        mergeRequirementsState: 'UNMERGEABLE',
        viewerCanAdminBypassMergeRequirements: true,
        autoMergeRequest: {
          mergeMethod: 'MERGE',
        },
        viewerCanDisableAutoMerge: true,
      }
      renderWithClient(<MergeSection {...pullRequest} />)

      expect(
        screen.queryByText('Merge without waiting for requirements to be met (bypass rules)'),
      ).not.toBeInTheDocument()
    })

    test('does not show bypass checkbox when PR is mergeable and user has ability to bypass', async () => {
      const pullRequest: MergeSectionProps = {
        ...pullRequestWithDefaultMergeActionsAndMethods,
        mergeRequirementsState: 'MERGEABLE',
        viewerMergeActions: mockViewerMergeActions['directMergeWithBypassAllowed'],
      }
      renderWithClient(<MergeSection {...pullRequest} />)

      expect(
        screen.queryByText('Merge without waiting for requirements to be met (bypass rules)'),
      ).not.toBeInTheDocument()
    })

    test('can bypass when the current merge method is blocked by default and user has permissions', async () => {
      const pullRequest: MergeSectionProps = {
        ...pullRequestWithDefaultMergeActionsAndMethods,
        mergeRequirementsState: 'UNMERGEABLE',
        viewerCanAdminBypassMergeRequirements: true,
        viewerMergeActions: [
          {
            name: MergeAction.DIRECT_MERGE,
            allowableStatus: 'ALLOWED',
            mergeMethods: [
              {
                name: MergeMethod.MERGE,
                allowableStatus: 'ALLOWED_WITH_BYPASS',
              },
              {
                name: MergeMethod.SQUASH,
                allowableStatus: 'ALLOWED',
              },
              {
                name: MergeMethod.REBASE,
                allowableStatus: 'ALLOWED',
              },
            ],
          },
        ],
      }

      const {user} = renderWithClient(<MergeSection {...pullRequest} />)

      const bypassCheckbox = screen.getByText('Merge without waiting for requirements to be met (bypass rules)')
      expect(bypassCheckbox).toBeVisible()

      const primaryButton = screen.getByRole('button', {name: 'Merge pull request'})
      expect(primaryButton).toHaveAttribute('aria-disabled', 'true')

      await user.click(bypassCheckbox)
      const bypassButton = screen.getByRole('button', {name: 'Bypass rules and merge'})
      expect(bypassButton).not.toHaveAttribute('aria-disabled', 'true')
    })

    test('can change merge method when the merge method is blocked and user has permissions for other merge methods', async () => {
      const pullRequest: MergeSectionProps = {
        ...pullRequestWithDefaultMergeActionsAndMethods,
        mergeRequirementsState: 'UNMERGEABLE',
        viewerMergeActions: [
          {
            name: MergeAction.DIRECT_MERGE,
            allowableStatus: 'ALLOWED',
            mergeMethods: [
              {
                name: MergeMethod.MERGE,
                allowableStatus: 'ALLOWED_WITH_BYPASS',
              },
              {
                name: MergeMethod.SQUASH,
                allowableStatus: 'ALLOWED',
              },
              {
                name: MergeMethod.REBASE,
                allowableStatus: 'ALLOWED',
              },
            ],
          },
        ],
      }
      const {user} = renderWithClient(<MergeSection {...pullRequest} />)

      const primaryButton = screen.getByRole('button', {name: 'Merge pull request'})
      expect(primaryButton).toHaveAttribute('aria-disabled', 'true')
      const mergeButtonOptions = screen.getByRole('button', {name: 'Select merge method'})
      expect(mergeButtonOptions).not.toHaveAttribute('aria-disabled', 'true')
      await user.click(mergeButtonOptions)

      expect(screen.getByText('Squash and merge')).toBeVisible()
    })

    test('when merge state is MERGEABLE_IF_STATUSES_PASS and is not mergeable, renders the bypass checkbox when user has the ability to bypass merge requirements', async () => {
      const pullRequest: MergeSectionProps = {
        ...pullRequestWithDefaultMergeActionsAndMethods,
        mergeRequirementsState: 'MERGEABLE_IF_STATUSES_PASS',
        viewerMergeActions: mockViewerMergeActions['directMergeWithBypassAllowed'],
        viewerCanAdminBypassMergeRequirements: true,
        status: Status.ChecksFailing,
      }

      const {user} = renderWithClient(<MergeSection {...pullRequest} />)

      const bypassCheckbox = screen.getByText('Merge without waiting for requirements to be met (bypass rules)')
      expect(bypassCheckbox).toBeVisible()
      await user.click(bypassCheckbox)

      const mergeButton = screen.getByRole('button', {name: 'Bypass rules and merge'})
      expect(mergeButton).toBeVisible()
    })

    test('when merge state is not mergeable, renders the bypass checkbox when user has the ability to bypass merge requirements', async () => {
      const pullRequest: MergeSectionProps = {
        ...pullRequestWithDefaultMergeActionsAndMethods,
        mergeRequirementsState: 'UNMERGEABLE',
        viewerMergeActions: mockViewerMergeActions['mergeQueueWithBypassAllowed'],
        viewerCanAdminBypassMergeRequirements: true,
      }

      const {user} = renderWithClient(<MergeSection {...pullRequest} />)

      const bypassCheckbox = screen.getByText('Merge without waiting for requirements to be met (bypass rules)')
      expect(bypassCheckbox).toBeVisible()
      await user.click(bypassCheckbox)

      const mergeButton = screen.getByRole('button', {name: 'Bypass rules and merge'})
      expect(mergeButton).toBeVisible()
    })

    test('with merge queue enabled and merge state is unmeargeable, renders bypass checkbox when user can bypass', async () => {
      const pullRequest: MergeSectionProps = {
        ...pullRequestWithDefaultMergeActionsAndMethods,
        mergeRequirementsState: 'UNMERGEABLE',
        viewerMergeActions: mockViewerMergeActions['mergeQueueWithBypassAllowed'],
        viewerCanAdminBypassMergeRequirements: true,
      }

      const {user} = renderWithClient(<MergeSection {...pullRequest} />)

      const bypassCheckbox = screen.getByText('Merge without waiting for requirements to be met (bypass rules)')
      expect(bypassCheckbox).toBeVisible()
      await user.click(bypassCheckbox)

      const mergeButton = screen.getByRole('button', {name: 'Bypass rules and merge'})
      expect(mergeButton).toBeVisible()

      await user.click(mergeButton)
      expect(screen.getByRole('button', {name: 'Confirm bypass rules and merge'})).toBeVisible()
    })

    test('with merge queue enabled and bypass toggle checked, user can select a different merge method and bypass merge queue', async () => {
      const pullRequest: MergeSectionProps = {
        ...pullRequestWithDefaultMergeActionsAndMethods,
        mergeRequirementsState: 'UNMERGEABLE',
        viewerMergeActions: mockViewerMergeActions['mergeQueueWithBypassAllowed'],
        viewerCanAdminBypassMergeRequirements: true,
      }

      const {user} = renderWithClient(<MergeSection {...pullRequest} />)

      const bypassCheckbox = screen.getByText('Merge without waiting for requirements to be met (bypass rules)')
      expect(bypassCheckbox).toBeVisible()
      await user.click(bypassCheckbox)

      const mergeButton = screen.getByRole('button', {name: 'Bypass rules and merge'})
      expect(mergeButton).toBeVisible()

      const selectMergeMethodButton = screen.getByRole('button', {name: 'Select merge method'})
      expect(selectMergeMethodButton).toBeVisible()
      await user.click(selectMergeMethodButton)

      const squashAndMergeOption = screen.getByText('Squash and merge')
      await user.click(squashAndMergeOption)

      expect(screen.getByRole('button', {name: 'Bypass rules and merge (squash)'})).toBeVisible()
    })

    test('with merge queue enabled and merge state is mergeable, renders the bypass check box when user has ability to bypass merge requirements', async () => {
      const pullRequest: MergeSectionProps = {
        ...pullRequestWithDefaultMergeActionsAndMethods,
        mergeRequirementsState: 'MERGEABLE',
        viewerMergeActions: mockViewerMergeActions['mergeQueueWithBypassAllowed'],
        viewerCanAdminBypassMergeRequirements: true,
      }

      const {user} = renderWithClient(<MergeSection {...pullRequest} />)

      const bypassCheckbox = screen.getByText('Merge without waiting for requirements to be met (bypass rules)')
      expect(bypassCheckbox).toBeVisible()
      await user.click(bypassCheckbox)

      const mergeButton = screen.getByRole('button', {name: 'Bypass rules and merge'})
      expect(mergeButton).toBeVisible()
    })

    test('with merge queue enabled and merge state is mergeable if statuses pass, renders the bypass check box when user has ability to bypass merge requirements', async () => {
      const pullRequest: MergeSectionProps = {
        ...pullRequestWithDefaultMergeActionsAndMethods,
        mergeRequirementsState: 'MERGEABLE_IF_STATUSES_PASS',
        viewerMergeActions: mockViewerMergeActions['mergeQueueWithBypassAllowed'],
        viewerCanAdminBypassMergeRequirements: true,
      }

      const {user} = renderWithClient(<MergeSection {...pullRequest} />)

      const bypassCheckbox = screen.getByText('Merge without waiting for requirements to be met (bypass rules)')
      expect(bypassCheckbox).toBeVisible()
      await user.click(bypassCheckbox)

      const mergeButton = screen.getByRole('button', {name: 'Bypass rules and merge'})
      expect(mergeButton).toBeVisible()
    })

    test('with merge queue enabled and merge state is mergeable if statuses pass, it does not render the bypass check box when user lacks ability to bypass merge requirements', async () => {
      const pullRequest: MergeSectionProps = {
        ...pullRequestWithDefaultMergeActionsAndMethods,
        mergeRequirementsState: 'MERGEABLE_IF_STATUSES_PASS',
        viewerCanAdminBypassMergeRequirements: false,
      }

      renderWithClient(<MergeSection {...pullRequest} />)

      expect(
        screen.queryByText('Merge without waiting for requirements to be met (bypass rules)'),
      ).not.toBeInTheDocument()
    })

    test('with merge queue enabled and merge state is mergeable, it does not render the bypass check box when user lacks ability to bypass merge requirements', async () => {
      const pullRequest: MergeSectionProps = {
        ...pullRequestWithDefaultMergeActionsAndMethods,
        mergeRequirementsState: 'MERGEABLE',
        viewerCanAdminBypassMergeRequirements: false,
      }

      renderWithClient(<MergeSection {...pullRequest} />)

      expect(
        screen.queryByText('Merge without waiting for requirements to be met (bypass rules)'),
      ).not.toBeInTheDocument()
    })

    test('with merge queue enabled, does not render DirectMergeActionsSection when the bypass toggle checkbox is unchecked', async () => {
      const pullRequest: MergeSectionProps = {
        ...pullRequestWithDefaultMergeActionsAndMethods,
        mergeRequirementsState: 'UNMERGEABLE',
        viewerMergeActions: mockViewerMergeActions['mergeQueueWithBypassAllowed'],
        viewerCanAdminBypassMergeRequirements: true,
      }

      renderWithClient(<MergeSection {...pullRequest} />)

      const bypassCheckbox = screen.getByText('Merge without waiting for requirements to be met (bypass rules)')
      expect(bypassCheckbox).toBeVisible()
      expect(screen.queryByRole('button', {name: 'Bypass rules and merge'})).not.toBeInTheDocument()
    })

    test('When :merge_box_hide_sections feature is disabled,the bypass checkbox is hidden while the user is confirming the merge', async () => {
      const pullRequest: MergeSectionProps = {
        ...pullRequestWithDefaultMergeActionsAndMethods,
        mergeRequirementsState: 'UNMERGEABLE',
        viewerMergeActions: mockViewerMergeActions['mergeQueueWithBypassAllowed'],
        viewerCanAdminBypassMergeRequirements: true,
      }

      const {user} = renderWithClient(
        <MergeSection {...pullRequest} enabledFeatures={{merge_box_hide_sections: false}} />,
      )

      await user.click(screen.getByText('Merge without waiting for requirements to be met (bypass rules)'))
      await user.click(screen.getByRole('button', {name: 'Bypass rules and merge'}))

      expect(
        screen.queryByText('Merge without waiting for requirements to be met (bypass rules)'),
      ).not.toBeInTheDocument()

      expect(screen.getByRole('button', {name: 'Confirm bypass rules and merge'})).toBeVisible()

      await user.click(screen.getByRole('button', {name: 'Cancel'}))

      expect(screen.getByText('Merge without waiting for requirements to be met (bypass rules)')).toBeInTheDocument()
      expect(screen.getByRole('button', {name: 'Bypass rules and merge'})).toBeInTheDocument()
      expect(screen.queryByRole('button', {name: 'Confirm bypass rules and merge'})).not.toBeInTheDocument()
    })

    test('When :merge_box_hide_sections feature is enabled, the bypass checkbox is hidden while the user is confirming the merge, when feature', async () => {
      const pullRequest: MergeSectionProps = {
        ...pullRequestWithDefaultMergeActionsAndMethods,
        mergeRequirementsState: 'UNMERGEABLE',
        viewerMergeActions: mockViewerMergeActions['mergeQueueWithBypassAllowed'],
        viewerCanAdminBypassMergeRequirements: true,
      }

      const {user} = renderWithClient(
        <MergeSection {...pullRequest} enabledFeatures={{merge_box_hide_sections: true}} />,
      )

      await user.click(screen.getByText('Merge without waiting for requirements to be met (bypass rules)'))
      await user.click(screen.getByRole('button', {name: 'Bypass rules and merge'}))

      expect(
        screen.queryByText('Merge without waiting for requirements to be met (bypass rules)'),
      ).not.toBeInTheDocument()

      expect(screen.getByRole('button', {name: 'Confirm bypass rules and merge'})).toBeVisible()

      await user.click(screen.getByRole('button', {name: 'Cancel'}))

      expect(screen.getByText('Merge without waiting for requirements to be met (bypass rules)')).toBeInTheDocument()
      expect(screen.getByRole('button', {name: 'Bypass rules and merge'})).toBeInTheDocument()
      expect(screen.queryByRole('button', {name: 'Confirm bypass rules and merge'})).not.toBeInTheDocument()
    })
  })

  test('the bypass checkbox is shown if mergeStateStatus is behind, and current user is admin', async () => {
    const pullRequest: MergeSectionProps = {
      ...pullRequestWithDefaultMergeActionsAndMethods,
      mergeStateStatus: 'BEHIND',
      mergeRequirementsState: 'MERGEABLE_IF_STATUSES_PASS',
      viewerCanAdminBypassMergeRequirements: true,
    }

    renderWithClient(<MergeSection {...pullRequest} />)

    expect(screen.getByText('Merge without waiting for requirements to be met (bypass rules)')).toBeInTheDocument()
  })
})
