import {graphql} from 'relay-runtime'
import {renderRelay} from '@github-ui/relay-test-utils'
import {screen} from '@testing-library/react'
import {ClosedEvent} from '../ClosedEvent'
import type {ClosedEventTestQuery} from './__generated__/ClosedEventTestQuery.graphql'
import {useFeatureFlags} from '@github-ui/react-core/use-feature-flag'

jest.mock('@github-ui/react-core/use-feature-flag')
const mockUseFeatureFlags = jest.mocked(useFeatureFlags)

beforeEach(() => {
  mockUseFeatureFlags.mockReturnValue({})
})

test('renders auto-close workflow closed issue event', () => {
  setupEnvironment()

  expect(screen.getByTestId('closer-link')).toHaveAttribute('href', 'monalisa-project-url')
  expect(screen.getByTestId('closer-link')).toHaveTextContent('monalisa-project')
})

describe('state reason', () => {
  test('renders close issue as completed', () => {
    setupEnvironment({stateReason: 'COMPLETED'})
    expect(screen.getByText(/closed this as/)).toBeInTheDocument()
    expect(screen.getByTestId('state-reason-link')).toHaveTextContent('completed')
  })

  test('renders close issue as not planned', () => {
    setupEnvironment({stateReason: 'NOT_PLANNED'})
    expect(screen.getByText(/closed this as/)).toBeInTheDocument()
    expect(screen.getByTestId('state-reason-link')).toHaveTextContent('not planned')
  })

  test('renders close issue as duplicate when issues_react_close_as_duplicate is enabled', () => {
    mockUseFeatureFlags.mockReturnValue({issues_react_close_as_duplicate: true})

    setupEnvironment({stateReason: 'DUPLICATE'})
    expect(screen.getByText(/closed this as a/)).toBeInTheDocument()
    expect(screen.getByTestId('state-reason-link')).toHaveTextContent('duplicate')
  })

  test('renders close issue as duplicate when issues_react_close_as_duplicate is disabled', () => {
    mockUseFeatureFlags.mockReturnValue({issues_react_close_as_duplicate: false})

    setupEnvironment({stateReason: 'DUPLICATE'})
    expect(screen.getByTestId('state-reason-link')).toHaveTextContent('not planned')
  })
})

function setupEnvironment({
  stateReason = 'COMPLETED',
}: {stateReason?: 'COMPLETED' | 'DUPLICATE' | 'NOT_PLANNED' | 'REOPENED'} = {}) {
  renderRelay<{query: ClosedEventTestQuery}>(
    ({queryData}) => (
      <ClosedEvent
        queryRef={queryData.query.node!}
        timelineEventBaseUrl="timelinetest"
        issueUrl="test"
        repositoryId="id"
      />
    ),
    {
      relay: {
        queries: {
          query: {
            type: 'fragment',
            query: graphql`
              query ClosedEventTestQuery @relay_test_operation {
                node(id: "node-id") {
                  ... on ClosedEvent {
                    ...ClosedEvent
                  }
                }
              }
            `,
            variables: {},
          },
        },
        mockResolvers: {
          Node() {
            return {
              stateReason,
              createdAt: '2024-01-01T00:00:00Z',
              closer: {
                __typename: 'ProjectV2',
                title: 'monalisa-project',
                url: 'monalisa-project-url',
              },
              closingProjectItemStatus: 'Done',
            }
          },
        },
      },
    },
  )
}
