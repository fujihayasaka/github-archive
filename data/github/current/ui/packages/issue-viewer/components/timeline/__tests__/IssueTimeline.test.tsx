import {Wrapper} from '@github-ui/react-core/test-utils'
import {renderRelay} from '@github-ui/relay-test-utils'
import {graphql, requestSubscription} from 'relay-runtime'
import type {IssueTimelineTestQuery} from './__generated__/IssueTimelineTestQuery.graphql'
import {IssueTimeline} from '../IssueTimeline'
import type {IssueViewerIssue$data} from '../../__generated__/IssueViewerIssue.graphql'
import {ISSUE_VIEWER_DEFAULT_CONFIG} from '../../OptionConfig'
import {act, screen} from '@testing-library/react'
import {MockPayloadGenerator} from 'relay-test-utils'
import {makeIssueBaseFields} from '../../../test-utils/Mocks'
import {ErrorBoundary} from '@github-ui/react-core/error-boundary'
import {noop} from '@github-ui/noop'
import type {RelayMockEnvironment} from 'relay-test-utils/lib/RelayModernMockEnvironment'

jest.mock('@github-ui/feature-flags', () => ({
  ...jest.requireActual('@github-ui/feature-flags'),
  isFeatureEnabled: jest.fn(),
}))

const QUERY = graphql`
  query IssueTimelineTestQuery @relay_test_operation {
    repository(owner: "owner", name: "repo") {
      issue(number: 33) {
        ...IssueTimelineIssueFragment
      }
    }
  }
`

test('simple timeline with a few comments', async () => {
  renderRelay<{issue: IssueTimelineTestQuery}>(
    ({queryData}) => (
      <IssueTimeline
        issue={queryData.issue.repository!.issue as IssueViewerIssue$data}
        issueSecondary={undefined}
        highlightedEvent={undefined}
        viewer={null}
        onCommentChange={() => {}}
        onCommentReply={() => {}}
        onCommentEditCancel={() => {}}
        optionConfig={ISSUE_VIEWER_DEFAULT_CONFIG}
      />
    ),
    {
      relay: {
        queries: {
          issue: {
            type: 'fragment',
            query: QUERY,
            variables: {},
          },
        },
        mockResolvers: {
          Issue: () => ({
            ...makeIssueBaseFields(),
            frontTimelineItems: {
              edges: createComments(0, 20),
              totalCount: 20,
            },
            backTimelineItems: {
              edges: [],
              totalCount: 20,
            },
          }),
        },
      },
      wrapper: Wrapper,
    },
  )

  const timeline = screen.getByTestId('issue-timeline-container')
  expect(timeline).toBeInTheDocument()

  const timelineItemElements = timeline.childNodes

  expect(timelineItemElements).toHaveLength(20)

  for (let i = 0; i < 20; i++) {
    const timelineItem = timelineItemElements[i]
    expect(timelineItem).toHaveTextContent(`Comment number ${i}`)
  }
})

test('simple timeline with a few comments and some remaining', async () => {
  const {relayMockEnvironment} = renderRelay<{issue: IssueTimelineTestQuery}>(
    ({queryData}) => (
      <IssueTimeline
        issue={queryData.issue.repository!.issue as IssueViewerIssue$data}
        issueSecondary={undefined}
        highlightedEvent={undefined}
        viewer={null}
        onCommentChange={() => {}}
        onCommentReply={() => {}}
        onCommentEditCancel={() => {}}
        optionConfig={ISSUE_VIEWER_DEFAULT_CONFIG}
      />
    ),
    {
      relay: {
        queries: {
          issue: {
            type: 'fragment',
            query: QUERY,
            variables: {},
          },
        },
        mockResolvers: {
          Issue: () => ({
            ...makeIssueBaseFields(),
            id: 'testissue1',
            author: {
              id: 'testauthor1',
              __typename: 'Actor',
            },
            frontTimelineItems: {
              edges: createComments(0, 5),
              totalCount: 20,
            },
            backTimelineItems: {
              edges: [],
              totalCount: 20,
            },
          }),
        },
      },
      wrapper: Wrapper,
    },
  )

  let timeline = screen.getByTestId('issue-timeline-container')
  expect(timeline).toBeInTheDocument()

  let timelineItemElements = timeline.childNodes

  // In the initial render we expect to only see the front items (+ the load more element)
  expect(timelineItemElements).toHaveLength(6)

  for (let i = 0; i < 5; i++) {
    const timelineItem = timelineItemElements[i]
    expect(timelineItem).toHaveTextContent(`Comment number ${i}`)
  }

  expect(timelineItemElements[5]).toHaveTextContent('15 remaining items')

  // Here we resolve the secondary query for the back timeline items
  await act(async () => {
    relayMockEnvironment.mock.resolveMostRecentOperation(operation => {
      expect(operation.fragment.node.name).toBe('NewTimelinePaginationBackQuery')
      return MockPayloadGenerator.generate(operation, {
        ...makeIssueBaseFields(),
        Issue: () => ({
          ...makeIssueBaseFields(),
          id: 'testissue1',
          author: {
            id: 'testauthor1',
            __typename: 'Actor',
          },
          backTimelineItems: {
            edges: createComments(15, 5),
            totalCount: 20,
          },
        }),
      })
    })
  })

  timeline = screen.getByTestId('issue-timeline-container')
  expect(timeline).toBeInTheDocument()
  timelineItemElements = timeline.childNodes

  // Now we expect to see both the front and back items (+ the load more element)
  expect(timelineItemElements).toHaveLength(11)

  for (let i = 6; i < 11; i++) {
    const timelineItem = timelineItemElements[i]
    expect(timelineItem).toHaveTextContent(`Comment number ${i + 9}`)
  }
})

test('renders error message when frontTimelineItems is zero, but total is >0', async () => {
  try {
    jest.spyOn(console, 'error').mockImplementation()
    renderRelay<{issue: IssueTimelineTestQuery}>(
      ({queryData}) => (
        <ErrorBoundary
          fallback={<div data-testid="issue-timeline-container-error">Timeline Error</div>}
          onError={() => {}}
        >
          <IssueTimeline
            issue={queryData.issue.repository!.issue as IssueViewerIssue$data}
            issueSecondary={undefined}
            highlightedEvent={undefined}
            viewer={null}
            onCommentChange={() => {}}
            onCommentReply={() => {}}
            onCommentEditCancel={() => {}}
            optionConfig={ISSUE_VIEWER_DEFAULT_CONFIG}
          />
        </ErrorBoundary>
      ),
      {
        relay: {
          queries: {
            issue: {
              type: 'fragment',
              query: QUERY,
              variables: {},
            },
          },
          mockResolvers: {
            Issue: () => ({
              ...makeIssueBaseFields(),
              id: 'testissue1',
              author: {
                id: 'testauthor1',
                __typename: 'Actor',
              },
              frontTimelineItems: {
                edges: [],
                totalCount: 20,
              },
              backTimelineItems: {
                edges: [],
                totalCount: 20,
              },
            }),
          },
        },
        wrapper: Wrapper,
      },
    )
  } catch (e) {
    // eslint-disable-next-line jest/no-conditional-expect
    expect(e).toBeInstanceOf(Error)
  }

  const timeline = screen.getByTestId('issue-timeline-container-error')
  expect(timeline).toHaveTextContent('Timeline Error')
})

test('not querying the back items if everything was fetched in the front', async () => {
  const {relayMockEnvironment} = renderRelay<{issue: IssueTimelineTestQuery}>(
    ({queryData}) => (
      <IssueTimeline
        issue={queryData.issue.repository!.issue as IssueViewerIssue$data}
        issueSecondary={undefined}
        highlightedEvent={undefined}
        viewer={null}
        onCommentChange={() => {}}
        onCommentReply={() => {}}
        onCommentEditCancel={() => {}}
        optionConfig={ISSUE_VIEWER_DEFAULT_CONFIG}
      />
    ),
    {
      relay: {
        queries: {
          issue: {
            type: 'fragment',
            query: QUERY,
            variables: {},
          },
        },
        mockResolvers: {
          Issue: () => ({
            ...makeIssueBaseFields(),
            id: 'testissue1',
            author: {
              id: 'testauthor1',
              __typename: 'Actor',
            },
            frontTimelineItems: {
              edges: createComments(0, 5),
              totalCount: 5,
            },
            backTimelineItems: {
              edges: [],
              totalCount: 5,
            },
          }),
        },
      },
      wrapper: Wrapper,
    },
  )

  const timeline = screen.getByTestId('issue-timeline-container')
  expect(timeline).toBeInTheDocument()

  const timelineItemElements = timeline.childNodes

  // In the initial render we expect to only see the front items (but no load more element)
  expect(timelineItemElements).toHaveLength(5)

  for (let i = 0; i < 5; i++) {
    const timelineItem = timelineItemElements[i]
    expect(timelineItem).toHaveTextContent(`Comment number ${i}`)
  }

  // Here we check that the back items pagination query was NOT called
  await act(async () => {
    const lastOperation = relayMockEnvironment.mock.getMostRecentOperation()
    expect(lastOperation.fragment.node.name).not.toBe('NewTimelinePaginationBackQuery')
  })
})

test('timeline with a highlighted comment id that doesnt exist', async () => {
  const {relayMockEnvironment} = renderRelay<{issue: IssueTimelineTestQuery}>(
    ({queryData}) => (
      <IssueTimeline
        issue={queryData.issue.repository!.issue as IssueViewerIssue$data}
        issueSecondary={undefined}
        highlightedEvent={'issuecomment-notfound'}
        viewer={null}
        onCommentChange={() => {}}
        onCommentReply={() => {}}
        onCommentEditCancel={() => {}}
        optionConfig={ISSUE_VIEWER_DEFAULT_CONFIG}
      />
    ),
    {
      relay: {
        queries: {
          issue: {
            type: 'fragment',
            query: QUERY,
            variables: {},
          },
        },
        mockResolvers: {
          Issue: () => ({
            ...makeIssueBaseFields(),
            frontTimelineItems: {
              edges: createComments(0, 5),
              totalCount: 10,
            },
            backTimelineItems: {
              edges: [],
              totalCount: 0,
            },
          }),
        },
      },
      wrapper: Wrapper,
    },
  )

  await act(async () => {
    relayMockEnvironment.mock.resolveMostRecentOperation(operation => {
      expect(operation.fragment.variables.focusText).toBe('issuecomment-notfound')
      return MockPayloadGenerator.generate(operation, {
        Issue: () => ({
          timelineItems: {
            edges: [],
          },
        }),
      })
    })
  })

  const timeline = screen.getByTestId('issue-timeline-container')
  expect(timeline).toBeInTheDocument()

  const timelineItemElements = timeline.childNodes

  expect(timelineItemElements).toHaveLength(6)

  for (let i = 0; i < 5; i++) {
    const timelineItem = timelineItemElements[i]
    expect(timelineItem).toHaveTextContent(`Comment number ${i}`)
  }
  expect(timelineItemElements[5]).toHaveTextContent('5 remaining items')
})

test('timeline with a highlighted comment id, no neighbors', async () => {
  const pageSize = 5
  const totalComments = 20
  const highlightPosition = 9
  const neighbors = 0
  const hasLoadMoreFront = true
  const hasLoadMoreBack = true

  expect(
    await testTimelineWithHighlightedComment(
      totalComments,
      pageSize,
      highlightPosition,
      neighbors,
      hasLoadMoreFront,
      hasLoadMoreBack,
    ),
  ).toBe(true)
})

test('timeline with a highlighted comment id with neighbors', async () => {
  const pageSize = 5
  const totalComments = 20
  const highlightPosition = 9
  const neighbors = 2
  const hasLoadMoreFront = true
  const hasLoadMoreBack = true

  expect(
    await testTimelineWithHighlightedComment(
      totalComments,
      pageSize,
      highlightPosition,
      neighbors,
      hasLoadMoreFront,
      hasLoadMoreBack,
    ),
  ).toBe(true)
})

test('timeline with a highlighted comment id with neighbors that overlap with the front', async () => {
  const pageSize = 5
  const totalComments = 20
  const highlightPosition = 6
  const neighbors = 3
  const hasLoadMoreFront = false
  const hasLoadMoreBack = true

  expect(
    await testTimelineWithHighlightedComment(
      totalComments,
      pageSize,
      highlightPosition,
      neighbors,
      hasLoadMoreFront,
      hasLoadMoreBack,
    ),
  ).toBe(true)
})

test('timeline with a highlighted comment id with neighbors that overlap with the back', async () => {
  const pageSize = 5
  const totalComments = 20
  const highlightPosition = 15
  const neighbors = 3
  const hasLoadMoreFront = true
  const hasLoadMoreBack = false

  expect(
    await testTimelineWithHighlightedComment(
      totalComments,
      pageSize,
      highlightPosition,
      neighbors,
      hasLoadMoreFront,
      hasLoadMoreBack,
    ),
  ).toBe(true)
})

test('timeline with a highlighted comment id with neighbors that overlap with both the front and back', async () => {
  const pageSize = 5
  const totalComments = 12
  const highlightPosition = 7
  const neighbors = 3
  const hasLoadMoreFront = false
  const hasLoadMoreBack = false

  expect(
    await testTimelineWithHighlightedComment(
      totalComments,
      pageSize,
      highlightPosition,
      neighbors,
      hasLoadMoreFront,
      hasLoadMoreBack,
    ),
  ).toBe(true)
})

// This test was added for the issue https://github.com/github/issues/issues/13354
test('timeline with a highlighted comment and the front and back timelines overlap', async () => {
  const pageSize = 15
  const totalComments = 28
  const highlightPosition = 21
  const neighbors = 3
  const hasLoadMoreFront = false
  const hasLoadMoreBack = false

  expect(
    await testTimelineWithHighlightedComment(
      totalComments,
      pageSize,
      highlightPosition,
      neighbors,
      hasLoadMoreFront,
      hasLoadMoreBack,
    ),
  ).toBe(true)
})

// This function is used to test the timeline with a highlighted comment id
// It will render the timeline and check if the front/highlighted/back items are rendered correctly
// While it also checks if the load-more items are rendered correctly, we pass explicit assertions (hasLoadMoreFront/hasLoadMoreBack) to make the intent clearer
// This serves as a simple sanity check, as the full logic is quite complex
async function testTimelineWithHighlightedComment(
  totalComments: number,
  pageSize: number,
  highlightPosition: number,
  neighbors: number,
  hasLoadMoreFront: boolean,
  hasLoadMoreBack: boolean,
) {
  const {relayMockEnvironment} = renderRelay<{issue: IssueTimelineTestQuery}>(
    ({queryData}) => (
      <IssueTimeline
        issue={queryData.issue.repository!.issue as IssueViewerIssue$data}
        issueSecondary={undefined}
        highlightedEvent={'issuecomment-12345'}
        viewer={null}
        onCommentChange={() => {}}
        onCommentReply={() => {}}
        onCommentEditCancel={() => {}}
        optionConfig={ISSUE_VIEWER_DEFAULT_CONFIG}
      />
    ),
    {
      relay: {
        queries: {
          issue: {
            type: 'fragment',
            query: QUERY,
            variables: {},
          },
        },
        mockResolvers: {
          Issue: () => {
            const effectiveBackItemsSize = Math.min(totalComments - pageSize, pageSize)
            return {
              ...makeIssueBaseFields(),
              frontTimelineItems: {
                edges: createComments(0, pageSize),
                totalCount: totalComments,
              },
              backTimelineItems: {
                edges: createComments(totalComments - effectiveBackItemsSize, effectiveBackItemsSize),
                totalCount: totalComments,
              },
            }
          },
        },
      },
      wrapper: Wrapper,
    },
  )

  await act(async () => {
    relayMockEnvironment.mock.resolveMostRecentOperation(operation => {
      expect(operation.fragment.variables.focusText).toBe('issuecomment-12345')
      return MockPayloadGenerator.generate(operation, {
        ...makeIssueBaseFields(),
        Issue: () => ({
          timelineItems: {
            edges: createComments(highlightPosition - neighbors, 1 + neighbors * 2),
            beforeFocusCount: highlightPosition - neighbors,
            afterFocusCount: totalComments - highlightPosition - 1 - neighbors,
          },
        }),
      })
    })
  })

  const timeline = screen.getByTestId('issue-timeline-container')
  expect(timeline).toBeInTheDocument()

  const timelineItemElements = timeline.childNodes

  // [0, ..., pageSize - 1] are the front items
  for (let i = 0; i < pageSize; i++) {
    const timelineItem = timelineItemElements[i]
    expect(timelineItem).toHaveTextContent(`Comment number ${i}`)
  }

  // [pageSize] is the front load-more item
  const overlapFromBackItems = Math.max(highlightPosition - neighbors - (totalComments - pageSize), 0)
  let expectedRemainingItems = highlightPosition - pageSize - neighbors - overlapFromBackItems
  let plural = expectedRemainingItems > 1 ? 's' : ''
  // In case of an overlap, we wont render the load-more item
  expect(expectedRemainingItems > 0).toBe(hasLoadMoreFront)
  if (expectedRemainingItems > 0) {
    expect(timelineItemElements[pageSize]).toHaveTextContent(`${expectedRemainingItems} remaining item${plural}`)
  }

  // [pageSize + 1, pageSize + 1 + neighbors] are the neighbors before the highlighted item
  // [pageSize + 1 + neighbors + 1] is the highlighted item
  // [pageSize + 1 + neighbors + 2, pageSize + 1 + neighbors * 2] are the neighbors after the highlighted item
  const shiftForLoadMoreFront = expectedRemainingItems > 0 ? 1 : 0
  const frontOverlap = Math.max(pageSize + neighbors - highlightPosition, 0)
  const backOverlap = Math.max(highlightPosition + neighbors + 1 - (totalComments - pageSize), 0)

  for (let i = 0; i < 1 + neighbors * 2 - frontOverlap - backOverlap; i++) {
    expect(timelineItemElements[pageSize + shiftForLoadMoreFront + i]).toHaveTextContent(
      `Comment number ${highlightPosition - neighbors + i + frontOverlap}`,
    )
  }

  // [pageSize + 2 + neighbors * 2] is the back load-more item
  expectedRemainingItems = totalComments - pageSize - highlightPosition - 1 - neighbors + frontOverlap
  plural = expectedRemainingItems > 1 ? 's' : ''
  // In case of an overlap, we wont render the load-more item
  expect(expectedRemainingItems > 0).toBe(hasLoadMoreBack)
  if (expectedRemainingItems > 0) {
    expect(
      timelineItemElements[pageSize + 2 + neighbors * 2 - frontOverlap - (1 - shiftForLoadMoreFront)],
    ).toHaveTextContent(`${expectedRemainingItems} remaining item${plural}`)
  }

  // [pageSize + 3 + neighbors * 2, pageSize + 3 + neighbors * 2 + pageSize - 1] are the back items
  const shiftForLoadMoreBack = expectedRemainingItems > 0 ? 1 : 0
  const backFrontOverlap = Math.max(pageSize * 2 - totalComments, 0)
  const effectiveBackOverlap = backFrontOverlap > 0 ? backFrontOverlap : backOverlap
  for (let i = 0; i < pageSize - effectiveBackOverlap; i++) {
    const indexWhenFrontAndBackAreNotOverlappping =
      pageSize + 3 + neighbors * 2 + i - frontOverlap - (1 - shiftForLoadMoreFront) - (1 - shiftForLoadMoreBack)
    const indexWhenFrontAndBackOverlap = pageSize + i
    const itemIndex =
      backOverlap - effectiveBackOverlap > 0 ? indexWhenFrontAndBackOverlap : indexWhenFrontAndBackAreNotOverlappping

    const timelineItem = timelineItemElements[itemIndex]
    expect(timelineItem).toHaveTextContent(`Comment number ${totalComments - pageSize + i + effectiveBackOverlap}`)
  }

  return true
}

function createComments(startIndex: number, count: number) {
  const nodes = []
  for (let i = 0; i < count; i++) {
    nodes.push({
      node: {
        __typename: 'IssueComment',
        id: `comment${startIndex + i}`,
        databaseId: startIndex + i,
        body: `Comment number ${startIndex + i}`,
        bodyHTML: `Comment number ${startIndex + i}`,
        minimizedReason: null,
        isHidden: false,
        createdViaEmail: false,
        showSpammyBadge: false,
        authorToRepoOwnerSponsorship: null,
        reactionGroups: [],
        lastUserContentEdit: null,
        createdAt: '2022-01-01T00:00:00Z',
        repository: {
          id: 'test-repo-1',
          owner: {
            id: 'test-repo-owner',
            __typename: 'RepositoryOwner',
          },
        },
        author: {
          id: 'test-author-1',
          __typename: 'Actor',
        },
        issue: {
          id: 'test-issue-1',
        },
      },
    })
  }

  return nodes
}

const mockSubscription = (environment: RelayMockEnvironment, issueId: string) => {
  requestSubscription(environment, {
    subscription: graphql`
      subscription IssueTimelineTestSubscription($issueId: ID!) @relay_test_operation {
        issueUpdated(id: $issueId) {
          deletedCommentId @deleteRecord
        }
      }
    `,
    onNext: noop,
    onError: noop,
    variables: {issueId},
  })

  return environment.mock.getMostRecentOperation()
}

test('timeline updates when comment is deleted via subscription', async () => {
  const mockIssueId = 'test-issue-1'
  const mockAuthorId = 'test-author-1'
  const mockAuthor = {
    id: mockAuthorId,
    __typename: 'Actor',
  }
  const comments = createComments(0, 2)

  const {relayMockEnvironment} = renderRelay<{issue: IssueTimelineTestQuery}>(
    ({queryData}) => (
      <IssueTimeline
        issue={queryData.issue.repository!.issue as IssueViewerIssue$data}
        issueSecondary={undefined}
        highlightedEvent={undefined}
        viewer={'true'}
        onCommentChange={noop}
        onCommentReply={noop}
        onCommentEditCancel={noop}
        optionConfig={{
          ...ISSUE_VIEWER_DEFAULT_CONFIG,
          withLiveUpdates: true,
        }}
      />
    ),
    {
      relay: {
        queries: {
          issue: {
            type: 'fragment',
            query: QUERY,
            variables: {},
          },
        },
        mockResolvers: {
          Issue: () => ({
            id: mockIssueId,
            ...makeIssueBaseFields(),
            frontTimelineItems: {
              edges: comments,
              totalCount: 2,
            },
            backTimelineItems: {
              edges: [],
              totalCount: 2,
            },
            author: mockAuthor,
          }),
        },
      },
      wrapper: Wrapper,
    },
  )

  // Verify initial state has both comments
  const timeline = screen.getByTestId('issue-timeline-container')
  expect(timeline).toBeInTheDocument()
  expect(timeline.childNodes).toHaveLength(2)

  expect(timeline.childNodes[0]).toHaveTextContent('Comment number 0')
  expect(timeline.childNodes[1]).toHaveTextContent('Comment number 1')

  const subscriptionOperation = mockSubscription(relayMockEnvironment, mockIssueId)

  act(() => {
    relayMockEnvironment.mock.nextValue(
      subscriptionOperation,
      MockPayloadGenerator.generate(subscriptionOperation, {
        IssueUpdatedPayload: () => ({
          deletedCommentId: 'comment1',
        }),
      }),
    )
  })

  // Mock the `NewTimelinePaginationBackQuery` response to return only 1 comment
  act(() => {
    relayMockEnvironment.mock.resolveMostRecentOperation(operation => {
      expect(operation.fragment.node.name).toBe('NewTimelinePaginationBackQuery')
      return MockPayloadGenerator.generate(operation, {
        Issue: () => ({
          id: mockIssueId,
          backTimelineItems: {
            edges: [comments[0]],
            totalCount: 1,
          },
        }),
      })
    })
  })

  // Verify only first comment remains after deletion
  const updatedTimeline = screen.getByTestId('issue-timeline-container')
  expect(updatedTimeline.childNodes).toHaveLength(1)
  expect(updatedTimeline.childNodes[0]).toHaveTextContent('Comment number 0')
  expect(updatedTimeline.textContent).not.toContain('Comment number 1')
})
