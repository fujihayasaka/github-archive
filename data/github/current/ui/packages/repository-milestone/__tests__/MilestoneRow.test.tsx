import {renderRelay} from '@github-ui/relay-test-utils'
import {MilestoneRow} from '../MilestoneRow'
import {graphql} from 'relay-runtime'
import {screen} from '@testing-library/react'
import {Wrapper} from '@github-ui/react-core/test-utils'

import type {MilestoneRowQuery} from './__generated__/MilestoneRowQuery.graphql'
import {IdProvider} from '@github-ui/list-view/ListViewIdContext'
import {VariantProvider} from '@github-ui/list-view/ListViewVariantContext'
import {TitleProvider} from '@github-ui/list-view/ListViewTitleContext'

describe('MilestoneRow', () => {
  test('renders milestone row', () => {
    renderRelay<{milestoneQuery: MilestoneRowQuery}>(
      ({queryData: {milestoneQuery}}) => (
        <Wrapper>
          <IdProvider>
            <VariantProvider>
              <TitleProvider title="milestone row">
                <MilestoneRow milestone={milestoneQuery.node!} repositoryNameWithOwner="github/github" />
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
                query MilestoneRowQuery @relay_test_operation {
                  node(id: "123") {
                    ... on Milestone {
                      ...MilestoneRow @dangerously_unaliased_fixme
                    }
                  }
                }
              `,
              variables: {},
            },
          },
          mockResolvers: {
            Milestone: () => ({
              title: 'release',
              description: 'next version',
            }),
          },
        },
      },
    )

    expect(screen.getByText('release')).toBeInTheDocument()
    expect(screen.getByText('next version')).toBeInTheDocument()
  })
})
