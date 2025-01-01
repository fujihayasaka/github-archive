import {renderRelay} from '@github-ui/relay-test-utils'
import {graphql, requestSubscription} from 'relay-runtime'
import {HeaderBlockedBySummary} from '../HeaderBlockedBySummary'
import {act, screen} from '@testing-library/react'
import type {HeaderBlockedBySummaryTestQuery} from './__generated__/HeaderBlockedBySummaryTestQuery.graphql'
import type {RelayMockProps} from '@github-ui/relay-test-utils/RelayTestFactories'
import {noop} from '@github-ui/noop'
import {MockPayloadGenerator} from 'relay-test-utils'
import type {RelayMockEnvironment} from 'relay-test-utils/lib/RelayModernMockEnvironment'

const mockIssueViewerSubscription = (environment: RelayMockEnvironment) => {
  requestSubscription(environment, {
    subscription: graphql`
      subscription HeaderBlockedBySummarySubscription_IssueViewerSubscription($id: ID!) @relay_test_operation {
        issueUpdated(id: $id) {
          issueDependenciesSummaryUpdated {
            ...HeaderBlockedBySummary
          }
        }
      }
    `,
    onNext: noop,
    onError: noop,
    variables: {id: 'issue_id'},
  })

  return environment.mock.getMostRecentOperation()
}

type HeaderBlockedBySummaryQueries = {
  headerBlockedBySummary: HeaderBlockedBySummaryTestQuery
}

const baseRelayMock: RelayMockProps<HeaderBlockedBySummaryQueries> = {
  queries: {
    headerBlockedBySummary: {
      type: 'fragment',
      query: graphql`
        query HeaderBlockedBySummaryTestQuery($id: ID!) @relay_test_operation {
          node(id: $id) {
            ... on Issue {
              # Include ID to correctly resolve the node with the Issue mockResolver
              # eslint-disable-next-line relay/unused-fields
              id
              ...HeaderBlockedBySummary @dangerously_unaliased_fixme
            }
          }
        }
      `,
      variables: {
        id: 'issue_id',
      },
    },
  },
}

const setup = ({
  summary = {blockedBy: 3},
  small = false,
  state = 'OPEN',
}: {
  summary?: {blockedBy: number} | null
  small?: boolean
  state?: 'OPEN' | 'CLOSED'
}) => {
  const {relayMockEnvironment, container} = renderRelay<{headerBlockedBySummary: HeaderBlockedBySummaryTestQuery}>(
    ({queryData}) => {
      return (
        <HeaderBlockedBySummary
          blockedBySecondaryKey={queryData.headerBlockedBySummary.node ?? undefined}
          size={small ? 'small' : undefined}
        />
      )
    },
    {
      relay: {
        ...baseRelayMock,
        mockResolvers: {
          Issue: ({path}) => {
            if (path?.includes('blockedBy')) {
              return {
                id: 'blocking_issue_id',
                title: 'Blocking issue',
                number: 2,
                url: 'http://issue.com',
              }
            }

            return {
              id: 'issue_id',
              state,
              issueDependenciesSummary: summary,
              blockedBy: summary?.blockedBy === 1 ? {nodes: [{id: 'blocking_issue_id'}]} : null,
            }
          },
        },
      },
    },
  )

  return {environment: relayMockEnvironment, container}
}

describe('HeaderBlockedBySummary', () => {
  test('renders blockedBy count', () => {
    setup({})
    const blockedByCount = screen.getByText(/Blocked by 3/, {ignore: 'span.sr-only'})
    expect(blockedByCount).toBeInTheDocument()
  })

  test('renders blockedBy count when small size', () => {
    setup({small: true})
    const blockedByCount = screen.getByText('3', {ignore: 'span.sr-only'})
    expect(blockedByCount).toBeInTheDocument()
  })

  test('does not render if blockedBy is null', () => {
    const {container} = setup({summary: null})
    expect(container).toBeEmptyDOMElement()
  })

  test('does not render if blockedBy is 0', () => {
    const {container} = setup({summary: {blockedBy: 0}})
    expect(container).toBeEmptyDOMElement()
  })

  test('does not render if issue is closed', () => {
    const {container} = setup({summary: {blockedBy: 3}, state: 'CLOSED'})
    expect(container).toBeEmptyDOMElement()
  })

  test('live updates when summary is updated', () => {
    const {environment} = setup({})
    const subscriptionOperation = mockIssueViewerSubscription(environment)

    let blockedByCount = screen.getByText(/Blocked by 3/, {ignore: 'span.sr-only'})
    expect(blockedByCount).toBeInTheDocument()

    act(() => {
      environment.mock.nextValue(
        subscriptionOperation,
        MockPayloadGenerator.generate(subscriptionOperation, {
          Issue: () => ({
            id: 'issue_id',
            state: 'OPEN',
            issueDependenciesSummary: {
              blockedBy: 2,
            },
          }),
        }),
      )
    })

    blockedByCount = screen.getByText(/Blocked by 2/, {ignore: 'span.sr-only'})
    expect(blockedByCount).toBeInTheDocument()
  })

  test('renders issue title with link when blockedBy count is 1', () => {
    setup({summary: {blockedBy: 1}})
    const link = screen.getByLabelText(/Blocked by issue/, {selector: 'a'})
    expect(link).toBeInTheDocument()
    expect(link).toHaveTextContent('Blocking issue')
    expect(link).toHaveAttribute('href', 'http://issue.com')
  })

  test('renders issue number with link when blockedBy count is 1 and small size', () => {
    setup({summary: {blockedBy: 1}, small: true})
    const link = screen.getByLabelText(/Blocked by issue/, {selector: 'a'})
    expect(link).toBeInTheDocument()
    expect(link).toHaveTextContent('#2')
    expect(link).toHaveAttribute('href', 'http://issue.com')
  })
})
