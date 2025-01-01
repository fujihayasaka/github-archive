import {renderRelay} from '@github-ui/relay-test-utils'
import {OpenClosedMilestones} from '../OpenClosedMilestones'
import {graphql} from 'relay-runtime'
import {screen} from '@testing-library/react'
import {Wrapper} from '@github-ui/react-core/test-utils'

import type {OpenClosedMilestonesQuery} from './__generated__/OpenClosedMilestonesQuery.graphql'
import {IdProvider} from '@github-ui/list-view/ListViewIdContext'
import {VariantProvider} from '@github-ui/list-view/ListViewVariantContext'
import {TitleProvider} from '@github-ui/list-view/ListViewTitleContext'
import type {MockResolverContext} from 'relay-test-utils/lib/RelayMockPayloadGenerator'

describe('OpenClosedMilestones', () => {
  test('renders open closed headers', () => {
    renderRelay<{milestoneQuery: OpenClosedMilestonesQuery}>(
      ({queryData: {milestoneQuery}}) => (
        <Wrapper>
          <IdProvider>
            <VariantProvider>
              <TitleProvider title="milestone row">
                <OpenClosedMilestones repository={milestoneQuery.node!} />
              </TitleProvider>
            </VariantProvider>
          </IdProvider>
        </Wrapper>
      ),
      {
        relay: {
          queries: {
            milestoneQuery: {
              type: 'fragment',
              query: graphql`
                query OpenClosedMilestonesQuery @relay_test_operation {
                  node(id: "123") {
                    ... on Repository {
                      ...OpenClosedMilestones @dangerously_unaliased_fixme
                    }
                  }
                }
              `,
              variables: {},
            },
          },
          mockResolvers: {
            Int: (context: MockResolverContext) => {
              if (context.path?.join('.') === 'node.open.totalCount') {
                return 37
              }
              if (context.path?.join('.') === 'node.closed.totalCount') {
                return 12
              }
              return 0
            },
          },
        },
      },
    )

    const openTab = screen.getByTestId('open-milestone-tab')
    expect(openTab).toBeInTheDocument()
    expect(openTab).toHaveTextContent('Open')
    expect(openTab).toHaveTextContent('37')
    const closedTab = screen.getByTestId('closed-milestone-tab')
    expect(closedTab).toBeInTheDocument()
    expect(closedTab).toHaveTextContent('Closed')
    expect(closedTab).toHaveTextContent('12')
  })
})
