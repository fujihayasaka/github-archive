import {screen} from '@testing-library/react'
import {NewIssueTimelineItem, TimelineItemFragment} from '../NewIssueTimelineItem'
import {noop} from '@github-ui/noop'
import {renderRelay} from '@github-ui/relay-test-utils'
import {graphql, readInlineData} from 'relay-runtime'
import type {RelayMockProps, TestComponentProps} from '@github-ui/relay-test-utils/RelayTestFactories'
import type {NewIssueTimelineItemTestQuery} from './__generated__/NewIssueTimelineItemTestQuery.graphql'
import type {NewIssueTimelineItem$key} from '../__generated__/NewIssueTimelineItem.graphql'
import {rollupEvents} from '../../../utils/timeline-rollups'

type NewIssueTimelineItemQueries = {
  event: NewIssueTimelineItemTestQuery
}
const baseRelayMock: RelayMockProps<NewIssueTimelineItemQueries> = {
  queries: {
    event: {
      type: 'fragment',
      query: graphql`
        query NewIssueTimelineItemTestQuery($id: ID!) @relay_test_operation {
          node(id: $id) {
            ...NewIssueTimelineItem
          }
        }
      `,
      variables: {
        id: 'issue_id',
      },
    },
  },
}
const renderComponent = ({queryData}: TestComponentProps<NewIssueTimelineItemQueries>) => {
  // eslint-disable-next-line no-restricted-syntax
  const data = readInlineData<NewIssueTimelineItem$key>(TimelineItemFragment, queryData.event.node!)
  const [rollupItem] = rollupEvents([data])

  return (
    <NewIssueTimelineItem
      item={rollupItem!}
      issueId={''}
      repositoryId={''}
      issueUrl={''}
      viewer={null}
      onCommentChange={noop}
      onCommentReply={noop}
      onCommentEditCancel={noop}
      optionConfig={{
        navigate: noop,
      }}
    />
  )
}

describe('component adds data attributes for a11y focus behaviors', () => {
  test('in comments', () => {
    const mockId = 'issue-comment-1'
    renderRelay<NewIssueTimelineItemQueries>(renderComponent, {
      relay: {
        ...baseRelayMock,
        mockResolvers: {
          IssueComment() {
            return {
              id: mockId,
            }
          },
        },
      },
    })

    const eventContainer = screen.getByTestId(`timeline-row-border-${mockId}`)
    expect(eventContainer).toHaveAttribute('data-timeline-event-id', mockId)
  })

  test('in other events', () => {
    const mockId = 'assigned-event-1'
    renderRelay<NewIssueTimelineItemQueries>(renderComponent, {
      relay: {
        ...baseRelayMock,
        mockResolvers: {
          Node: () => ({
            __typename: 'AssignedEvent',
          }),
          AssignedEvent: () => ({
            id: mockId,
          }),
        },
      },
    })

    const eventContainer = screen.getByTestId(`timeline-row-border-${mockId}`)
    expect(eventContainer).toHaveAttribute('data-timeline-event-id', mockId)
  })
})
