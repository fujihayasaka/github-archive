import {screen, act, waitFor} from '@testing-library/react'
import {renderRelay} from '@github-ui/relay-test-utils'
import {ThemeProvider} from '@primer/react'
import type {RepositoryPickerCurrentRepoQuery} from '@github-ui/item-picker/RepositoryPickerCurrentRepoQuery.graphql'
import PRELOAD_CURRENT_REPOSITORY_QUERY from '@github-ui/item-picker/RepositoryPickerCurrentRepoQuery.graphql'
import {RelationshipsSection, RelationshipsSectionGraphqlQuery} from '../relations-section/RelationshipsSection'
import type {RelationshipsSectionQuery} from '../relations-section/__generated__/RelationshipsSectionQuery.graphql'
import {useFeatureFlags} from '@github-ui/react-core/use-feature-flag'
import type {DependenciesPickerBlockingBlockedByIssuesQuery} from '../relations-section/__generated__/DependenciesPickerBlockingBlockedByIssuesQuery.graphql'
import {TopRepositories} from '@github-ui/item-picker/RepositoryPicker'
import type {RepositoryPickerTopRepositoriesQuery} from '@github-ui/item-picker/RepositoryPickerTopRepositoriesQuery.graphql'
import type {useIssueFilteringQuery} from '@github-ui/item-picker/useIssueFilteringQuery.graphql'
import {MockPayloadGenerator} from 'relay-test-utils'
import {LABELS} from '../../../constants/labels'
import {noop} from '@github-ui/noop'
import {requestSubscription, graphql} from 'relay-runtime'
import type {RelayMockEnvironment} from 'relay-test-utils/lib/RelayModernMockEnvironment'
import {isStaff} from '@github-ui/stats'

// mocks
const sendAnalyticsEvent = jest.fn().mockName('sendAnalyticsEvent')
jest.mock('@github-ui/use-analytics', () => ({
  useAnalytics: () => ({sendAnalyticsEvent}),
}))

jest.mock('@github-ui/react-core/use-feature-flag')
const mockUseFeatureFlag = jest.mocked(useFeatureFlags).mockReturnValue({})

// Mock isStaff function
jest.mock('@github-ui/stats', () => ({
  isStaff: jest.fn().mockReturnValue(false),
}))

const mockIssueViewerSubscription = (environment: RelayMockEnvironment) => {
  requestSubscription(environment, {
    subscription: graphql`
      subscription RelationshipsSectionDependenciesSubscription_IssueViewerSubscription($id: ID!)
      @relay_test_operation {
        issueUpdated(id: $id) {
          issueDependenciesSummaryUpdated {
            ...RelationshipsSectionFragment
          }
        }
      }
    `,
    onNext: noop,
    onError: noop,
    variables: {id: ISSUE.id},
  })

  return environment.mock.getMostRecentOperation()
}

// consts
const OWNER = {
  __typename: 'RepositoryOwner',
  id: 'org',
  login: 'org',
}

const REPO = {
  id: 'repo',
  name: 'repo',
  isArchived: false,
  isPrivate: false,
  owner: OWNER,
  nameWithOwner: `${OWNER.login}/repo`,
}

const ISSUE = {
  id: 'issue',
  databaseId: 1,
  number: 1,
  parent: null,
  topBlockedBy: null,
  topBlocking: null,
  blockedBy: {nodes: []},
  blocking: {nodes: []},
  title: 'issue',
  titleHTML: 'issue',
  viewerCanUpdateMetadata: true,
  repository: REPO,
}

const OTHER_ISSUE = {
  id: 'other-issue',
  number: 2,
  title: 'other issue',
  titleHtml: 'other issue',
  repository: REPO,
}

// types
type DependencyResponse = {
  nodes: Array<Record<string, unknown>>
  pageInfo?: {
    hasNextPage: boolean
  }
}

type Mock = {
  blockedBy?: DependencyResponse
  blocking?: DependencyResponse
  usePickerQueries?: boolean
}

type RelayQueries = {
  preloadCurrentRepositoryQuery: RepositoryPickerCurrentRepoQuery
  topRepositories: RepositoryPickerTopRepositoriesQuery
  relationsSectionQuery: RelationshipsSectionQuery
}

type RelayQueriesWithLazy = RelayQueries & {
  dependenciesPickerBlockingBlockedByIssuesQuery: DependenciesPickerBlockingBlockedByIssuesQuery
  useIssueFilteringQueryGraphQLQuery: useIssueFilteringQuery
}

function setupEnvironment({blockedBy, blocking, usePickerQueries}: Mock = {}) {
  sendAnalyticsEvent.mockReset()

  // In tests where we don't trigger the picker, the lazy picker queries never get resolved.
  // This can lead to problems if trying to manually queue other operations, such as subscriptions or mutations.
  // Only include these via usePickerQueries if the test requires opening the picker.
  const lazyQueries = usePickerQueries
    ? {
        useIssueFilteringQueryGraphQLQuery: {
          type: 'lazy',
        },
        dependenciesPickerBlockingBlockedByIssuesQuery: {
          type: 'lazy',
        },
      }
    : {}

  const {relayMockEnvironment, user} = renderRelay<RelayQueries | RelayQueriesWithLazy>(
    ({queryRefs: {relationsSectionQuery}}) => (
      <ThemeProvider>
        <RelationshipsSection queryRef={relationsSectionQuery} />
      </ThemeProvider>
    ),
    {
      relay: {
        queries: {
          preloadCurrentRepositoryQuery: {
            type: 'preloaded',
            query: PRELOAD_CURRENT_REPOSITORY_QUERY,
            variables: {owner: OWNER.login, name: REPO.name},
          },
          topRepositories: {
            type: 'preloaded',
            query: TopRepositories,
            variables: {topRepositoriesFirst: 5, hasIssuesEnabled: true, owner: null},
          },
          relationsSectionQuery: {
            type: 'preloaded',
            query: RelationshipsSectionGraphqlQuery,
            variables: {owner: OWNER.login, repo: REPO.name, number: ISSUE.number},
          },
          ...lazyQueries,
        },
        mockResolvers: {
          RepositoryConnection() {
            return {
              edges: [],
            }
          },
          Repository() {
            return REPO
          },
          Issue({path, args}) {
            // Responds to the query for the dependency issue picker
            if (path?.includes('commenters')) {
              return OTHER_ISSUE
            }
            // Responds to query for currently configured blockedBy issues
            if (path?.includes('topBlockedBy') || path?.includes('blockedBy')) {
              return getDependencyMockFromArray(path, blockedBy?.nodes)
            }
            // Responds to query for currently configured blocking issues
            if (path?.includes('topBlocking') || path?.includes('blocking')) {
              return getDependencyMockFromArray(path, blocking?.nodes)
            }
            // Responds to the query for the issue being viewed
            if (args?.number === ISSUE.number || !args?.number) {
              return {
                ...ISSUE,
                topBlockedBy: blockedBy ? {pageInfo: {hasNextPage: false}, ...blockedBy} : null,
                topBlocking: blocking ? {pageInfo: {hasNextPage: false}, ...blocking} : null,
                blockedBy: blockedBy || {nodes: []},
                blocking: blocking || {nodes: []},
                issueDependenciesSummary: {
                  blockedBy: blockedBy?.nodes?.length || 0,
                  blocking: blocking?.nodes?.length || 0,
                },
              }
            }
          },
        },
      },
    },
  )

  return {environment: relayMockEnvironment, user}
}

function getDependencyMockFromArray(path: readonly string[], array: Array<Record<string, unknown>> | undefined) {
  const lastPathItem = path[path.length - 1]
  if (!lastPathItem) return null
  const index = parseInt(lastPathItem, 10)
  if (!array?.[index]) {
    return null
  }
  return {
    id: array[index].id,
    title: array[index].title,
    titleHTML: array[index].titleHTML || array[index].title,
  }
}

test('renders nothing when blocked and blocking are present but flag is false', async () => {
  mockUseFeatureFlag.mockReturnValue({issue_dependencies: false})
  setupEnvironment({
    blockedBy: {
      nodes: [
        {id: 'blocked-1', title: 'Blocked Issue 1'},
        {id: 'blocked-2', title: 'Blocked Issue 2'},
      ],
    },
    blocking: {
      nodes: [
        {id: 'blocked-1', title: 'Blocked Issue 1'},
        {id: 'blocked-2', title: 'Blocked Issue 2'},
      ],
    },
  })

  expect(await screen.findByText(LABELS.sectionTitles.relationships)).toBeInTheDocument()
  expect(screen.queryByText(LABELS.relationNames.blockedByIssues)).not.toBeInTheDocument()
  expect(screen.queryByText(LABELS.relationNames.blockingIssues)).not.toBeInTheDocument()
})

test('renders blockedBy issues when present', async () => {
  mockUseFeatureFlag.mockReturnValue({issue_dependencies: true})
  setupEnvironment({
    blockedBy: {
      nodes: [
        {id: 'blocked-1', title: 'Blocked Issue 1'},
        {id: 'blocked-2', title: 'Blocked Issue 2'},
      ],
    },
  })

  expect(await screen.findByText(LABELS.sectionTitles.relationships)).toBeInTheDocument()
  expect(await screen.findByText(LABELS.relationNames.blockedByIssues)).toBeInTheDocument()
  expect(screen.queryByText(LABELS.relationNames.blockingIssues)).not.toBeInTheDocument()
  expect(await screen.findByText('Blocked Issue 1')).toBeInTheDocument()
  expect(await screen.findByText('Blocked Issue 2')).toBeInTheDocument()
})

test('renders blockedBy issues with View all button when hasNextPage is true for related blockedBy issues', async () => {
  mockUseFeatureFlag.mockReturnValue({issue_dependencies: true})
  setupEnvironment({
    blockedBy: {
      nodes: [
        {id: 'blocked-1', title: 'Blocked Issue 1'},
        {id: 'blocked-2', title: 'Blocked Issue 2'},
        {id: 'blocked-3', title: 'Blocked Issue 3'},
        {id: 'blocked-4', title: 'Blocked Issue 4'},
      ],
      pageInfo: {hasNextPage: true},
    },
  })

  expect(await screen.findByText(LABELS.sectionTitles.relationships)).toBeInTheDocument()
  expect(await screen.findByText(LABELS.relationNames.blockedByIssues)).toBeInTheDocument()
  expect(await screen.findByText(LABELS.relationViewAll)).toBeInTheDocument()
})

test('renders blockedBy issues does NOT include View all button when hasNextPage is false for related blockedBy issues', async () => {
  mockUseFeatureFlag.mockReturnValue({issue_dependencies: true})
  setupEnvironment({
    blockedBy: {
      nodes: [{id: 'blocked-1', title: 'Blocked Issue 1'}],
      pageInfo: {hasNextPage: false},
    },
  })

  expect(await screen.findByText(LABELS.sectionTitles.relationships)).toBeInTheDocument()
  expect(await screen.findByText(LABELS.relationNames.blockedByIssues)).toBeInTheDocument()
  expect(screen.queryByText(LABELS.relationViewAll)).not.toBeInTheDocument()
})

test('renders blocking issues when present', async () => {
  setupEnvironment({
    blocking: {
      nodes: [
        {id: 'blocking-1', title: 'Blocking Issue 1'},
        {id: 'blocking-2', title: 'Blocking Issue 2'},
      ],
    },
  })

  expect(await screen.findByText(LABELS.sectionTitles.relationships)).toBeInTheDocument()
  expect(await screen.findByText(LABELS.relationNames.blockingIssues)).toBeInTheDocument()
  expect(screen.queryByText(LABELS.relationNames.blockedByIssues)).not.toBeInTheDocument()
  expect(await screen.findByText('Blocking Issue 1')).toBeInTheDocument()
  expect(await screen.findByText('Blocking Issue 2')).toBeInTheDocument()
})

test('renders blocking issues with View all button when hasNextPage is true for related blocking issues', async () => {
  mockUseFeatureFlag.mockReturnValue({issue_dependencies: true})
  setupEnvironment({
    blocking: {
      nodes: [
        {id: 'blocking-1', title: 'Blocking Issue 1'},
        {id: 'blocking-2', title: 'Blocking Issue 2'},
        {id: 'blocking-3', title: 'Blocking Issue 3'},
        {id: 'blocking-4', title: 'Blocking Issue 4'},
      ],
      pageInfo: {hasNextPage: true},
    },
  })

  expect(await screen.findByText(LABELS.sectionTitles.relationships)).toBeInTheDocument()
  expect(await screen.findByText(LABELS.relationNames.blockingIssues)).toBeInTheDocument()
  expect(await screen.findByText(LABELS.relationViewAll)).toBeInTheDocument()
})

test('renders blocking issues does NOT include View all button when hasNextPage is false for related blocking issues', async () => {
  mockUseFeatureFlag.mockReturnValue({issue_dependencies: true})
  setupEnvironment({
    blocking: {
      nodes: [{id: 'blocking-1', title: 'Blocking Issue 1'}],
      pageInfo: {hasNextPage: false},
    },
  })

  expect(await screen.findByText(LABELS.sectionTitles.relationships)).toBeInTheDocument()
  expect(await screen.findByText(LABELS.relationNames.blockingIssues)).toBeInTheDocument()
  expect(screen.queryByText(LABELS.relationViewAll)).not.toBeInTheDocument()
})

test('can open dependencies picker and switch between issue and repository pickers', async () => {
  mockUseFeatureFlag.mockReturnValue({issue_dependencies: true})
  const {user} = setupEnvironment({
    blockedBy: {
      nodes: [{id: 'blocked-1', title: 'Blocked Issue 1'}],
    },
  })

  // Open the relationships menu
  await act(async () => {
    await user.click(await screen.findByRole('button', {name: 'Edit Relationships'}))
  })

  // Open the dependencies picker (simulate command or menu click)
  await act(async () => {
    await user.click(await screen.findByLabelText('Change blocked by'))
  })

  await waitFor(() => {
    const listItems = screen.queryAllByRole('option').filter(item => item.getAttribute('data-id') !== 'no-results')
    expect(listItems).toHaveLength(0)
  })
  const backButton = await screen.findByRole('button', {name: 'Back to repository selection'})
  expect(backButton).toBeInTheDocument()

  await user.click(backButton)

  expect(await screen.findByRole('heading', {name: 'Select a repository'})).toBeInTheDocument()

  const repoOptions = await screen.findAllByRole('option')
  expect(repoOptions).toHaveLength(1)

  await user.click(repoOptions[0] as HTMLElement)

  await waitFor(() => {
    expect(screen.getByRole('button', {name: 'Back to repository selection'})).toBeInTheDocument()
  })
})

test('can add a blocked by by selecting an issue in the Edit Relationships picker', async () => {
  mockUseFeatureFlag.mockReturnValue({issue_dependencies: true})
  const {user, environment} = setupEnvironment({usePickerQueries: true})

  // Open the relationships menu
  await act(async () => {
    await user.click(await screen.findByRole('button', {name: 'Edit Relationships'}))
  })

  // Open the dependencies picker (simulate command or menu click)
  await act(async () => {
    await user.click(await screen.findByLabelText('Mark as blocked by'))
  })

  // Wait for the options to appear
  await waitFor(() => {
    const listItems = screen.getAllByRole('option').filter(item => item.getAttribute('data-id') !== 'no-results')
    expect(listItems).toHaveLength(1)
  })

  // Select the first (and only) option to add as blocked by
  const option = screen.getByRole('option', {name: `${OTHER_ISSUE.title} #${OTHER_ISSUE.number}`})
  await user.click(option)

  await act(async () => {
    await user.keyboard('{Escape}')
  })

  expect(sendAnalyticsEvent).toHaveBeenCalledWith(
    'issue_viewer.dependencies_picker.blocked_by',
    'ISSUE_DEPENDENCIES_PICKER',
    {issuesToAdd: 1, issuesToRemove: 0},
  )

  act(() => {
    environment.mock.resolveMostRecentOperation(operation => {
      expect(operation.fragment.node.name).toEqual('addBlockedByMutation')
      expect(operation.fragment.variables.input.issueId).toEqual(ISSUE.id)
      expect(operation.fragment.variables.input.blockingIssueId).toEqual(OTHER_ISSUE.id)
      return MockPayloadGenerator.generate(operation)
    })
  })
})

test('can remove a blocked by by selecting an issue in the Edit Relationships picker', async () => {
  mockUseFeatureFlag.mockReturnValue({issue_dependencies: true})
  const {user, environment} = setupEnvironment({
    blockedBy: {
      nodes: [{id: 'blocked-1', title: 'Blocked Issue 1'}],
    },
    usePickerQueries: true,
  })

  // Open the relationships menu
  await act(async () => {
    await user.click(await screen.findByRole('button', {name: 'Edit Relationships'}))
  })

  // Open the dependencies picker (simulate command or menu click)
  await act(async () => {
    await user.click(await screen.findByLabelText('Change blocked by'))
  })

  // Wait for the options to appear
  await waitFor(() => {
    const listItems = screen.getAllByRole('option').filter(item => item.getAttribute('data-id') !== 'no-results')
    expect(listItems).toHaveLength(1)
  })

  // Select the first (and only) option to add as blocked by
  const option = screen.getByRole('option', {name: `${OTHER_ISSUE.title} #${OTHER_ISSUE.number}`})
  await user.click(option)

  await act(async () => {
    await user.keyboard('{Escape}')
  })

  expect(sendAnalyticsEvent).toHaveBeenCalledWith(
    'issue_viewer.dependencies_picker.blocked_by',
    'ISSUE_DEPENDENCIES_PICKER',
    {issuesToAdd: 1, issuesToRemove: 1},
  )

  // Since the blocked-1 issue is already selected, it gets removed since it is diffed out of the onIssueSelection logic
  act(() => {
    environment.mock.resolveMostRecentOperation(operation => {
      expect(operation.fragment.node.name).toEqual('removeBlockedByMutation')
      expect(operation.fragment.variables.input.issueId).toEqual(ISSUE.id)
      expect(operation.fragment.variables.input.blockingIssueId).toEqual('blocked-1')
      return MockPayloadGenerator.generate(operation)
    })
  })
})

test('can add a blocking dependency by selecting an issue in the Edit Relationships picker', async () => {
  mockUseFeatureFlag.mockReturnValue({issue_dependencies: true})
  const {user, environment} = setupEnvironment({usePickerQueries: true})

  // Open the relationships menu
  await act(async () => {
    await user.click(await screen.findByRole('button', {name: 'Edit Relationships'}))
  })

  // Open the dependencies picker (simulate command or menu click)
  await act(async () => {
    await user.click(await screen.findByLabelText('Mark as blocking'))
  })

  // Wait for the options to appear
  await waitFor(() => {
    const listItems = screen.getAllByRole('option').filter(item => item.getAttribute('data-id') !== 'no-results')
    expect(listItems).toHaveLength(1)
  })

  // Select the first (and only) option to add as blocked by
  const option = screen.getByRole('option', {name: `${OTHER_ISSUE.title} #${OTHER_ISSUE.number}`})
  await user.click(option)

  await act(async () => {
    await user.keyboard('{Escape}')
  })

  expect(sendAnalyticsEvent).toHaveBeenCalledWith(
    'issue_viewer.dependencies_picker.blocking',
    'ISSUE_DEPENDENCIES_PICKER',
    {issuesToAdd: 1, issuesToRemove: 0},
  )

  act(() => {
    environment.mock.resolveMostRecentOperation(operation => {
      expect(operation.fragment.node.name).toEqual('addBlockedByMutation')
      expect(operation.fragment.variables.input.issueId).toEqual(OTHER_ISSUE.id)
      expect(operation.fragment.variables.input.blockingIssueId).toEqual(ISSUE.id)
      return MockPayloadGenerator.generate(operation)
    })
  })
})

test('can remove a blocking dependency by selecting an issue in the Edit Relationships picker', async () => {
  mockUseFeatureFlag.mockReturnValue({issue_dependencies: true})
  const {user, environment} = setupEnvironment({
    blocking: {
      nodes: [{id: 'blocking-1', title: 'Blocking Issue 1'}],
    },
    usePickerQueries: true,
  })

  // Open the relationships menu
  await act(async () => {
    await user.click(await screen.findByRole('button', {name: 'Edit Relationships'}))
  })

  // Open the dependencies picker (simulate command or menu click)
  await act(async () => {
    await user.click(await screen.findByLabelText('Change blocking'))
  })

  // Wait for the options to appear
  await waitFor(() => {
    const listItems = screen.getAllByRole('option').filter(item => item.getAttribute('data-id') !== 'no-results')
    expect(listItems).toHaveLength(1)
  })

  // Select the first (and only) option to remove as blocking
  const option = screen.getByRole('option', {name: `${OTHER_ISSUE.title} #${OTHER_ISSUE.number}`})
  await user.click(option)

  await act(async () => {
    await user.keyboard('{Escape}')
  })

  expect(sendAnalyticsEvent).toHaveBeenCalledWith(
    'issue_viewer.dependencies_picker.blocking',
    'ISSUE_DEPENDENCIES_PICKER',
    {issuesToAdd: 1, issuesToRemove: 1},
  )

  // Since the blocking-1 issue is already selected, it gets removed since it is diffed out of the onIssueSelection logic
  act(() => {
    environment.mock.resolveMostRecentOperation(operation => {
      expect(operation.fragment.node.name).toEqual('removeBlockedByMutation')
      expect(operation.fragment.variables.input.issueId).toEqual('blocking-1')
      expect(operation.fragment.variables.input.blockingIssueId).toEqual(ISSUE.id)
      return MockPayloadGenerator.generate(operation)
    })
  })
})

test('renders errors when addition and removal fails', async () => {
  mockUseFeatureFlag.mockReturnValue({issue_dependencies: true})
  const {user, environment} = setupEnvironment({
    blockedBy: {
      nodes: [{id: 'blocked-1', title: 'Blocked Issue 1'}],
    },
    usePickerQueries: true,
  })

  // Open the relationships menu
  await act(async () => {
    await user.click(await screen.findByRole('button', {name: 'Edit Relationships'}))
  })

  // Open the dependencies picker (simulate command or menu click)
  await act(async () => {
    await user.click(await screen.findByLabelText('Change blocked by'))
  })

  // Wait for the options to appear
  await waitFor(() => {
    const listItems = screen.getAllByRole('option').filter(item => item.getAttribute('data-id') !== 'no-results')
    expect(listItems).toHaveLength(1)
  })

  // Select the first (and only) option to add as blocked by
  const option = screen.getByRole('option', {name: `${OTHER_ISSUE.title} #${OTHER_ISSUE.number}`})
  await user.click(option)

  const MockError = new Error('Generic error')

  await act(async () => {
    await user.keyboard('{Escape}')
  })

  await act(async () => {
    environment.mock.rejectMostRecentOperation(() => {
      return MockError
    })
  })

  // Alert dialog not appear when only one error has resolved
  expect(screen.queryByText(/Failed to save \d issues/)).not.toBeInTheDocument()

  const MockPermissionsError = new Error('does not have the correct permissions to execute')
  await act(async () => {
    environment.mock.rejectMostRecentOperation(() => {
      return MockPermissionsError
    })
  })

  expect(screen.getByText(/Failed to save 2 issues/)).toBeInTheDocument()
  expect(screen.getByLabelText('Unexpected error')).toBeInTheDocument()
  expect(screen.getByLabelText('Access denied')).toBeInTheDocument()
})

test('should only have one menu open at a time', async () => {
  mockUseFeatureFlag.mockReturnValue({issue_dependencies: true})
  const {user} = setupEnvironment({
    blockedBy: {
      nodes: [{id: 'blocked-1', title: 'Blocked Issue 1'}],
    },
    usePickerQueries: true,
  })

  // Open the relationships menu
  await act(async () => {
    await user.click(await screen.findByRole('button', {name: 'Edit Relationships'}))
  })

  // Open the dependencies picker (simulate command or menu click)
  await act(async () => {
    await user.click(await screen.findByLabelText('Change blocked by'))
  })

  // Wait for the options to appear
  await waitFor(() => {
    const listItems = screen.getAllByRole('option').filter(item => item.getAttribute('data-id') !== 'no-results')
    expect(listItems).toHaveLength(1)
  })

  // Open the relationships menu
  await act(async () => {
    await user.click(await screen.findByRole('button', {name: 'Edit Relationships'}))
  })

  // Expect the dependencies picker to be closed
  await waitFor(() => {
    const listItems = screen.queryAllByRole('option').filter(item => item.getAttribute('data-id') !== 'no-results')
    expect(listItems).toHaveLength(0)
  })
})

test('should open blocked by menu by keyboard shortcut', async () => {
  mockUseFeatureFlag.mockReturnValue({issue_dependencies: true})
  const {user} = setupEnvironment({usePickerQueries: true})

  await act(async () => {
    await user.keyboard('bb')
  })

  expect(await screen.findByText(/Mark current issue as blocked by/)).toBeInTheDocument()
})

test('should open blocking menu by keyboard shortcut', async () => {
  mockUseFeatureFlag.mockReturnValue({issue_dependencies: true})
  const {user} = setupEnvironment({usePickerQueries: true})

  await act(async () => {
    await user.keyboard('bx')
  })

  expect(await screen.findByText(/Mark current issue as blocking/)).toBeInTheDocument()
})

test('live updates when summary is updated', async () => {
  mockUseFeatureFlag.mockReturnValue({issue_dependencies: true})
  const nodes = [
    {id: 'blocked-1', title: 'Blocked Issue 1'},
    {id: 'blocked-2', title: 'Blocked Issue 2'},
  ]
  const {environment} = setupEnvironment({
    blockedBy: {
      nodes: [nodes[0]!],
    },
  })

  expect(await screen.findByText('Blocked Issue 1')).toBeInTheDocument()
  expect(screen.queryByText('Blocked Issue 2')).not.toBeInTheDocument()

  const subscriptionOperation = mockIssueViewerSubscription(environment)
  act(() => {
    expect(subscriptionOperation.request.node.operation.name).toBe(
      'RelationshipsSectionDependenciesSubscription_IssueViewerSubscription',
    )
    environment.mock.nextValue(
      subscriptionOperation,
      MockPayloadGenerator.generate(subscriptionOperation, {
        Issue: ({path, args}) => {
          // Responds to query for currently configured blockedBy issues
          if (path?.includes('topBlockedBy') || path?.includes('blockedBy')) {
            return getDependencyMockFromArray(path, nodes)
          }
          // Responds to query for currently configured blocking issues
          if (path?.includes('topBlocking') || path?.includes('blocking')) {
            return getDependencyMockFromArray(path, [])
          }
          // Responds to the query for the issue being viewed
          if (args?.number === ISSUE.number || !args?.number) {
            return {
              ...ISSUE,
              topBlockedBy: {
                pageInfo: {hasNextPage: false},
                nodes,
              },
              blockedBy: {
                nodes,
              },
            }
          }
        },
      }),
    )
  })

  expect(await screen.findByText('Blocked Issue 1')).toBeInTheDocument()
  expect(await screen.findByText('Blocked Issue 2')).toBeInTheDocument()
})

describe('StaffFeedback', () => {
  const mockIsStaff = jest.mocked(isStaff)

  beforeEach(() => {
    mockIsStaff.mockReset()
  })

  test('should not render for non-staff', async () => {
    mockIsStaff.mockReturnValue(false)
    mockUseFeatureFlag.mockReturnValue({issue_dependencies: true})

    setupEnvironment({
      blockedBy: {
        nodes: [OTHER_ISSUE],
        pageInfo: {hasNextPage: false},
      },
    })

    expect(await screen.findByText(LABELS.relationNames.blockedByIssues)).toBeInTheDocument()
    expect(screen.queryByTestId('staff-feedback')).not.toBeInTheDocument()
  })

  test('should render next to blocked by when both blocking and blocked-by issues are present', async () => {
    mockIsStaff.mockReturnValue(true)
    mockUseFeatureFlag.mockReturnValue({issue_dependencies: true})

    setupEnvironment({
      blockedBy: {
        nodes: [OTHER_ISSUE],
        pageInfo: {hasNextPage: false},
      },
      blocking: {
        nodes: [OTHER_ISSUE],
        pageInfo: {hasNextPage: false},
      },
    })

    expect(await screen.findByText(LABELS.relationNames.blockedByIssues)).toBeInTheDocument()
    expect(await screen.findByText(LABELS.relationNames.blockingIssues)).toBeInTheDocument()

    // Should render StaffFeedback in the blocked by section
    const blockedBySection = screen.getByText(LABELS.relationNames.blockedByIssues)
    expect(blockedBySection).toBeInTheDocument()

    const staffFeedbackLinks = screen.queryAllByTestId('staff-feedback')
    expect(staffFeedbackLinks).toHaveLength(1)
    const staffFeedbackLink = staffFeedbackLinks[0]!
    expect(staffFeedbackLink).toBeInTheDocument()
    expect(staffFeedbackLink).toHaveAttribute('href', 'https://gh.io/dependencies-feedback')
    expect(staffFeedbackLink).toHaveAttribute('target', '_blank')
    expect(staffFeedbackLink).toHaveTextContent('Give feedback')
    expect(staffFeedbackLink).toHaveTextContent('Staff')

    // Ensure it's in the blocked by section, not the blocking section
    expect(blockedBySection).toContainElement(staffFeedbackLink)
  })

  test('should render next to blocking when only blocking issues are present', async () => {
    mockIsStaff.mockReturnValue(true)
    mockUseFeatureFlag.mockReturnValue({issue_dependencies: true})

    setupEnvironment({
      blocking: {
        nodes: [OTHER_ISSUE],
        pageInfo: {hasNextPage: false},
      },
    })

    expect(await screen.findByText(LABELS.relationNames.blockingIssues)).toBeInTheDocument()
    expect(screen.queryByText(LABELS.relationNames.blockedByIssues)).not.toBeInTheDocument()

    // Should render StaffFeedback in the blocking section
    const blockingSection = screen.getByText(LABELS.relationNames.blockingIssues)
    expect(blockingSection).toBeInTheDocument()

    const staffFeedbackLink = screen.getByTestId('staff-feedback')
    expect(staffFeedbackLink).toBeInTheDocument()
    expect(staffFeedbackLink).toHaveAttribute('href', 'https://gh.io/dependencies-feedback')
    expect(staffFeedbackLink).toHaveAttribute('target', '_blank')
    expect(staffFeedbackLink).toHaveTextContent('Give feedback')
    expect(staffFeedbackLink).toHaveTextContent('Staff')

    // Ensure it's in the blocking section
    expect(blockingSection).toContainElement(staffFeedbackLink)
  })
})
