import {renderRelay} from '@github-ui/relay-test-utils'
import {graphql} from 'relay-runtime'
import {screen} from '@testing-library/react'
import {RepositoryMilestonesInternal} from '../RepositoryMilestones'
import type {RepositoryMilestonesTestQuery} from './__generated__/RepositoryMilestonesTestQuery.graphql'
import type {RelayMockProps} from '@github-ui/relay-test-utils/RelayTestFactories'
import {LABELS} from '../constants/labels'
import {Wrapper} from '@github-ui/react-core/test-utils'

type MilestoneQueries = {
  milestoneQuery: RepositoryMilestonesTestQuery
}

const baseConfig: RelayMockProps<MilestoneQueries> = {
  queries: {
    milestoneQuery: {
      type: 'fragment',
      query: graphql`
        query RepositoryMilestonesTestQuery @relay_test_operation {
          node(id: "123") {
            ... on Repository {
              ...RepositoryMilestonesInternal @dangerously_unaliased_fixme @arguments(state: OPEN)
            }
          }
        }
      `,
      variables: {},
    },
  },
}

describe('MilestoneList', () => {
  test('renders milestone List', () => {
    renderRelay<{milestoneQuery: RepositoryMilestonesTestQuery}>(
      ({queryData: {milestoneQuery}}) => (
        <Wrapper>
          <RepositoryMilestonesInternal repository={milestoneQuery.node!} />
        </Wrapper>
      ),
      {
        relay: {
          ...baseConfig,
          mockResolvers: {
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

    expect(screen.getByText('release')).toBeInTheDocument()
    expect(screen.getByText('bugs')).toBeInTheDocument()
  })

  test('renders error fallback if no milestones are rendered', () => {
    jest.spyOn(console, 'error').mockImplementation()
    renderRelay<{milestoneQuery: RepositoryMilestonesTestQuery}>(
      ({queryData: {milestoneQuery}}) => (
        <Wrapper>
          <RepositoryMilestonesInternal repository={milestoneQuery.node!} />
        </Wrapper>
      ),
      {
        relay: {
          ...baseConfig,
          mockResolvers: {
            Repository: () => ({
              milestones: null,
            }),
          },
        },
      },
    )

    expect(screen.getByText(LABELS.milestonesError)).toBeInTheDocument()
  })
})
