import {renderRelay} from '@github-ui/relay-test-utils'
import {MilestoneEdit} from '../MilestoneEdit'
import {graphql} from 'relay-runtime'
import {act, screen, waitFor} from '@testing-library/react'
import {LABELS} from '../constants/labels'
import {setupUserEvent, Wrapper} from '@github-ui/react-core/test-utils'
import type {MilestoneEditTestQuery} from './__generated__/MilestoneEditTestQuery.graphql'
import type {RelayMockProps} from '@github-ui/relay-test-utils/RelayTestFactories'
import {createMockEnvironment, MockPayloadGenerator} from 'relay-test-utils'
import {DefaultMocks} from '@github-ui/relay-test-utils/mock-resolvers'
import {useNavigate} from '@github-ui/use-navigate'
import {goBack} from '@github-ui/history'

jest.mock('@github-ui/use-navigate', () => ({
  ...jest.requireActual('@github-ui/use-navigate'),
  useNavigate: jest.fn(),
}))

jest.mock('@github-ui/history', () => ({
  ...jest.requireActual('@github-ui/history'),
  goBack: jest.fn(),
}))

type RepositoryQueryType = {
  repositoryQuery: MilestoneEditTestQuery
}

const milestoneEditQuery = graphql`
  query MilestoneEditTestQuery @relay_test_operation {
    node(id: "repo-123") {
      ... on Repository {
        ...MilestoneEditFormRepositoryQuery @dangerously_unaliased_fixme @arguments(number: 1)
      }
    }
  }
`

const baseConfig: RelayMockProps<RepositoryQueryType> = {
  queries: {
    repositoryQuery: {
      type: 'fragment',
      query: milestoneEditQuery,
      variables: {},
    },
  },
}

describe('MilestoneEdit', () => {
  const navigateMock = jest.fn()
  const goBackMock = jest.fn()

  beforeEach(() => {
    jest.clearAllMocks()
    ;(useNavigate as jest.Mock).mockReturnValue(navigateMock)
    ;(goBack as jest.Mock).mockImplementation(goBackMock)
  })

  test('successfully updates milestone and navigates on success', async () => {
    const user = setupUserEvent()
    const environment = createMockEnvironment()

    renderRelay<RepositoryQueryType>(
      ({queryData: {repositoryQuery}}) => (
        <Wrapper>
          <MilestoneEdit repository={repositoryQuery.node!} />
        </Wrapper>
      ),
      {
        relay: {
          environment,
          ...baseConfig,
          mockResolvers: {
            Repository: () => ({
              id: 'repo-123',
              nameWithOwner: 'github/test-repo',
              viewerCanPush: true,
              milestone: {
                id: 'milestone-123',
                title: 'Original Title',
                description: 'Original Description',
              },
            }),
          },
        },
      },
    )

    await user.clear(screen.getByDisplayValue('Original Title'))
    await user.type(screen.getByDisplayValue(''), 'Updated Milestone')

    await user.clear(screen.getByDisplayValue('Original Description'))
    await user.type(screen.getByDisplayValue(''), 'Updated Description')

    await user.click(screen.getByRole('button', {name: LABELS.saveChanges}))

    expect(environment.mock.getMostRecentOperation().request.variables).toMatchObject({
      input: {
        id: 'milestone-123',
        title: 'Updated Milestone',
        description: 'Updated Description',
      },
    })

    await act(async () => {
      environment.mock.resolveMostRecentOperation(operation => {
        return MockPayloadGenerator.generate(operation, {
          UpdateMilestonePayload: () => ({
            milestone: {
              id: 'milestone-123',
              number: 42,
              title: 'Updated Milestone',
              description: 'Updated Description',
              dueOn: null,
            },
            errors: [],
          }),
        })
      })
    })

    expect(navigateMock).toHaveBeenCalledWith('/github/test-repo/milestone/42')
  })

  test('displays error when update mutation fails', async () => {
    const user = setupUserEvent()
    const environment = createMockEnvironment()

    renderRelay<RepositoryQueryType>(
      ({queryData: {repositoryQuery}}) => (
        <Wrapper>
          <MilestoneEdit repository={repositoryQuery.node!} />
        </Wrapper>
      ),
      {
        relay: {
          environment,
          ...baseConfig,
          mockResolvers: {
            Repository: () => ({
              id: 'repo-123',
              nameWithOwner: 'github/test-repo',
              viewerCanPush: true,
              milestone: {
                id: 'milestone-123',
                number: 1,
                title: 'Original Title',
                description: 'Original Description',
                dueOn: null,
              },
            }),
          },
        },
      },
    )

    await user.clear(screen.getByDisplayValue('Original Title'))
    await user.type(screen.getByDisplayValue(''), 'Updated Milestone')
    await user.click(screen.getByRole('button', {name: LABELS.saveChanges}))

    await act(async () => {
      environment.mock.rejectMostRecentOperation({
        message: 'Update error',
        name: 'InternalError',
        cause: [
          {
            message: 'Update error',
          },
        ],
      })
    })

    await waitFor(() => {
      expect(screen.getByText('Update error')).toBeInTheDocument()
    })
  })

  test('displays error when update response has no milestone', async () => {
    const user = setupUserEvent()
    const environment = createMockEnvironment()

    renderRelay<RepositoryQueryType>(
      ({queryData: {repositoryQuery}}) => (
        <Wrapper>
          <MilestoneEdit repository={repositoryQuery.node!} />
        </Wrapper>
      ),
      {
        relay: {
          environment,
          ...baseConfig,
          mockResolvers: {
            Repository: () => ({
              id: 'repo-123',
              nameWithOwner: 'github/test-repo',
              viewerCanPush: true,
              milestone: {
                id: 'milestone-123',
                number: 1,
                title: 'Original Title',
                description: 'Original Description',
                dueOn: null,
              },
            }),
          },
        },
      },
    )

    await user.clear(screen.getByDisplayValue('Original Title'))
    await user.type(screen.getByDisplayValue(''), 'Updated Milestone')
    await user.click(screen.getByRole('button', {name: LABELS.saveChanges}))

    await act(async () => {
      environment.mock.resolveMostRecentOperation(operation => {
        return MockPayloadGenerator.generate(operation, {
          ...DefaultMocks,
          UpdateMilestonePayload: () => ({
            milestone: null,
            errors: [],
          }),
        })
      })
    })

    await waitFor(() => {
      expect(screen.getByText(LABELS.milestoneEditError)).toBeInTheDocument()
    })
  })

  test('displays error when user lacks permission', async () => {
    const user = setupUserEvent()
    const environment = createMockEnvironment()

    renderRelay<RepositoryQueryType>(
      ({queryData: {repositoryQuery}}) => (
        <Wrapper>
          <MilestoneEdit repository={repositoryQuery.node!} />
        </Wrapper>
      ),
      {
        relay: {
          environment,
          ...baseConfig,
          mockResolvers: {
            Repository: () => ({
              id: 'repo-123',
              nameWithOwner: 'github/test-repo',
              viewerCanPush: false,
              milestone: {
                id: 'milestone-123',
                number: 1,
                title: 'Original Title',
                description: 'Original Description',
                dueOn: null,
              },
            }),
          },
        },
      },
    )

    await user.clear(screen.getByDisplayValue('Original Title'))
    await user.type(screen.getByDisplayValue(''), 'Updated Milestone')
    await user.click(screen.getByRole('button', {name: LABELS.saveChanges}))

    await waitFor(() => {
      expect(screen.getByText(LABELS.milestoneEditPermissionError)).toBeInTheDocument()
    })
  })

  test('displays error when update response has validation errors', async () => {
    const user = setupUserEvent()
    const environment = createMockEnvironment()

    renderRelay<RepositoryQueryType>(
      ({queryData: {repositoryQuery}}) => (
        <Wrapper>
          <MilestoneEdit repository={repositoryQuery.node!} />
        </Wrapper>
      ),
      {
        relay: {
          environment,
          ...baseConfig,
          mockResolvers: {
            Repository: () => ({
              id: 'repo-123',
              nameWithOwner: 'github/test-repo',
              viewerCanPush: true,
              milestone: {
                id: 'milestone-123',
                number: 1,
                title: 'Original Title',
                description: 'Original Description',
                dueOn: null,
              },
            }),
          },
        },
      },
    )

    await user.clear(screen.getByDisplayValue('Original Title'))
    await user.type(screen.getByDisplayValue(''), 'Updated Milestone')
    await user.click(screen.getByRole('button', {name: LABELS.saveChanges}))

    await act(async () => {
      environment.mock.resolveMostRecentOperation(operation => {
        return MockPayloadGenerator.generate(operation, {
          ...DefaultMocks,
          UpdateMilestonePayload: () => ({
            milestone: null,
            errors: [
              {
                message: 'Validation error',
              },
            ],
          }),
        })
      })
    })

    await waitFor(() => {
      expect(screen.getByText(LABELS.milestoneEditError)).toBeInTheDocument()
    })
  })

  test('calls goBack when cancel is clicked', async () => {
    const user = setupUserEvent()
    const environment = createMockEnvironment()

    renderRelay<RepositoryQueryType>(
      ({queryData: {repositoryQuery}}) => (
        <Wrapper>
          <MilestoneEdit repository={repositoryQuery.node!} />
        </Wrapper>
      ),
      {
        relay: {
          environment,
          ...baseConfig,
          mockResolvers: {
            Repository: () => ({
              id: 'repo-123',
              nameWithOwner: 'github/test-repo',
              viewerCanPush: true,
              milestone: {
                id: 'milestone-123',
                number: 1,
                title: 'Original Title',
                description: 'Original Description',
                dueOn: null,
              },
            }),
          },
        },
      },
    )

    await user.click(screen.getByRole('button', {name: LABELS.cancel}))
    expect(goBackMock).toHaveBeenCalled()
  })

  test('successfully closes milestone', async () => {
    const user = setupUserEvent()
    const environment = createMockEnvironment()

    renderRelay<RepositoryQueryType>(
      ({queryData: {repositoryQuery}}) => (
        <Wrapper>
          <MilestoneEdit repository={repositoryQuery.node!} />
        </Wrapper>
      ),
      {
        relay: {
          environment,
          ...baseConfig,
          mockResolvers: {
            Repository: () => ({
              id: 'repo-123',
              nameWithOwner: 'github/test-repo',
              viewerCanPush: true,
              milestone: {
                id: 'milestone-123',
                number: 1,
                title: 'Original Title',
                description: 'Original Description',
                dueOn: null,
                state: 'OPEN',
              },
            }),
          },
        },
      },
    )

    await user.click(screen.getByRole('button', {name: LABELS.closeMilestone}))

    expect(environment.mock.getMostRecentOperation().request.variables).toMatchObject({
      input: {
        id: 'milestone-123',
        state: 'CLOSED',
      },
    })

    await act(async () => {
      environment.mock.resolveMostRecentOperation(operation => {
        return MockPayloadGenerator.generate(operation, {
          UpdateMilestonePayload: () => ({
            milestone: {
              id: 'M1',
              closed: true,
            },
          }),
        })
      })
    })

    expect(navigateMock).toHaveBeenCalledWith('/github/test-repo/milestone/1')
  })

  test('displays error when close milestone mutation fails', async () => {
    const user = setupUserEvent()
    const environment = createMockEnvironment()

    renderRelay<RepositoryQueryType>(
      ({queryData: {repositoryQuery}}) => (
        <Wrapper>
          <MilestoneEdit repository={repositoryQuery.node!} />
        </Wrapper>
      ),
      {
        relay: {
          environment,
          ...baseConfig,
          mockResolvers: {
            Repository: () => ({
              id: 'repo-123',
              nameWithOwner: 'github/test-repo',
              viewerCanPush: true,
              milestone: {
                id: 'milestone-123',
                number: 1,
                title: 'Original Title',
                description: 'Original Description',
                dueOn: null,
                state: 'OPEN',
              },
            }),
          },
        },
      },
    )

    await user.click(screen.getByRole('button', {name: LABELS.closeMilestone}))

    await act(async () => {
      environment.mock.rejectMostRecentOperation({
        message: 'Close error',
        name: 'InternalError',
        cause: [
          {
            message: 'Close error',
          },
        ],
      })
    })

    await waitFor(() => {
      expect(screen.getByText('Close error')).toBeInTheDocument()
    })
  })

  test('displays error message when milestone is not found', async () => {
    const environment = createMockEnvironment()

    renderRelay<RepositoryQueryType>(
      ({queryData: {repositoryQuery}}) => (
        <Wrapper>
          <MilestoneEdit repository={repositoryQuery.node!} />
        </Wrapper>
      ),
      {
        relay: {
          environment,
          ...baseConfig,
          mockResolvers: {
            Repository: () => ({
              id: 'repo-123',
              nameWithOwner: 'github/test-repo',
              viewerCanPush: true,
              milestone: null,
            }),
          },
        },
      },
    )

    expect(screen.getByText(LABELS.milestoneError)).toBeInTheDocument()
  })
})
