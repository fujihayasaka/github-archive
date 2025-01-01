import {renderRelay} from '@github-ui/relay-test-utils'
import {LabelCreate} from '../LabelCreate'
import {ConnectionHandler, graphql} from 'relay-runtime'
import {act, screen, waitFor} from '@testing-library/react'
import {LABELS} from '../constants/labels'
import {setupUserEvent, Wrapper} from '@github-ui/react-core/test-utils'
import type {LabelCreateTestQuery} from './__generated__/LabelCreateTestQuery.graphql'
import type {RelayMockProps} from '@github-ui/relay-test-utils/RelayTestFactories'
import {createMockEnvironment} from 'relay-test-utils'
import type {LabelCreate$key} from '../__generated__/LabelCreate.graphql'
import {useSearchParams as useSearchParamsMock} from '@github-ui/use-navigate'
import {SORT_MAP, UI_SORT_VALUES} from '../sort-options'

jest.mock('@github-ui/use-navigate', () => {
  const real = jest.requireActual('@github-ui/use-navigate')
  return {...real, useSearchParams: jest.fn()}
})

const mockedUseSearchParams = useSearchParamsMock as jest.Mock

type RepositoryQueryType = {
  repositoryQuery: LabelCreateTestQuery
}

const labelCreateQuery = graphql`
  query LabelCreateTestQuery @relay_test_operation {
    node(id: "repo-123") {
      ... on Repository {
        ...LabelCreate @dangerously_unaliased_fixme
      }
    }
  }
`

const baseConfig: RelayMockProps<RepositoryQueryType> = {
  queries: {
    repositoryQuery: {
      type: 'fragment',
      query: labelCreateQuery,
      variables: {},
    },
  },
}

function primeEmptyLabelsConnection(env: ReturnType<typeof createMockEnvironment>) {
  act(() => {
    env.commitUpdate(store => {
      const repoId = 'repo-123'
      // eslint-disable-next-line @typescript-eslint/no-unused-expressions
      store.get(repoId) || store.create(repoId, 'Repository')

      const connectionId = ConnectionHandler.getConnectionID(repoId, 'LabelList_labels', {
        orderBy: {direction: 'ASC', field: 'NAME'},
        skip: 0,
      })

      // create an empty connection record if it does not yet exist
      if (!store.get(connectionId)) {
        const connection = store.create(connectionId, 'LabelConnection')
        connection.setLinkedRecords([], 'edges')
        connection.setValue(0, 'totalCount')
      }
    })
  })
}

beforeEach(() => {
  mockedUseSearchParams.mockReturnValue([new URLSearchParams('')])
})

describe('LabelCreate', () => {
  test('renders nothing when closed', () => {
    renderRelay<RepositoryQueryType>(
      ({queryData}) => (
        <Wrapper>
          <LabelCreate
            repository={queryData.repositoryQuery.node as LabelCreate$key}
            isOpen={false}
            onClose={jest.fn()}
          />
        </Wrapper>
      ),
      {relay: {...baseConfig}},
    )

    // When the dialog is closed nothing related should be present in the DOM
    expect(screen.queryByRole('button', {name: `${LABELS.createButtonText} ( control enter )`})).not.toBeInTheDocument()
  })

  test('successfully creates label and closes dialog on success', async () => {
    const user = setupUserEvent()
    const environment = createMockEnvironment()
    primeEmptyLabelsConnection(environment)

    renderRelay<RepositoryQueryType>(
      ({queryData: {repositoryQuery}}) => (
        <Wrapper>
          <LabelCreate repository={repositoryQuery.node as LabelCreate$key} isOpen onClose={jest.fn()} />
        </Wrapper>
      ),
      {
        relay: {
          environment,
          ...baseConfig,
          mockResolvers: {
            Repository: () => ({
              __typename: 'Repository',
              id: 'repo-123',
              viewerCanPush: true,
              labels: {
                edges: [],
                totalCount: 0,
              },
            }),
          },
        },
      },
    )

    await user.type(screen.getByPlaceholderText(LABELS.labelNamePlaceholder), 'Test Label')
    await user.type(screen.getByPlaceholderText(LABELS.labelDescriptionPlaceholder), 'Test Description')

    await user.click(screen.getByRole('button', {name: `${LABELS.createButtonText} ( control enter )`}))

    expect(environment.mock.getMostRecentOperation().request.variables).toMatchObject({
      input: {
        repositoryId: 'repo-123',
        name: 'Test Label',
        description: 'Test Description',
      },
    })

    await act(async () => {
      environment.mock.resolveMostRecentOperation({
        data: {
          createLabel: {
            label: {
              id: 'label-123',
              name: 'Test Label',
              nameHTML: 'Test Label',
              color: '#000000',
              description: 'Test Description',
              repository: {
                id: 'repo-123',
              },
              issues: {totalCount: 0},
              pullRequests: {totalCount: 0},
            },
            errors: [],
          },
        },
      })
    })

    expect(screen.queryByText(LABELS.labelCreateError)).not.toBeInTheDocument()
  })

  test.each(
    UI_SORT_VALUES.flatMap(k => [
      {keyword: k, dir: 'asc'},
      {keyword: k, dir: 'desc'},
    ]),
  )('creates label using correct connection $keyword-$dir', async ({keyword, dir}) => {
    const user = setupUserEvent()
    const environment = createMockEnvironment()
    primeEmptyLabelsConnection(environment)
    mockedUseSearchParams.mockReturnValue([new URLSearchParams(`sort=${keyword}-${dir}`)])

    const connectionId = ConnectionHandler.getConnectionID('repo-123', 'LabelList_labels', {
      orderBy: {direction: dir.toUpperCase(), field: SORT_MAP[keyword]},
      skip: 0,
    })

    act(() => {
      environment.commitUpdate(store => {
        if (!store.get(connectionId)) {
          const conn = store.create(connectionId, 'LabelConnection')
          conn.setLinkedRecords([], 'edges')
          conn.setValue(0, 'totalCount')
        }
      })
    })

    renderRelay<RepositoryQueryType>(
      ({queryData: {repositoryQuery}}) => (
        <Wrapper>
          <LabelCreate repository={repositoryQuery.node as LabelCreate$key} isOpen onClose={jest.fn()} />
        </Wrapper>
      ),
      {
        relay: {
          environment,
          ...baseConfig,
          mockResolvers: {
            Repository: () => ({
              __typename: 'Repository',
              id: 'repo-123',
              viewerCanPush: true,
              labels: {edges: [], totalCount: 0},
            }),
          },
        },
      },
    )

    await user.type(screen.getByPlaceholderText(LABELS.labelNamePlaceholder), 'Issue label')
    await user.click(screen.getByRole('button', {name: `${LABELS.createButtonText} ( control enter )`}))

    // the mutation must target the same connection ID
    expect(environment.mock.getMostRecentOperation().request.variables.connection).toBe(connectionId)

    await act(async () => {
      environment.mock.resolveMostRecentOperation({
        data: {
          createLabel: {
            label: {
              id: 'label-42',
              name: 'Issue label',
              nameHTML: 'Issue label',
              color: '#abcdef',
              description: '',
              repository: {id: 'repo-123'},
              issues: {totalCount: 0},
              pullRequests: {totalCount: 0},
            },
            errors: [],
          },
        },
      })
    })

    environment.commitUpdate(store => {
      const total = store.get(connectionId)?.getValue('totalCount')
      expect(total).toBe(1)
    })
  })

  test('displays error when mutation fails', async () => {
    const user = setupUserEvent()
    const environment = createMockEnvironment()
    primeEmptyLabelsConnection(environment)

    renderRelay<RepositoryQueryType>(
      ({queryData: {repositoryQuery}}) => (
        <Wrapper>
          <LabelCreate repository={repositoryQuery.node as LabelCreate$key} isOpen onClose={jest.fn()} />
        </Wrapper>
      ),
      {
        relay: {
          environment,
          ...baseConfig,
          mockResolvers: {
            Repository: () => ({
              id: 'repo-123',
              viewerCanPush: true,
            }),
          },
        },
      },
    )

    await user.type(screen.getByPlaceholderText(LABELS.labelNamePlaceholder), 'Test Label')
    await user.click(screen.getByRole('button', {name: `${LABELS.createButtonText} ( control enter )`}))

    await act(async () => {
      environment.mock.rejectMostRecentOperation(new Error('Mutation error'))
    })

    await waitFor(() => {
      expect(screen.getByText(LABELS.labelCreateError)).toBeInTheDocument()
    })
  })

  test('calls onClose when mutation completes successfully', async () => {
    const user = setupUserEvent()
    const environment = createMockEnvironment()
    primeEmptyLabelsConnection(environment)
    const onClose = jest.fn()

    renderRelay<RepositoryQueryType>(
      ({queryData: {repositoryQuery}}) => (
        <Wrapper>
          <LabelCreate repository={repositoryQuery.node as LabelCreate$key} isOpen onClose={onClose} />
        </Wrapper>
      ),
      {
        relay: {
          environment,
          ...baseConfig,
          mockResolvers: {
            Repository: () => ({
              __typename: 'Repository',
              id: 'repo-123',
              viewerCanPush: true,
              labels: {edges: [], totalCount: 0},
            }),
          },
        },
      },
    )

    await user.type(screen.getByPlaceholderText(LABELS.labelNamePlaceholder), 'Ok Label')
    await user.type(screen.getByPlaceholderText(LABELS.labelDescriptionPlaceholder), 'Some description')
    await user.click(screen.getByRole('button', {name: `${LABELS.createButtonText} ( control enter )`}))

    expect(environment.mock.getMostRecentOperation().request.variables).toMatchObject({
      input: {repositoryId: 'repo-123', name: 'Ok Label', description: 'Some description'},
    })

    await act(async () => {
      environment.mock.resolveMostRecentOperation({
        data: {
          createLabel: {
            label: {
              id: 'label-123',
              name: 'Ok Label',
              nameHTML: 'Ok Label',
              color: '#ffffff',
              description: 'Some description',
              repository: {id: 'repo-123'},
              issues: {totalCount: 0},
              pullRequests: {totalCount: 0},
            },
            errors: [],
          },
        },
      })
    })

    await waitFor(() => {
      expect(onClose).toHaveBeenCalledTimes(1)
    })

    expect(screen.queryByText(LABELS.labelCreateError)).not.toBeInTheDocument()
  })

  test('shows field errors returned from mutation', async () => {
    // Silence Relay's expected warning and assert it was logged.
    const consoleErrorSpy = jest.spyOn(console, 'error').mockImplementation(() => {})

    const user = setupUserEvent()
    const environment = createMockEnvironment()
    primeEmptyLabelsConnection(environment)

    renderRelay<RepositoryQueryType>(
      ({queryData: {repositoryQuery}}) => (
        <Wrapper>
          <LabelCreate repository={repositoryQuery.node as LabelCreate$key} isOpen onClose={jest.fn()} />
        </Wrapper>
      ),
      {
        relay: {
          environment,
          ...baseConfig,
          mockResolvers: {
            Repository: () => ({
              __typename: 'Repository',
              id: 'repo-123',
              viewerCanPush: true,
              labels: {edges: [], totalCount: 0},
            }),
          },
        },
      },
    )

    await user.type(screen.getByPlaceholderText(LABELS.labelNamePlaceholder), 'Duplicate')
    await user.click(screen.getByRole('button', {name: `${LABELS.createButtonText} ( control enter )`}))

    await act(async () => {
      environment.mock.resolveMostRecentOperation({
        data: {
          createLabel: {
            label: null,
            errors: [{__typename: 'ValidationError', message: 'Name is already taken', path: ['createLabel']}],
          },
        },
        errors: [
          {
            path: ['createLabel'],
            locations: [
              {
                line: 4,
                column: 3,
              },
            ],
            message: 'Name has already been taken',
          },
        ],
      })
    })

    await waitFor(() => {
      expect(screen.getByText(/Name is already taken/i)).toBeInTheDocument()
    })

    // Verify the warning occurred and restore the spy.
    expect(consoleErrorSpy).toHaveBeenCalledWith(
      expect.stringContaining('MutationHandlers: Expected target node to exist.'),
    )
    consoleErrorSpy.mockRestore()
  })

  test('shows permission error when viewer cannot push', async () => {
    const user = setupUserEvent()
    const environment = createMockEnvironment()
    primeEmptyLabelsConnection(environment)

    renderRelay<RepositoryQueryType>(
      ({queryData: {repositoryQuery}}) => (
        <Wrapper>
          <LabelCreate repository={repositoryQuery.node as LabelCreate$key} isOpen onClose={jest.fn()} />
        </Wrapper>
      ),
      {
        relay: {
          environment,
          ...baseConfig,
          mockResolvers: {
            Repository: () => ({
              __typename: 'Repository',
              id: 'repo-123',
              viewerCanPush: false,
            }),
          },
        },
      },
    )

    // One test query operation has already been recorded.
    const opsBeforeClick = environment.mock.getAllOperations().length

    await user.type(screen.getByPlaceholderText(LABELS.labelNamePlaceholder), 'Blocked')
    await user.click(screen.getByRole('button', {name: `${LABELS.createButtonText} ( control enter )`}))

    // No additional operations (i.e. no mutation) should have been scheduled.
    expect(environment.mock.getAllOperations()).toHaveLength(opsBeforeClick)

    await waitFor(() => {
      expect(screen.getByText(LABELS.labelCreatePermissionError)).toBeInTheDocument()
    })
  })
})
