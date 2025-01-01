import {act, screen, waitFor} from '@testing-library/react'
import {LABELS} from '../../../constants/labels'
import type {User} from '@github-ui/react-core/test-utils'
import {renderRelay} from '@github-ui/relay-test-utils'
import {ThemeProvider} from '@primer/react'
import {mockRelayId} from '@github-ui/relay-test-utils/RelayComponents'
import type {RepositoryPickerCurrentRepoQuery} from '@github-ui/item-picker/RepositoryPickerCurrentRepoQuery.graphql'
import {CurrentRepository, TopRepositories} from '@github-ui/item-picker/RepositoryPicker'
import type {RepositoryPickerTopRepositoriesQuery} from '@github-ui/item-picker/RepositoryPickerTopRepositoriesQuery.graphql'
import PRELOAD_CURRENT_REPOSITORY_QUERY from '@github-ui/item-picker/RepositoryPickerCurrentRepoQuery.graphql'
import {MockPayloadGenerator} from 'relay-test-utils'
import {RelationshipsSection, RelationshipsSectionGraphqlQuery} from '../relations-section/RelationshipsSection'
import type {RelationshipsSectionQuery} from '../relations-section/__generated__/RelationshipsSectionQuery.graphql'
import {useIssueFilteringQueryGraphQLQuery} from '@github-ui/item-picker/useIssueFiltering'
import type {useIssueFilteringQuery} from '@github-ui/item-picker/useIssueFilteringQuery.graphql'
import type {RelationshipsSectionFragment$data} from '../relations-section/__generated__/RelationshipsSectionFragment.graphql'
import {useFeatureFlags} from '@github-ui/react-core/use-feature-flag'
import {AnalyticsProvider} from '@github-ui/analytics-provider'

const owner = 'owner'
const repo = 'repo'
const number = 10

const urlParams = {
  owner,
  repo,
  number,
}

jest.mock('@github-ui/react-core/use-feature-flag')
const mockUseFeatureFlag = jest.mocked(useFeatureFlags).mockReturnValue({})

jest.mock('react-router-dom', () => {
  const originalModule = jest.requireActual('react-router-dom')
  const navigateFn = jest.fn()
  return {
    ...originalModule,
    useNavigate: () => navigateFn,
    _routerNavigateFn: navigateFn,
    useParams: () => urlParams,
  }
})

const findAlertDialog = (): Promise<HTMLElement> => {
  return screen.findByRole('alertdialog')
}

const addNewParent = async (user: User): Promise<undefined> => {
  await user.click(screen.getByRole('button'))
  await user.click(screen.getByLabelText('Add parent'))

  await waitFor(() => {
    const listItems = screen.getAllByRole('option').filter(item => item.getAttribute('data-id') !== 'no-results')
    expect(listItems).toHaveLength(1)
  })
  const option = screen.getByRole('option')
  await user.click(option)
}

function setupEnvironment({
  parentMock,
  issueMock,
}: {parentMock?: Record<string, unknown>; issueMock?: Partial<RelationshipsSectionFragment$data>} = {}) {
  if (parentMock && parentMock.title && !parentMock.titleHTML) {
    parentMock.titleHTML = parentMock.title
  }
  const {relayMockEnvironment, user} = renderRelay<{
    relationsSectionQuery: RelationshipsSectionQuery
    useIssueFilteringQueryGraphQLQuery: useIssueFilteringQuery
    repositoryPickerCurrentRepoQuery: RepositoryPickerCurrentRepoQuery
    topRepositories: RepositoryPickerTopRepositoriesQuery
    preloadCurrentRepositoryQuery: RepositoryPickerCurrentRepoQuery
  }>(
    ({queryRefs: {relationsSectionQuery}}) => (
      <ThemeProvider>
        <AnalyticsProvider appName="test-app" category="test-category" metadata={{}}>
          <RelationshipsSection queryRef={relationsSectionQuery} />
        </AnalyticsProvider>
      </ThemeProvider>
    ),
    {
      relay: {
        queries: {
          preloadCurrentRepositoryQuery: {
            type: 'preloaded',
            query: PRELOAD_CURRENT_REPOSITORY_QUERY,
            variables: {owner: 'orgA', name: 'test-repo'},
          },
          topRepositories: {
            type: 'preloaded',
            query: TopRepositories,
            variables: {topRepositoriesFirst: 5, hasIssuesEnabled: true, owner: null},
          },
          relationsSectionQuery: {
            type: 'preloaded',
            query: RelationshipsSectionGraphqlQuery,
            variables: {owner, repo, number},
          },
          useIssueFilteringQueryGraphQLQuery: {
            type: 'preloaded',
            query: useIssueFilteringQueryGraphQLQuery,
            variables: {
              assignee: 'repo:orgA/test-repo commenter:@me',
              author: 'repo:orgA/test-repo commenter:@me',
              commenters: 'repo:orgA/test-repo commenter:@me',
              mentions: 'repo:orgA/test-repo commenter:@me',
              other: 'repo:orgA/test-repo commenter:@me',
              first: 10,
              resource: '',
              queryIsUrl: false,
            },
          },
          repositoryPickerCurrentRepoQuery: {
            type: 'preloaded',
            query: CurrentRepository,
            variables: {owner: 'orgA', name: 'test-repo'},
          },
        },
        mockResolvers: {
          Repository() {
            return {
              id: 'repoid123',
              name: 'test-repo',
              owner: {
                login: 'orgA',
              },
              isPrivate: false,
              isArchived: parentMock?.repoIsArchived || false,
              nameWithOwner: `orgA/test-repo`,
            }
          },
          Query() {
            return {
              commenters: {
                nodes: [{title: 'issueA', id: mockRelayId()}],
              },
              mentions: [],
              assignee: [],
              author: [],
              other: [],
            }
          },
          Issue({path, args}) {
            if (path?.includes('nodes')) {
              return {
                id: 'parent-issue-id',
                repository: {
                  id: 'repo-id',
                  nameWithOwner: 'orgA/test-repo',
                  owner: {
                    login: 'orgA',
                  },
                  isArchived: parentMock?.repoIsArchived || false,
                },
              }
            }
            if (path?.includes('parent')) {
              return parentMock
            }
            if (args?.number === urlParams.number) {
              return {
                id: '10',
                databaseId: 25,
                parent: parentMock || null,
                topBlockedBy: null,
                topBlocking: null,
                viewerCanUpdateMetadata: !parentMock?.userHasReadOnlyPermission,
                repository: {
                  id: 'repoid123',
                  isArchived: parentMock?.repoIsArchived || false,
                },
                ...issueMock,
              }
            }
            return {id: path?.[0], title: path?.[0], __typename: 'Issue'}
          },
        },
      },
    },
  )

  return {environment: relayMockEnvironment, user}
}

describe('permissions', () => {
  test('renders header with actions when has permission', async () => {
    setupEnvironment({parentMock: {userHasReadOnlyPermission: false}})

    expect(await screen.findByRole('button', {name: 'Edit Relationships'})).toBeInTheDocument()
  })

  test('renders readonly header when without permission', async () => {
    setupEnvironment({parentMock: {userHasReadOnlyPermission: true}})

    await waitFor(() => expect(screen.queryByRole('button', {name: 'Edit Relationships'})).not.toBeInTheDocument())
  })

  test('renders readonly header when repo is archived', async () => {
    setupEnvironment({parentMock: {repoIsArchived: true}})

    await waitFor(() => expect(screen.queryByRole('button', {name: 'Edit Relationships'})).not.toBeInTheDocument())
  })
})

test('renders the parent when present', async () => {
  setupEnvironment({parentMock: {title: 'parent title'}})

  expect(await screen.findByLabelText('parent title')).toBeInTheDocument()
})

test('renders code blocks in parent title', async () => {
  setupEnvironment({parentMock: {title: 'parent title `code`', titleHTML: `parent title <code>code</code>`}})

  expect(await screen.findByRole('code')).toHaveTextContent('code')
  expect(await screen.findByLabelText(/parent title/)).toBeInTheDocument()
})

test('renders empty message when not present', async () => {
  setupEnvironment()

  expect(await screen.findByText(LABELS.emptySections.relationships)).toBeInTheDocument()
})

test('should only have one menu open at a time', async () => {
  const {user} = setupEnvironment()

  await user.click(screen.getByText('Edit Relationships'))

  expect(await screen.findByLabelText('Add parent')).toBeInTheDocument()

  await user.click(screen.getByLabelText('Add parent'))

  await waitFor(() => {
    expect(screen.getAllByRole('option')).toHaveLength(1)
  })

  await user.click(screen.getByText('Edit Relationships'))

  expect(await screen.findByLabelText('Add parent')).toBeInTheDocument()

  await waitFor(() => {
    expect(screen.queryByRole('option')).not.toBeInTheDocument()
  })
})

test('should be able to add new parent', async () => {
  const {environment, user} = setupEnvironment()

  await addNewParent(user)

  act(() => {
    environment.mock.resolveMostRecentOperation(operation => {
      expect(operation.fragment.node.name).toEqual('setParentMutation')
      expect(operation.fragment.variables.input.issueId).toEqual('parent-issue-id')
      expect(operation.fragment.variables.input.subIssueId).toEqual('10')
      return MockPayloadGenerator.generate(operation, {
        Issue({path}) {
          const parent = {id: operation.fragment.variables.input.issueId, title: 'new parent', titleHTML: 'new parent'}
          if (path?.includes('parent')) {
            return parent
          }
          return {
            id: operation.fragment.variables.input.subIssueId,
            parent,
            topBlockedBy: null,
            topBlocking: null,
          }
        },
      })
    })
  })
  await waitFor(() => {
    expect(screen.getByLabelText('new parent')).toBeInTheDocument()
  })
})

test('should be able to change parent', async () => {
  const {environment, user} = setupEnvironment({
    parentMock: {
      title: 'old parent',
      titleHTML: 'old parent',
      databaseId: Math.ceil(Math.random() * 1000),
    },
  })

  await act(() => {
    screen.getByRole('button').click()
  })

  await act(() => {
    screen.getByLabelText('Change or remove parent').click()
  })

  await waitFor(() => {
    const listItems = screen.getAllByRole('option').filter(item => item.getAttribute('data-id') !== 'no-results')
    expect(listItems).toHaveLength(1)
  })
  const option = screen.getByRole('option')

  await user.click(option)

  act(() => {
    environment.mock.resolveMostRecentOperation(operation => {
      expect(operation.fragment.node.name).toEqual('setParentMutation')
      expect(operation.fragment.variables.input.issueId).toEqual('parent-issue-id')
      expect(operation.fragment.variables.input.subIssueId).toEqual('10')
      return MockPayloadGenerator.generate(operation, {
        Issue({path}) {
          const parent = {id: operation.fragment.variables.input.issueId, title: 'new parent', titleHTML: 'new parent'}
          if (path?.includes('parent')) {
            return parent
          }
          return {
            id: operation.fragment.variables.input.subIssueId,
            parent,
            topBlockedBy: null,
            topBlocking: null,
          }
        },
      })
    })
  })
  await waitFor(() => {
    expect(screen.getByLabelText('new parent')).toBeInTheDocument()
  })
})

test('should be able to switch between repository and issue pickers', async () => {
  const {user} = setupEnvironment({parentMock: {title: 'old parent'}})

  await act(() => {
    screen.getByRole('button').click()
  })

  await act(() => {
    screen.getByLabelText('Change or remove parent').click()
  })

  await waitFor(() => {
    expect(screen.getAllByRole('option')).toHaveLength(1)
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

test('dialog is present when there is a breadth limit', async () => {
  const mockError = 'Parent cannot have more than 100 sub-issues'
  const {environment, user} = setupEnvironment()

  await addNewParent(user)
  await act(async () => {
    environment.mock.rejectMostRecentOperation(() => new Error(mockError))
  })

  const alert = await findAlertDialog()
  expect(alert).toBeInTheDocument()

  const heading = await screen.findByText('Sub-issue limit reached')
  expect(heading).toBeInTheDocument()
})

test('dialog is present when there is a depth limit error', async () => {
  const mockError =
    'You can’t add more than 7 layers of sub-issues. To add a sub-issue, remove a parent issue at any level.'
  const {environment, user} = setupEnvironment()

  await addNewParent(user)
  await act(async () => {
    environment.mock.rejectMostRecentOperation(() => new Error(mockError))
  })

  const alert = await findAlertDialog()
  expect(alert).toBeInTheDocument()

  const heading = await screen.findByText('Sub-issue limit reached')
  expect(heading).toBeInTheDocument()
})

test('dialog is present when there is a circular reference error', async () => {
  const mockError = 'Failed to add sub-issue: Sub issue may not create a circular dependency'
  const {environment, user} = setupEnvironment()

  await addNewParent(user)
  await act(async () => {
    environment.mock.rejectMostRecentOperation(() => new Error(mockError))
  })

  const alert = await findAlertDialog()
  expect(alert).toBeInTheDocument()

  const heading = await screen.findByText('Sub-issue circular dependency')
  expect(heading).toBeInTheDocument()
})

test('dialog is present when there is an invalid owner error', async () => {
  const mockError = 'Sub issue must have the same owner as the parent'
  const {environment, user} = setupEnvironment()

  await addNewParent(user)
  await act(async () => {
    environment.mock.rejectMostRecentOperation(() => new Error(mockError))
  })

  const alert = await findAlertDialog()
  expect(alert).toBeInTheDocument()

  const heading = await screen.findByText('Invalid owner')
  expect(heading).toBeInTheDocument()
})

test('shows a blocked by / blocking count if there are more than 0 open, otherwise nothing', async () => {
  mockUseFeatureFlag.mockReturnValue({issue_dependencies: true})
  setupEnvironment({
    issueMock: {
      issueDependenciesSummary: {
        blockedBy: 1,
        blocking: 0,
      },
      topBlockedBy: {
        nodes: [
          {
            ' $fragmentSpreads': {DependencyIssueFragment: true},
            id: 'issue-1',
          },
        ],
        pageInfo: {
          hasNextPage: false,
        },
      },
      topBlocking: {
        nodes: [
          {
            ' $fragmentSpreads': {DependencyIssueFragment: true},
            id: 'issue-2',
          },
        ],
        pageInfo: {
          hasNextPage: false,
        },
      },
    },
  })

  expect(await screen.findByRole('list', {name: 'Blocked by (1)'})).toBeInTheDocument()
  expect(await screen.findByRole('list', {name: 'Is blocking'})).toBeInTheDocument()
})

test('can open the blocked by picker', async () => {
  mockUseFeatureFlag.mockReturnValue({issue_dependencies: true})
  const {user} = setupEnvironment({})

  await user.click(await screen.findByRole('button', {name: 'Edit Relationships'}))
  await user.click(await screen.findByRole('menuitem', {name: /Mark as blocked by/}))
  expect(await screen.findByText(/Mark current issue as blocked by/)).toBeInTheDocument()
})

test('can open the blocking picker', async () => {
  mockUseFeatureFlag.mockReturnValue({issue_dependencies: true})
  const {user} = setupEnvironment({})

  await user.click(await screen.findByRole('button', {name: 'Edit Relationships'}))
  await user.click(await screen.findByRole('menuitem', {name: /Mark as blocking/}))
  expect(await screen.findByText(/Mark current issue as blocking/)).toBeInTheDocument()
})

describe('blockedBy private issues notice', () => {
  test('shows notice when fewer issues are visible than total count', async () => {
    mockUseFeatureFlag.mockReturnValue({issue_dependencies: true})
    setupEnvironment({
      issueMock: {
        issueDependenciesSummary: {
          blockedBy: 2,
          blocking: 0,
        },
        topBlockedBy: {
          nodes: [
            {
              ' $fragmentSpreads': {DependencyIssueFragment: true},
              id: 'issue-1',
            },
          ],
          pageInfo: {
            hasNextPage: false,
          },
        },
        topBlocking: {nodes: [], pageInfo: {hasNextPage: false}},
      },
    })

    const notice = await screen.findByTestId('private-blocked-by-notice')
    expect(notice).toBeInTheDocument()
    expect(notice).toHaveTextContent('Private issues are hidden')
  })

  test('does NOT show notice when visible issues are the same as total count', async () => {
    mockUseFeatureFlag.mockReturnValue({issue_dependencies: true})
    setupEnvironment({
      issueMock: {
        issueDependenciesSummary: {
          blockedBy: 1,
          blocking: 0,
        },
        topBlockedBy: {
          nodes: [
            {
              ' $fragmentSpreads': {DependencyIssueFragment: true},
              id: 'issue-1',
            },
          ],
          pageInfo: {
            hasNextPage: false,
          },
        },
        topBlocking: {nodes: [], pageInfo: {hasNextPage: false}},
      },
    })

    expect(screen.queryByTestId('private-blocked-by-notice')).not.toBeInTheDocument()
  })
})

describe('blocking private issues notice', () => {
  test('shows notice when fewer issues are visible than total count', async () => {
    mockUseFeatureFlag.mockReturnValue({issue_dependencies: true})
    setupEnvironment({
      issueMock: {
        issueDependenciesSummary: {
          blockedBy: 0,
          blocking: 2,
        },
        topBlockedBy: {nodes: [], pageInfo: {hasNextPage: false}},
        topBlocking: {
          nodes: [
            {
              ' $fragmentSpreads': {DependencyIssueFragment: true},
              id: 'issue-1',
            },
          ],
          pageInfo: {
            hasNextPage: false,
          },
        },
      },
    })

    const span = await screen.findByTestId('private-blocking-notice')
    expect(span).toBeInTheDocument()
    expect(span).toHaveTextContent('Private issues are hidden')
  })

  test('does NOT show notice when visible issues are the same as total count', async () => {
    mockUseFeatureFlag.mockReturnValue({issue_dependencies: true})
    setupEnvironment({
      issueMock: {
        issueDependenciesSummary: {
          blockedBy: 0,
          blocking: 1,
        },
        topBlockedBy: {nodes: [], pageInfo: {hasNextPage: false}},
        topBlocking: {
          nodes: [
            {
              ' $fragmentSpreads': {DependencyIssueFragment: true},
              id: 'issue-1',
            },
          ],
          pageInfo: {
            hasNextPage: false,
          },
        },
      },
    })

    expect(screen.queryByTestId('private-blocking-notice')).not.toBeInTheDocument()
  })
})
