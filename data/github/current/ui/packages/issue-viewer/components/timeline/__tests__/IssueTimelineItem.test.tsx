import {screen} from '@testing-library/react'
import {IssueTimelineItem, TimelineItemFragment} from '../IssueTimelineItem'
import {noop} from '@github-ui/noop'
import {renderRelay} from '@github-ui/relay-test-utils'
import {graphql, readInlineData} from 'relay-runtime'
import type {RelayMockProps, TestComponentProps} from '@github-ui/relay-test-utils/RelayTestFactories'
import type {IssueTimelineItemTestQuery} from './__generated__/IssueTimelineItemTestQuery.graphql'
import type {IssueTimelineItem$key} from '../__generated__/IssueTimelineItem.graphql'
import {rollupEvents} from '../../../utils/timeline-rollups'

type IssueTimelineItemQueries = {
  event: IssueTimelineItemTestQuery
}
const baseRelayMock: RelayMockProps<IssueTimelineItemQueries> = {
  queries: {
    event: {
      type: 'fragment',
      query: graphql`
        query IssueTimelineItemTestQuery($id: ID!) @relay_test_operation {
          node(id: $id) {
            ...IssueTimelineItem
          }
        }
      `,
      variables: {
        id: 'issue_id',
      },
    },
  },
}
const renderComponent = ({queryData}: TestComponentProps<IssueTimelineItemQueries>) => {
  const node = queryData.event.node!
  // eslint-disable-next-line no-restricted-syntax
  const data = readInlineData<IssueTimelineItem$key>(TimelineItemFragment, node)
  const [rollupItem] = rollupEvents([data])

  return (
    <IssueTimelineItem
      item={rollupItem!}
      issueId={''}
      repositoryId={''}
      repositoryNameWithOwner={''}
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
    renderRelay<IssueTimelineItemQueries>(renderComponent, {
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
    renderRelay<IssueTimelineItemQueries>(renderComponent, {
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

describe('author details', () => {
  test('shows ghost avatar if author is missing', () => {
    renderRelay<IssueTimelineItemQueries>(renderComponent, {
      relay: {
        ...baseRelayMock,
        mockResolvers: {
          IssueComment() {
            return {
              author: null,
            }
          },
        },
      },
    })

    const ghostUser = screen.getByAltText('ghost')
    expect(ghostUser).toBeTruthy()
  })

  test('shows author details correctly', () => {
    renderRelay<IssueTimelineItemQueries>(renderComponent, {
      relay: {
        ...baseRelayMock,
        mockResolvers: {
          IssueComment() {
            return {
              author: {
                avatarUrl: '/monalisa.png',
                login: 'monalisa',
              },
            }
          },
        },
      },
    })

    const author = screen.getByAltText('monalisa')
    expect(author).toBeTruthy()
  })
})
