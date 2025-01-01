import {renderRelay} from '@github-ui/relay-test-utils'
import {MilestoneDate} from '../MilestoneDate'
import {graphql} from 'relay-runtime'
import {screen} from '@testing-library/react'
import {Wrapper} from '@github-ui/react-core/test-utils'

import type {MilestoneDateQuery} from './__generated__/MilestoneDateQuery.graphql'
import {IdProvider} from '@github-ui/list-view/ListViewIdContext'
import {VariantProvider} from '@github-ui/list-view/ListViewVariantContext'
import {TitleProvider} from '@github-ui/list-view/ListViewTitleContext'

const renderMilestoneDate = (dueOn: string | null) =>
  renderRelay<{milestoneQuery: MilestoneDateQuery}>(
    ({queryData: {milestoneQuery}}) => (
      <Wrapper>
        <IdProvider>
          <VariantProvider>
            <TitleProvider title="milestone row">
              <MilestoneDate milestone={milestoneQuery.node!} />
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
              query MilestoneDateQuery @relay_test_operation {
                node(id: "123") {
                  ... on Milestone {
                    ...MilestoneDate @dangerously_unaliased_fixme
                  }
                }
              }
            `,
            variables: {},
          },
        },
        mockResolvers: {
          Milestone: () => ({
            dueOn,
          }),
        },
      },
    },
  )

describe('MilestoneDate', () => {
  test('renders milestone date', () => {
    renderMilestoneDate('2044-08-30T00:00:00Z')

    expect(screen.getByText(/Due by/)).toBeInTheDocument()
  })

  test('renders overdue milestone', () => {
    renderMilestoneDate('2022-08-30T00:00:00Z')

    expect(screen.getByText(/Overdue by/)).toBeInTheDocument()
    expect(screen.getByText(/year/)).toBeInTheDocument()
  })

  test('renders milestone with no due date', () => {
    renderMilestoneDate(null)

    expect(screen.getByText(/No due date/)).toBeInTheDocument()
  })

  test('renders milestone due in the future', () => {
    renderMilestoneDate('2044-08-30T00:00:00Z')

    expect(screen.getByText(/Due by/)).toBeInTheDocument()
    expect(screen.getByText(/2044/)).toBeInTheDocument()
  })
})
