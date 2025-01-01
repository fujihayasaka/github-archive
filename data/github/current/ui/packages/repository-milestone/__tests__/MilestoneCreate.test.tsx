import {renderRelay} from '@github-ui/relay-test-utils'
import {MilestoneCreate} from '../MilestoneCreate'
import {graphql} from 'relay-runtime'
import {act, screen, waitFor} from '@testing-library/react'
import {LABELS} from '../constants/labels'
import {setupUserEvent, Wrapper} from '@github-ui/react-core/test-utils'
import type {MilestoneCreateTestQuery} from './__generated__/MilestoneCreateTestQuery.graphql'
import type {RelayMockProps} from '@github-ui/relay-test-utils/RelayTestFactories'
import {createMockEnvironment, MockPayloadGenerator} from 'relay-test-utils'
import {DefaultMocks} from '@github-ui/relay-test-utils/mock-resolvers'
import {useNavigate} from '@github-ui/use-navigate'

jest.mock('@github-ui/use-navigate', () => ({
  ...jest.requireActual('@github-ui/use-navigate'),
  useNavigate: jest.fn(),
}))

jest.mock('@github-ui/history', () => ({
  ...jest.requireActual('@github-ui/history'),
  goBack: jest.fn(),
}))

type RepositoryQueryType = {
  repositoryQuery: MilestoneCreateTestQuery
}

const milestoneCreateQuery = graphql`
  query MilestoneCreateTestQuery @relay_test_operation {
    node(id: "repo-123") {
      ... on Repository {
        ...MilestoneCreateFormRepositoryQuery @dangerously_unaliased_fixme
      }
    }
  }
`

const baseConfig: RelayMockProps<RepositoryQueryType> = {
  queries: {
    repositoryQuery: {
      type: 'fragment',
      query: milestoneCreateQuery,
      variables: {},
    },
  },
}

describe('MilestoneCreate', () => {
  const navigateMock = jest.fn()

  beforeEach(() => {
    jest.clearAllMocks()
    ;(useNavigate as jest.Mock).mockReturnValue(navigateMock)
  })

  test('successfully creates milestone and navigates on success', async () => {
    const user = setupUserEvent()
    const environment = createMockEnvironment()

    renderRelay<RepositoryQueryType>(
      ({queryData: {repositoryQuery}}) => (
        <Wrapper>
          <MilestoneCreate repository={repositoryQuery.node!} />
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
            }),
          },
        },
      },
    )

    await user.type(screen.getByPlaceholderText(LABELS.titlePlaceholder), 'Test Milestone')
    await user.type(screen.getByPlaceholderText(LABELS.descriptionPlaceholder), 'Test Description')

    await user.click(screen.getByRole('button', {name: LABELS.createMilestone}))

    expect(environment.mock.getMostRecentOperation().request.variables).toMatchObject({
      input: {
        repositoryId: 'repo-123',
        title: 'Test Milestone',
        description: 'Test Description',
      },
    })

    await act(async () => {
      environment.mock.resolveMostRecentOperation({
        data: {
          createMilestone: {
            milestone: {
              number: 42,
              repository: null,
              id: 'milestone-123',
              title: 'Test Milestone',
              description: 'Test Description',
              dueOn: null,
              url: '/github/test-repo/milestones/1',
              progressPercentage: 0,
              openIssueCount: 0,
              closedIssueCount: 0,
              issues: {
                totalCount: 0,
              },
              state: 'open',
            },
            errors: [],
          },
        },
      })
    })

    expect(navigateMock).toHaveBeenCalledWith('/github/test-repo/milestone/42')
  })

  test('displays error when mutation fails', async () => {
    const user = setupUserEvent()
    const environment = createMockEnvironment()

    renderRelay<RepositoryQueryType>(
      ({queryData: {repositoryQuery}}) => (
        <Wrapper>
          <MilestoneCreate repository={repositoryQuery.node!} />
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
            }),
          },
        },
      },
    )

    await user.type(screen.getByPlaceholderText(LABELS.titlePlaceholder), 'Test Milestone')

    await user.click(screen.getByRole('button', {name: LABELS.createMilestone}))

    await act(async () => {
      environment.mock.rejectMostRecentOperation({
        message: 'Mutation error',
        name: 'InternalError',
        cause: [
          {
            message: 'Mutation error',
          },
        ],
      })
    })

    await waitFor(() => {
      expect(screen.getByText('Mutation error')).toBeInTheDocument()
    })
  })

  test('displays error when response has no milestone', async () => {
    const user = setupUserEvent()
    const environment = createMockEnvironment()

    renderRelay<RepositoryQueryType>(
      ({queryData: {repositoryQuery}}) => (
        <Wrapper>
          <MilestoneCreate repository={repositoryQuery.node!} />
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
            }),
          },
        },
      },
    )

    await user.type(screen.getByPlaceholderText(LABELS.titlePlaceholder), 'Test Milestone')
    await user.click(screen.getByRole('button', {name: LABELS.createMilestone}))

    await act(async () => {
      environment.mock.resolveMostRecentOperation(operation => {
        return MockPayloadGenerator.generate(operation, {
          ...DefaultMocks,
          Repository: () => ({
            id: 'repo-123',
            viewerCanPush: true,
            milestone: null,
          }),
          CreateMilestonePayload: () => ({
            milestone: null,
            errors: [],
          }),
        })
      })
    })

    await waitFor(() => {
      expect(screen.getByText(LABELS.milestoneCreateError)).toBeInTheDocument()
    })
  })

  test('displays error when user lacks permission', async () => {
    const user = setupUserEvent()
    const environment = createMockEnvironment()

    renderRelay<RepositoryQueryType>(
      ({queryData: {repositoryQuery}}) => (
        <Wrapper>
          <MilestoneCreate repository={repositoryQuery.node!} />
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
            }),
          },
        },
      },
    )

    await user.type(screen.getByPlaceholderText(LABELS.titlePlaceholder), 'Test Milestone')
    await user.click(screen.getByRole('button', {name: LABELS.createMilestone}))

    await waitFor(() => {
      expect(screen.getByText(LABELS.milestoneCreatePermissionError)).toBeInTheDocument()
    })
  })

  test('displays error when response has validation errors', async () => {
    const user = setupUserEvent()
    const environment = createMockEnvironment()

    renderRelay<RepositoryQueryType>(
      ({queryData: {repositoryQuery}}) => (
        <Wrapper>
          <MilestoneCreate repository={repositoryQuery.node!} />
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
            }),
          },
        },
      },
    )

    await user.type(screen.getByPlaceholderText(LABELS.titlePlaceholder), 'Test Milestone')
    await user.click(screen.getByRole('button', {name: LABELS.createMilestone}))

    await act(async () => {
      environment.mock.resolveMostRecentOperation(operation => {
        return MockPayloadGenerator.generate(operation, {
          ...DefaultMocks,
          Repository: () => ({
            id: 'repo-123',
            viewerCanPush: true,
            milestone: null,
          }),
          CreateMilestonePayload: () => ({
            milestone: null,
            errors: [
              {
                message: 'Unknown error',
              },
            ],
          }),
        })
      })
    })

    await waitFor(() => {
      expect(screen.getByText(LABELS.milestoneCreateError)).toBeInTheDocument()
    })
  })
})
