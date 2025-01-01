import {describe, expect, it, vi} from '@github-ui/tests'
import {screen} from '@testing-library/react'

import {ErrorBoundary, type ErrorBoundaryProps} from '../ErrorBoundary'
import {render} from '../test-utils/Render'

const ErrorThrowingComponent = () => {
  throw new Error('Test error')
}

function TestErrorBoundary(props: Omit<ErrorBoundaryProps, 'children'>) {
  return (
    <ErrorBoundary {...props}>
      <ErrorThrowingComponent />
    </ErrorBoundary>
  )
}

function expectConsoleError(fn: () => void) {
  const consoleError = vi.fn()
  const spy = vi.spyOn(console, 'error').mockImplementation(consoleError)
  fn()
  expect(consoleError).toHaveBeenCalled()
  spy.mockRestore()
}

describe('ErrorBoundary', () => {
  it('renders `children` when no error', () => {
    render(
      <ErrorBoundary>
        <span>No error</span>
      </ErrorBoundary>,
    )

    expect(screen.getByText('No error')).toBeInTheDocument()
  })

  describe('error fallback', () => {
    it('renders default fallback when `fallback` is `undefined`', () => {
      expectConsoleError(() => render(<TestErrorBoundary />))

      expect(screen.getByText('Error')).toBeInTheDocument()
    })

    it('renders empty fallback when `fallback` is `null`', () => {
      expectConsoleError(() => render(<TestErrorBoundary fallback={null} />))

      expect(screen.queryByText('Error')).not.toBeInTheDocument()
    })

    it('renders provided fallback when `fallback` is provided', () => {
      expectConsoleError(() => render(<TestErrorBoundary fallback="Oh no!" />))

      expect(screen.getByText('Oh no!')).toBeInTheDocument()
    })
  })

  it('calls `onError` when an error is caught', () => {
    const onError = vi.fn()

    expectConsoleError(() => render(<TestErrorBoundary onError={onError} />))

    expect(onError).toHaveBeenCalledWith(expect.objectContaining({message: 'Test error'}), {
      critical: false,
      reactAppName: 'test-app',
    })
  })

  it('passes `critical` and `appName` props to error handler', () => {
    const onError = vi.fn()

    expectConsoleError(() => render(<TestErrorBoundary onError={onError} critical appName="some-app" />))

    expect(onError).toHaveBeenCalledWith(expect.objectContaining({message: 'Test error'}), {
      critical: true,
      reactAppName: 'some-app',
    })
  })
})
