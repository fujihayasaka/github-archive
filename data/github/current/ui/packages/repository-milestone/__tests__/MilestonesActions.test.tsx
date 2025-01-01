import {renderRelay} from '@github-ui/relay-test-utils'
import {MilestonesActions} from '../MilestonesActions'
import {graphql} from 'relay-runtime'
import {screen} from '@testing-library/react'
import {Wrapper} from '@github-ui/react-core/test-utils'

import type {MilestonesActionsQuery} from './__generated__/MilestonesActionsQuery.graphql'
import {IdProvider} from '@github-ui/list-view/ListViewIdContext'
import {VariantProvider} from '@github-ui/list-view/ListViewVariantContext'
import {TitleProvider} from '@github-ui/list-view/ListViewTitleContext'

const renderMilestoneActions = (viewerCanPush: boolean) =>
  renderRelay<{milestoneQuery: MilestonesActionsQuery}>(
    ({queryData: {milestoneQuery}}) => (
      <Wrapper>
        <IdProvider>
          <VariantProvider>
            <TitleProvider title="milestone row">
              <MilestonesActions repositoryRef={milestoneQuery.node!} />
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
              query MilestonesActionsQuery @relay_test_operation {
                node(id: "123") {
                  ... on Repository {
                    ...MilestonesActions @dangerously_unaliased_fixme
                  }
                }
              }
            `,
            variables: {},
          },
        },
        mockResolvers: {
          Repository: () => ({
            title: 'release',
            viewerCanPush,
          }),
        },
      },
    },
  )

describe('Milestones Actions', () => {
  test('renders milestone actions', () => {
    renderMilestoneActions(true)
    expect(screen.getByTestId('new-milestone-button')).toBeInTheDocument()
  })

  test('does not render milestone actions', () => {
    renderMilestoneActions(false)
    expect(screen.queryByTestId('new-milestone-button')).not.toBeInTheDocument()
  })
})
