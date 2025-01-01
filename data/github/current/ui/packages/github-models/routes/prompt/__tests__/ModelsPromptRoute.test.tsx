import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {modelPromptPath} from '@github-ui/paths'
import {mockGettingStartedPayload} from '../../playground/__tests__/mocks'
import {mockResizeObserver} from '../../playground/components/GettingStartedDialog/__tests__/mocks'
import {setupMatchMediaMock} from '../../playground/components/__tests__/mocks'
import {ModelsPromptRoute} from '../ModelsPromptRoute'

const mockVerifiedFetchJSON = jest.fn().mockName('verifiedFetchJSON')
// eslint-disable-next-line no-restricted-syntax
jest.mock('@github-ui/verified-fetch', () => {
  return {verifiedFetchJSON: (...args: unknown[]) => mockVerifiedFetchJSON(...args)}
})

describe('ModelsPromptRoute', () => {
  beforeEach(() => {
    // Avoids "TypeError: Cannot read properties of undefined (reading 'addEventListener')" error when all tests run.
    setupMatchMediaMock()

    // Necessary to avoid a 'TypeError: observer.observe is not a function' error when all ModelsPromptRoute
    // tests are run.
    mockResizeObserver()
  })

  afterEach(() => {
    jest.resetAllMocks()
  })

  describe('/prompt', () => {
    test('renders', () => {
      const routePayload = mockGettingStartedPayload()
      const pathname = modelPromptPath(routePayload.model)

      render(<ModelsPromptRoute />, {routePayload, pathname})

      expect(screen.getByRole('heading', {name: 'Talk to us'})).toBeInTheDocument()
      expect(screen.getAllByRole('link', {name: 'Give feedback'}).length).toBeGreaterThanOrEqual(1)
      expect(screen.getByRole('link', {name: 'share your thoughts'})).toBeInTheDocument()
      expect(screen.getAllByRole('link', {name: 'Book a call'}).length).toBeGreaterThanOrEqual(1)
      expect(screen.getByRole('button', {name: 'Dismiss banner'})).toBeInTheDocument()

      expect(screen.getByRole('button', {name: 'Switch model'})).toBeInTheDocument()
      expect(screen.getByRole('button', {name: 'Show model info'})).toBeInTheDocument()
      expect(screen.getByRole('button', {name: 'Playground'})).toBeInTheDocument()
      expect(screen.getByRole('button', {name: 'Use this model'})).toBeInTheDocument()

      expect(screen.getByRole('button', {name: 'Chat'})).toBeInTheDocument()
      expect(screen.getByRole('button', {name: 'Run ( control enter )'})).toBeInTheDocument()
      expect(screen.getByRole('button', {name: 'Edit variables'})).toBeInTheDocument()
      expect(screen.getByRole('button', {name: 'Show parameters setting'})).toBeInTheDocument()
      expect(screen.getByRole('button', {name: 'Clear prompts, variables, and chat'})).toBeInTheDocument()
      expect(screen.getByRole('textbox', {name: 'System'})).toBeInTheDocument()
      expect(screen.getByRole('textbox', {name: 'User'})).toBeInTheDocument()
      expect(screen.getByRole('heading', {name: 'Iterate on your prompt'})).toBeInTheDocument()
    })
  })
})
