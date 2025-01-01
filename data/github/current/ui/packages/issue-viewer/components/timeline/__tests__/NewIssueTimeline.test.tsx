import {Wrapper} from '@github-ui/react-core/test-utils'
import {renderRelay} from '@github-ui/relay-test-utils'
import {graphql} from 'relay-runtime'
import type {NewIssueTimelineTestQuery} from './__generated__/NewIssueTimelineTestQuery.graphql'
import {NewIssueTimeline} from '../NewIssueTimeline'
import type {IssueViewerIssue$data} from '../../__generated__/IssueViewerIssue.graphql'
import {ISSUE_VIEWER_DEFAULT_CONFIG} from '../../OptionConfig'
import {act, screen} from '@testing-library/react'
import {MockPayloadGenerator} from 'relay-test-utils'
import {makeIssueBaseFields} from '../../../test-utils/Mocks'

const QUERY = graphql`
  query NewIssueTimelineTestQuery @relay_test_operation {
    repository(owner: "owner", name: "repo") {
      issue(number: 33) {
        ...NewIssueTimelineIssueFragment
      }
    }
  }
`

test('simple timeline with a few comments', async () => {
  renderRelay<{issue: NewIssueTimelineTestQuery}>(
    ({queryData}) => (
      <NewIssueTimeline
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
  renderRelay<{issue: NewIssueTimelineTestQuery}>(
    ({queryData}) => (
      <NewIssueTimeline
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
              edges: createComments(0, 5),
              totalCount: 20,
            },
            backTimelineItems: {
              edges: createComments(15, 5),
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

  expect(timelineItemElements).toHaveLength(11)

  for (let i = 0; i < 5; i++) {
    const timelineItem = timelineItemElements[i]
    expect(timelineItem).toHaveTextContent(`Comment number ${i}`)
  }

  expect(timelineItemElements[5]).toHaveTextContent('10 remaining items')

  for (let i = 6; i < 11; i++) {
    const timelineItem = timelineItemElements[i]
    expect(timelineItem).toHaveTextContent(`Comment number ${i + 9}`)
  }
})

test('timeline with a highlighted comment id that doesnt exist', async () => {
  const {relayMockEnvironment} = renderRelay<{issue: NewIssueTimelineTestQuery}>(
    ({queryData}) => (
      <NewIssueTimeline
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
  const {relayMockEnvironment} = renderRelay<{issue: NewIssueTimelineTestQuery}>(
    ({queryData}) => (
      <NewIssueTimeline
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
          Issue: () => ({
            ...makeIssueBaseFields(),
            frontTimelineItems: {
              edges: createComments(0, pageSize),
              totalCount: totalComments,
            },
            backTimelineItems: {
              edges: createComments(totalComments - pageSize, pageSize),
              totalCount: totalComments,
            },
          }),
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
  let expectedRemainingItems = highlightPosition - pageSize - neighbors
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

  for (let i = 0; i < 1 + neighbors * 2 - frontOverlap; i++) {
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
  const backOverlap = Math.max(highlightPosition + neighbors + 1 - (totalComments - pageSize), 0)
  for (let i = 0; i < pageSize - backOverlap; i++) {
    const timelineItem =
      timelineItemElements[
        pageSize + 3 + neighbors * 2 + i - frontOverlap - (1 - shiftForLoadMoreFront) - (1 - shiftForLoadMoreBack)
      ]
    expect(timelineItem).toHaveTextContent(`Comment number ${totalComments - pageSize + i + backOverlap}`)
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
      },
    })
  }

  return nodes
}
