import {render} from '@github-ui/react-core/test-utils'
import type {SafeHTMLString} from '@github-ui/safe-html'
import {act, screen} from '@testing-library/react'
import {useRef} from 'react'
import {fetchQuery, graphql, RelayEnvironmentProvider} from 'react-relay'
import {Observable} from 'relay-runtime'
import {createMockEnvironment} from 'relay-test-utils'

import {RefreshVideoWrapper} from '../RefreshVideoWrapper'

jest.mock('react-relay', () => ({
  ...jest.requireActual('react-relay'),
  fetchQuery: jest.fn(),
  useRelayEnvironment: jest.fn().mockReturnValue({}),
}))

const mockFetchQuery = jest.mocked(fetchQuery)

type TestComponentProps = {
  environment: ReturnType<typeof createMockEnvironment>
  id?: string
  bodyHTML?: SafeHTMLString
  getHTML?: (fetchResult: unknown) => string | undefined
}

const mockQuery = graphql`
  query RefreshVideoWrapperTestQuery @relay_test_operation {
    node(id: "test-id") {
      ... on Node {
        # eslint-disable-next-line relay/unused-fields
        id
      }
    }
  }
`

const getHTMLDefault = jest.fn().mockReturnValue('<video src="updated-src"></video>')

function TestComponent({
  environment,
  id = 'test-id',
  bodyHTML = '<video src="original-src" muted></video>' as SafeHTMLString,
  getHTML = getHTMLDefault,
}: TestComponentProps) {
  // Use React's useRef hook to create a proper ref
  const bodyRef = useRef<HTMLDivElement>(null)

  return (
    <RelayEnvironmentProvider environment={environment}>
      <RefreshVideoWrapper id={id} bodyHTML={bodyHTML} query={mockQuery} bodyRef={bodyRef} getHTML={getHTML}>
        <div>
          <div data-testid="markdown-body" ref={bodyRef}>
            {bodyHTML.includes('video') && <video src="original-src" muted />}
            {bodyHTML.includes('img') && <img src="original-img-src" alt="Test" />}
          </div>
        </div>
      </RefreshVideoWrapper>
    </RelayEnvironmentProvider>
  )
}

describe('RefreshVideoWrapper', () => {
  beforeEach(() => {
    jest.useFakeTimers()
  })

  afterEach(() => {
    jest.useRealTimers()
    jest.clearAllMocks()
  })

  test('updates video src on mouseover after timeout', async () => {
    const environment = createMockEnvironment()
    const mockResponse = {
      node: {
        bodyHTML: '<video src="updated-src"></video>',
      },
    }

    mockFetchQuery.mockImplementation(() =>
      Observable.create(sink => {
        sink.next(mockResponse)
        sink.complete()
      }),
    )

    const getHTML = jest.fn().mockReturnValue('<video src="updated-src"></video>')

    const {user} = render(
      <TestComponent
        environment={environment}
        bodyHTML={"<video src='original-src'></video>" as SafeHTMLString}
        getHTML={getHTML}
      />,
    )

    // Jump forward 5 minutes
    act(() => {
      jest.advanceTimersByTime(5 * 60 * 1000)
    })

    // Initial hover should trigger fetch
    const body = screen.getByTestId('markdown-body')
    await user.hover(body)

    expect(mockFetchQuery).toHaveBeenCalledTimes(1)
    expect(getHTML).toHaveBeenCalledTimes(1)

    // Reset mocks to test debouncing
    mockFetchQuery.mockClear()
    getHTML.mockClear()

    // Another hover immediately after should not trigger a fetch (debounce)
    await user.unhover(body)
    await user.hover(body)

    expect(mockFetchQuery).not.toHaveBeenCalled()
    expect(getHTML).not.toHaveBeenCalled()
  })

  test('respects refresh timeout between fetches', async () => {
    const environment = createMockEnvironment()
    const mockResponse = {
      node: {
        bodyHTML: '<video src="updated-src"></video>',
      },
    }

    mockFetchQuery.mockImplementation(() =>
      Observable.create(sink => {
        sink.next(mockResponse)
        sink.complete()
      }),
    )

    const getHTML = jest.fn().mockReturnValue('<video src="updated-src"></video>')

    const {user} = render(
      <TestComponent
        environment={environment}
        bodyHTML={"<video src='original-src'></video>" as SafeHTMLString}
        getHTML={getHTML}
      />,
    )

    expect(mockFetchQuery).not.toHaveBeenCalled()

    // Jump forward 5 minutes
    act(() => {
      jest.advanceTimersByTime(5 * 60 * 1000)
    })

    // User mouses over the body
    const body = screen.getByTestId('markdown-body')
    await user.hover(body)

    expect(mockFetchQuery).toHaveBeenCalledTimes(1)
    expect(getHTML).toHaveBeenCalledTimes(1)

    // Jump forward 5 minutes
    act(() => {
      jest.advanceTimersByTime(5 * 60 * 1000)
    })

    expect(mockFetchQuery).toHaveBeenCalledTimes(1)

    // Now the hover should trigger a fetch again
    await user.unhover(body)
    await user.hover(body)

    expect(mockFetchQuery).toHaveBeenCalledTimes(2)
    expect(getHTML).toHaveBeenCalledTimes(2)
  })

  test('does not update when html does not contain video or image tags', async () => {
    const environment = createMockEnvironment()
    const getHTML = jest.fn()

    const {user} = render(
      <TestComponent
        environment={environment}
        bodyHTML={'<p>Just text content</p>' as SafeHTMLString}
        getHTML={getHTML}
      />,
    )

    expect(mockFetchQuery).not.toHaveBeenCalled()

    // Wind the time on 5 minutes
    act(() => {
      jest.advanceTimersByTime(5 * 60 * 1000)
    })

    const body = screen.getByTestId('markdown-body')
    await user.hover(body)

    expect(mockFetchQuery).not.toHaveBeenCalled()
  })

  test('updates both image and video sources', async () => {
    const environment = createMockEnvironment()
    const mockResponse = {
      node: {
        bodyHTML: '<video src="updated-video-src"></video><img src="updated-img-src">',
      },
    }

    mockFetchQuery.mockImplementation(() =>
      Observable.create(sink => {
        sink.next(mockResponse)
        sink.complete()
      }),
    )

    const getHTML = jest.fn().mockReturnValue('<video src="updated-video-src"></video><img src="updated-img-src">')

    const {user} = render(
      <TestComponent
        environment={environment}
        bodyHTML={"<video src='original-video-src'></video><img src='original-img-src'>" as SafeHTMLString}
        getHTML={getHTML}
      />,
    )

    expect(mockFetchQuery).toHaveBeenCalledTimes(0)

    // Wind the time on 5 minutes
    act(() => {
      jest.advanceTimersByTime(5 * 60 * 1000)
    })

    const body = screen.getByTestId('markdown-body')
    await user.hover(body)

    expect(mockFetchQuery).toHaveBeenCalledTimes(1)
    expect(getHTML).toHaveBeenCalledTimes(1)
  })
})
