import {mockClientEnv} from '@github-ui/client-env/mock'
import {isFeatureEnabled} from '@github-ui/feature-flags'
import {noop} from '@github-ui/noop'
import {render} from '@github-ui/react-core/test-utils'
import {renderRelay} from '@github-ui/relay-test-utils'
import {ComponentWithLazyLoadQuery} from '@github-ui/relay-test-utils/RelayComponents'
import {act, fireEvent, screen} from '@testing-library/react'
import {type ComponentProps, Suspense} from 'react'
import {fetchQuery, graphql, RelayEnvironmentProvider} from 'react-relay'
import {Observable} from 'relay-runtime'
import {createMockEnvironment, MockPayloadGenerator} from 'relay-test-utils'

import {makeIssueCommentBaseTypes} from '../../../test-utils/relay-type-mocks'
import type {SelectionContext} from '../../../utils/quotes'
import type {IssueCommentViewerCommentRow$key} from '../__generated__/IssueCommentViewerCommentRow.graphql'
import type {IssueCommentViewerReactable$key} from '../__generated__/IssueCommentViewerReactable.graphql'
import {IssueCommentViewer} from '../IssueCommentViewer'
import type {IssueCommentViewerCommentTestQuery} from './__generated__/IssueCommentViewerCommentTestQuery.graphql'

type TestComponentProps = {
  environment: ReturnType<typeof createMockEnvironment>
} & Partial<Omit<ComponentProps<typeof IssueCommentViewer>, 'comment'>>

const selectQuoteFromCommentMock = jest.fn()
jest.mock('../../../utils/quotes', () => ({
  selectQuoteFromComment: (comment: HTMLDivElement | null | undefined, selection: SelectionContext | null) =>
    selectQuoteFromCommentMock(comment, selection),
}))

beforeEach(() => {
  mockClientEnv({
    login: 'monalisa',
  })
})

jest.mock('@github-ui/feature-flags', () => ({
  isFeatureEnabled: jest.fn(),
}))
const mockIsFeatureEnabled = jest.mocked(isFeatureEnabled)

beforeEach(() => {
  mockIsFeatureEnabled.mockReturnValue(false)
})

const query = graphql`
  query IssueCommentViewerCommentTestQuery($commentId: ID!) @relay_test_operation {
    comment: node(id: $commentId) {
      ... on IssueComment {
        ...IssueCommentViewerCommentRow @dangerously_unaliased_fixme
        ...IssueCommentViewerReactable @dangerously_unaliased_fixme
      }
    }
  }
`

function TestComponent({environment, ...componentProps}: TestComponentProps) {
  const propsWithDefault = {
    setIsEditing: noop,
    onReply: noop,
    navigate: noop,
    ...componentProps,
  }
  const queryVariables = {
    commentId: 'IC_kwAEAg',
  }
  const createComponent = (data: unknown) => (
    <IssueCommentViewer
      comment={(data as {comment: IssueCommentViewerCommentRow$key}).comment}
      reactable={(data as {comment: IssueCommentViewerReactable$key}).comment}
      {...propsWithDefault}
    />
  )
  return (
    <RelayEnvironmentProvider environment={environment}>
      <Suspense fallback="...Loading">
        <ComponentWithLazyLoadQuery dataToComponent={createComponent} query={query} queryVariables={queryVariables} />
      </Suspense>
    </RelayEnvironmentProvider>
  )
}

it('onReplySelect bubbles up the quoted comment body', async () => {
  const environment = createMockEnvironment()
  const onReplySelectMock = jest.fn()
  selectQuoteFromCommentMock.mockReturnValue('quoted text')

  render(<TestComponent environment={environment} onReply={onReplySelectMock} />)
  await act(async () =>
    environment.mock.resolveMostRecentOperation(operation =>
      MockPayloadGenerator.generate(operation, {
        ...makeIssueCommentBaseTypes(),
        IssueComment() {
          return {isHidden: false, viewerCanUpdate: true}
        },
      }),
    ),
  )

  const commentAction = screen.getByLabelText(/Comment actions/)
  expect(commentAction).toBeInTheDocument()
  // eslint-disable-next-line testing-library/prefer-user-event
  fireEvent.click(commentAction)

  const quoteReplyAction = screen.getByText('Quote reply')
  expect(quoteReplyAction).toBeInTheDocument()
  // eslint-disable-next-line testing-library/prefer-user-event
  fireEvent.click(quoteReplyAction)

  expect(selectQuoteFromCommentMock).toHaveBeenCalledTimes(1)
  expect(onReplySelectMock).toHaveBeenCalledTimes(1)
  expect(onReplySelectMock).toHaveBeenCalledWith('quoted text')
})

// Mock fetchQuery
jest.mock('relay-runtime', () => ({
  ...jest.requireActual('relay-runtime'),
  fetchQuery: jest.fn(),
}))

test('refetchHtml is called after hover', async () => {
  jest.useFakeTimers()
  mockIsFeatureEnabled.mockReturnValue(true)
  const environment = createMockEnvironment()
  const mathAbsSpy = jest.spyOn(Math, 'abs')

  const mockResponse = {
    node: {
      body: '<video role="video" src="new-test" />',
      bodyHTML: '<video role="video" src="new-test" />',
    },
  }

  // Mock fetchQuery to return a RelayObservable
  ;(fetchQuery as jest.Mock).mockImplementation(() =>
    Observable.create(sink => {
      sink.next(mockResponse)
      sink.complete()
    }),
  )

  const {user} = renderRelay<{issueBody: IssueCommentViewerCommentTestQuery}>(
    () => <TestComponent environment={environment} />,
    {
      relay: {
        queries: {
          issueBody: {
            type: 'fragment',
            query,
            variables: {
              commentId: 'IC_kwAEAg',
            },
          },
        },
      },
    },
  )
  await act(async () =>
    environment.mock.resolveMostRecentOperation(operation =>
      MockPayloadGenerator.generate(operation, {
        ...makeIssueCommentBaseTypes(),
        IssueComment() {
          return {
            isHidden: false,
            viewerCanUpdate: true,
            body: '<video role="video" src="test" />',
            bodyHTML: '<video role="video" src="test" />',
          }
        },
      }),
    ),
  )

  // Go 60 minutes into the future, we shouldn't trigger a refetch however till the user does something
  await act(async () => jest.advanceTimersByTime(260 * 60 * 1000))
  expect(fetchQuery).not.toHaveBeenCalled()

  // User mouses over the body
  const body = screen.getByTestId('markdown-body')
  await user.hover(body)
  // Test the debounced method is called
  expect(mathAbsSpy).toHaveBeenCalled()

  // The updated body is fetched and the src tags updated - and only called once
  expect(fetchQuery).toHaveBeenCalledTimes(1)

  // Check the src of the video has been updated
  const src = screen.getByRole('video').getAttribute('src')
  expect(src).toBe('new-test')

  // Wait for 2 seconds
  await act(async () => jest.advanceTimersByTime(2000))

  mathAbsSpy.mockRestore()
  await user.hover(screen.getByTestId('markdown-body'))
  expect(mathAbsSpy).not.toHaveBeenCalled()
})
