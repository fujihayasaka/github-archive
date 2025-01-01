import {useRef} from 'react'
import {render} from '@github-ui/react-core/test-utils'
import type {PreloadedQueryBoundaryProps} from '../PreloadedQueryBoundary'
import PreloadedQueryBoundary from '../PreloadedQueryBoundary'
import {screen} from '@testing-library/react'
// eslint-disable-next-line no-restricted-imports
import {reportError} from '@github-ui/failbot'

jest.mock('@github-ui/failbot', () => ({
  reportError: jest.fn(),
}))

function ErrorsOnSecondRenderBase({skipReport}: {skipReport: boolean}) {
  const renderCountRef = useRef(0)
  renderCountRef.current++

  if (renderCountRef.current >= 2) {
    const error = new Error('Test error') as Error & {shouldSkipReport?: boolean}
    if (skipReport) {
      error.shouldSkipReport = true
    }
    throw error
  }

  return <span>No error</span>
}

function ErrorsOnSecondRender() {
  return <ErrorsOnSecondRenderBase skipReport={false} />
}

function ErrorsOnSecondRenderNoReport() {
  return <ErrorsOnSecondRenderBase skipReport />
}

function TestErrorBoundary({
  shouldSkipReport = false,
  ...props
}: Omit<PreloadedQueryBoundaryProps, 'children' | 'onRetry'> & {shouldSkipReport?: boolean}) {
  return (
    <PreloadedQueryBoundary {...props} onRetry={() => {}}>
      {shouldSkipReport ? <ErrorsOnSecondRenderNoReport /> : <ErrorsOnSecondRender />}
    </PreloadedQueryBoundary>
  )
}

function expectConsoleError(fn: () => void) {
  const consoleError = jest.fn()
  const spy = jest.spyOn(console, 'error').mockImplementation(consoleError)
  fn()
  expect(consoleError).toHaveBeenCalled()
  spy.mockRestore()
}

describe('ErrorBoundary', () => {
  beforeEach(() => {
    jest.clearAllMocks()
  })

  it('renders `children` when no error', () => {
    render(<TestErrorBoundary />)

    expect(screen.getByText('No error')).toBeInTheDocument()
  })

  describe('error fallback', () => {
    it('renders default fallback when `fallback` is `undefined`', () => {
      const {rerender} = render(<TestErrorBoundary />)

      expectConsoleError(() => rerender(<TestErrorBoundary />))

      expect(screen.getByText('Error:')).toBeInTheDocument()
    })

    it('renders provided fallback when `fallback` is provided', () => {
      const fallback = () => <div>Oh no!</div>

      const {rerender} = render(<TestErrorBoundary fallback={fallback} />)

      expectConsoleError(() => rerender(<TestErrorBoundary fallback={fallback} />))

      expect(screen.getByText('Oh no!')).toBeInTheDocument()
    })
  })

  it('calls `reportError` when an error is caught', () => {
    const {rerender} = render(<TestErrorBoundary />)

    expectConsoleError(() => rerender(<TestErrorBoundary />))

    expect(reportError).toHaveBeenCalledWith(expect.objectContaining({message: 'Test error'}), {
      critical: false,
      reactAppName: 'test-app',
    })
  })

  it('does not call `reportError` when an error contains `shouldSkipReport` set to true', () => {
    const {rerender} = render(<TestErrorBoundary shouldSkipReport />)

    expectConsoleError(() => rerender(<TestErrorBoundary shouldSkipReport />))

    expect(reportError).toHaveBeenCalledTimes(0)
  })

  it('passes `critical` and `appName` props to error handler', () => {
    const {rerender} = render(<TestErrorBoundary critical appName="some-app" />)

    expectConsoleError(() => rerender(<TestErrorBoundary critical appName="some-app" />))

    expect(reportError).toHaveBeenCalledWith(expect.objectContaining({message: 'Test error'}), {
      critical: true,
      reactAppName: 'some-app',
    })
  })
})
