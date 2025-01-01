import {renderRelay} from '@github-ui/relay-test-utils'
import {graphql} from 'relay-runtime'
import {act, screen} from '@testing-library/react'
import {RepositoryLabelsInternal} from '../RepositoryLabels'
import type {RepositoryLabelsTestQuery} from './__generated__/RepositoryLabelsTestQuery.graphql'
import type {RelayMockProps} from '@github-ui/relay-test-utils/RelayTestFactories'
import {Wrapper} from '@github-ui/react-core/test-utils'
import {createMockEnvironment} from 'relay-test-utils'

type LabelQueries = {
  labelQuery: RepositoryLabelsTestQuery
}

let paramsMock = new URLSearchParams()
jest.mock('@github-ui/use-navigate', () => {
  const originalModule = jest.requireActual('@github-ui/use-navigate')
  return {
    ...originalModule,
    useSearchParams: jest.fn().mockImplementation(() => {
      return [paramsMock, jest.fn()]
    }),
  }
})

const baseConfig: RelayMockProps<LabelQueries> = {
  queries: {
    labelQuery: {
      type: 'fragment',
      query: graphql`
        query RepositoryLabelsTestQuery @relay_test_operation {
          node(id: "mockRepositoryId") {
            ... on Repository {
              ...RepositoryLabelsInternal @dangerously_unaliased_fixme @arguments(first: 30, skip: 0)
            }
          }
        }
      `,
      variables: {},
    },
  },
}

const LabelConnection = () => ({
  edges: [
    {
      node: {
        id: 'mockLabelID',
        nameHTML: 'bug',
        description: 'something is not working',
        color: '18180c',
        issueCount: 5,
        pullRequestCount: 12,
      },
    },
    {
      node: {
        id: 'mockLabelID2',
        nameHTML: 'good for first issue',
        description: 'pick this up if you are not familiar with the code',
        issueCount: 0,
        pullRequestCount: 0,
        color: 'a2eeef',
      },
    },
  ],
})

beforeEach(() => {
  paramsMock = new URLSearchParams()
})

describe('Repository labels', () => {
  test('renders search bar', () => {
    renderRelay<{labelQuery: RepositoryLabelsTestQuery}>(
      ({queryData: {labelQuery}}) => {
        if (labelQuery.node) {
          return (
            <Wrapper>
              <RepositoryLabelsInternal repository={labelQuery.node} />
            </Wrapper>
          )
        }
      },
      {
        relay: {
          ...baseConfig,
          mockResolvers: {
            LabelConnection,
          },
        },
      },
    )

    expect(screen.getByRole('search', {name: /search all labels/i})).toBeInTheDocument()
  })

  test('renders label names', () => {
    renderRelay<{labelQuery: RepositoryLabelsTestQuery}>(
      ({queryData: {labelQuery}}) => {
        if (labelQuery.node) {
          return (
            <Wrapper>
              <RepositoryLabelsInternal repository={labelQuery.node} />
            </Wrapper>
          )
        }
      },
      {
        relay: {
          ...baseConfig,
          mockResolvers: {
            LabelConnection,
          },
        },
      },
    )

    expect(screen.getByRole('link', {name: /bug/})).toBeInTheDocument()
    expect(screen.getByRole('link', {name: /good for first issue/})).toBeInTheDocument()
  })

  test('renders label descriptions', () => {
    renderRelay<{labelQuery: RepositoryLabelsTestQuery}>(
      ({queryData: {labelQuery}}) => {
        if (labelQuery.node) {
          return (
            <Wrapper>
              <RepositoryLabelsInternal repository={labelQuery.node} />
            </Wrapper>
          )
        }
      },
      {
        relay: {
          ...baseConfig,
          mockResolvers: {
            LabelConnection,
          },
        },
      },
    )

    expect(screen.getByText(/something is not working/)).toBeInTheDocument()
    expect(screen.getByText(/pick this up if you are not familiar with the code/)).toBeInTheDocument()
    // renders sort button
    expect(screen.getByRole('button', {name: /sort/i})).toBeInTheDocument()
  })

  test('Does not render sort menu if query is present', () => {
    paramsMock.set('q', 'some query')
    renderRelay<{labelQuery: RepositoryLabelsTestQuery}>(
      ({queryData: {labelQuery}}) => {
        if (labelQuery.node) {
          return (
            <Wrapper>
              <RepositoryLabelsInternal repository={labelQuery.node} />
            </Wrapper>
          )
        }
      },
      {
        relay: {
          ...baseConfig,
          mockResolvers: {
            LabelConnection,
          },
        },
      },
    )

    expect(screen.queryByRole('button', {name: /sort/i})).not.toBeInTheDocument()
  })

  test('shows secondary data per row', async () => {
    const environment = createMockEnvironment()
    renderRelay<{labelQuery: RepositoryLabelsTestQuery}>(
      ({queryData: {labelQuery}}) => {
        if (labelQuery.node) {
          return (
            <Wrapper>
              <RepositoryLabelsInternal repository={labelQuery.node} />
            </Wrapper>
          )
        }
      },
      {
        relay: {
          environment,
          ...baseConfig,
          mockResolvers: {
            LabelConnection,
          },
        },
      },
    )

    expect(screen.getByText(/something is not working/)).toBeInTheDocument()
    expect(screen.getByText(/pick this up if you are not familiar with the code/)).toBeInTheDocument()
    expect(environment.mock.getMostRecentOperation().fragment.node.name).toBe(
      'IssuesAndPullRequestsCountSecondaryQuery',
    )
    await act(async () => {
      environment.mock.resolveMostRecentOperation({
        data: {
          nodes: [
            {
              __typename: 'Label',
              id: 'mockLabelID',
              issueCount: 99,
              pullRequestCount: 0,
            },
            {
              __typename: 'Label',
              id: 'mockLabelID2',
              issueCount: 0,
              pullRequestCount: 420,
            },
          ],
        },
      })
    })

    expect(screen.getByRole('link', {name: /99 open issues/})).toBeInTheDocument()
    expect(screen.getByRole('link', {name: /420 open pull requests/})).toBeInTheDocument()
  })

  test('shows fallback in case of error secondary query', async () => {
    jest.spyOn(console, 'error').mockImplementation()
    const environment = createMockEnvironment()
    renderRelay<{labelQuery: RepositoryLabelsTestQuery}>(
      ({queryData: {labelQuery}}) => {
        if (labelQuery.node) {
          return (
            <Wrapper>
              <RepositoryLabelsInternal repository={labelQuery.node} />
            </Wrapper>
          )
        }
      },
      {
        relay: {
          environment,
          ...baseConfig,
          mockResolvers: {
            LabelConnection,
          },
        },
      },
    )

    expect(screen.getByText(/something is not working/)).toBeInTheDocument()
    expect(screen.getByText(/pick this up if you are not familiar with the code/)).toBeInTheDocument()
    expect(environment.mock.getMostRecentOperation().fragment.node.name).toBe(
      'IssuesAndPullRequestsCountSecondaryQuery',
    )
    await act(async () => {
      environment.mock.rejectMostRecentOperation(() => new Error('Failed to fetch secondary data'))
    })
    expect(screen.getAllByText(/Could not load data/)).toHaveLength(2)
  })
})
