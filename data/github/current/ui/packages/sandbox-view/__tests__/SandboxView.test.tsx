import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import {SandboxView} from '../SandboxView'
import {RenderState} from '../types'
import {useIFrameMessaging} from '../use-iframe-messaging'

jest.mock('../use-iframe-messaging')
jest.mock('@github-ui/feature-flags', () => ({
  isFeatureEnabled: () => true,
}))

const mockedUseIFrameMessaging = jest.mocked(useIFrameMessaging)

beforeEach(() => {
  mockedUseIFrameMessaging.mockClear()
  mockedUseIFrameMessaging.mockReturnValue({
    renderState: RenderState.LOADING,
    errorMessage: undefined,
  })
})

const sampleProps = {
  viewscreenUrl: 'https://github.com',
  content: 'hello world',
}

test('Renders sandbox content', async () => {
  render(<SandboxView {...sampleProps} />)

  expect(screen.getByTitle('Preview page for the user provided code')).toBeInTheDocument()
})

test('Renders error message', async () => {
  mockedUseIFrameMessaging.mockReturnValue({
    renderState: RenderState.ERROR,
    errorMessage: 'Test Error',
  })

  render(<SandboxView {...sampleProps} />)

  expect(screen.getByText('HTML rendering failed')).toBeInTheDocument()
  expect(screen.getByText('Test Error')).toBeInTheDocument()
})

test('Renders error without message', async () => {
  mockedUseIFrameMessaging.mockReturnValue({
    renderState: RenderState.ERROR,
    errorMessage: undefined,
  })

  render(<SandboxView {...sampleProps} />)

  expect(screen.getByText('HTML rendering failed')).toBeInTheDocument()
  expect(screen.getByText('Refresh the page or check the HTML')).toBeInTheDocument()
})

test('Renders iframe in the ready state', async () => {
  mockedUseIFrameMessaging.mockReturnValue({
    renderState: RenderState.READY,
    errorMessage: undefined,
  })

  render(<SandboxView {...sampleProps} />)

  expect(screen.getByTitle('Preview page for the user provided code')).toBeInTheDocument()
})
