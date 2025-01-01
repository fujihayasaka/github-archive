import {renderRelay} from '@github-ui/relay-test-utils'
import {MilestoneList} from '../MilestoneList'
import {graphql} from 'relay-runtime'
import {screen} from '@testing-library/react'
import type {MilestoneListTestQuery} from './__generated__/MilestoneListTestQuery.graphql'
import {Wrapper} from '@github-ui/react-core/test-utils'
import {LABELS} from '../constants/labels'

const renderMilestones = (hasNextPage: boolean = false) =>
  renderRelay<{milestoneQuery: MilestoneListTestQuery}>(
    ({queryData: {milestoneQuery}}) => (
      <Wrapper>
        <MilestoneList repositoryRef={milestoneQuery.node!} />
      </Wrapper>
    ),
    {
      relay: {
        queries: {
          milestoneQuery: {
            type: 'fragment',
            query: graphql`
              query MilestoneListTestQuery @relay_test_operation {
                node(id: "123") {
                  ... on Repository {
                    ...MilestoneList @dangerously_unaliased_fixme @arguments(first: 10, state: OPEN)
                  }
                }
              }
            `,
            variables: {},
          },
        },
        mockResolvers: {
          PageInfo: () => ({
            hasNextPage,
            endCursor: 'cursor',
            startCursor: 'cursor',
            hasPreviousPage: false,
          }),
          MilestoneConnection: () => ({
            edges: [
              {
                node: {
                  id: '123',
                  title: 'release',
                },
              },
              {
                node: {
                  id: '456',
                  title: 'bugs',
                },
              },
            ],
          }),
        },
      },
    },
  )

describe('MilestoneList', () => {
  test('renders milestone List', () => {
    renderMilestones()
    expect(screen.getByText('release')).toBeInTheDocument()
    expect(screen.getByText('bugs')).toBeInTheDocument()
  })

  test('renders load more button in milestone List', () => {
    renderMilestones(true)

    expect(screen.getByText('release')).toBeInTheDocument()
    expect(screen.getByText('bugs')).toBeInTheDocument()
    expect(screen.getByTestId('load-more-milestones-button')).toBeInTheDocument()
  })

  test('Does not render load more button in milestone List', () => {
    renderMilestones(false)

    expect(screen.getByText('release')).toBeInTheDocument()
    expect(screen.getByText('bugs')).toBeInTheDocument()
    expect(screen.queryByTestId('load-more-milestones-button')).not.toBeInTheDocument()
  })

  test('renders empty state with create milestone action when no milestones exist', () => {
    renderRelay<{milestoneQuery: MilestoneListTestQuery}>(
      ({queryData: {milestoneQuery}}) => (
        <Wrapper>
          <MilestoneList repositoryRef={milestoneQuery.node!} />
        </Wrapper>
      ),
      {
        relay: {
          queries: {
            milestoneQuery: {
              type: 'fragment',
              query: graphql`
                query MilestoneList_NoMilestonesTestQuery @relay_test_operation {
                  node(id: "123") {
                    ... on Repository {
                      ...MilestoneList @dangerously_unaliased_fixme @arguments(first: 10, state: OPEN)
                    }
                  }
                }
              `,
              variables: {},
            },
          },
          mockResolvers: {
            PageInfo: () => ({
              hasNextPage: false,
              endCursor: null,
              startCursor: null,
              hasPreviousPage: false,
            }),
            MilestoneConnection: () => ({
              edges: [],
              totalCount: 0,
            }),
            Repository: () => ({
              nameWithOwner: 'test/repo',
              open: {
                totalCount: 0,
              },
              closed: {
                totalCount: 0,
              },
            }),
          },
        },
      },
    )
    expect(screen.getByText(LABELS.createAMilestone)).toBeInTheDocument()
    expect(screen.getByText(LABELS.noCreatedMilestones)).toBeInTheDocument()
  })

  test('renders none found state when milestones exist but none match', () => {
    renderRelay<{milestoneQuery: MilestoneListTestQuery}>(
      ({queryData: {milestoneQuery}}) => (
        <Wrapper>
          <MilestoneList repositoryRef={milestoneQuery.node!} />
        </Wrapper>
      ),
      {
        relay: {
          queries: {
            milestoneQuery: {
              type: 'fragment',
              query: graphql`
                query MilestoneListNoMatchesTestQuery @relay_test_operation {
                  node(id: "123") {
                    ... on Repository {
                      ...MilestoneList @dangerously_unaliased_fixme @arguments(first: 10, state: OPEN)
                    }
                  }
                }
              `,
              variables: {},
            },
          },
          mockResolvers: {
            PageInfo: () => ({
              hasNextPage: false,
              endCursor: null,
              startCursor: null,
              hasPreviousPage: false,
            }),
            MilestoneConnection: () => ({
              edges: [],
              totalCount: 1,
            }),
            Repository: () => ({
              nameWithOwner: 'test/repo',
              open: {
                totalCount: 0,
              },
              closed: {
                totalCount: 1,
              },
            }),
          },
        },
      },
    )
    expect(screen.queryByText(LABELS.createAMilestone)).not.toBeInTheDocument()
    expect(screen.getByText(LABELS.weCouldntFindMilestones)).toBeInTheDocument()
  })
})
