import {screen, waitFor} from '@testing-library/react'
import {useFeatureFlags} from '@github-ui/react-core/use-feature-flag'
import {render} from '@github-ui/react-core/test-utils'
import type {Model} from '@github-ui/marketplace-common'
import {modelEvalsPath, modelPromptPath} from '@github-ui/paths'
import {mockGettingStartedPayload, mockModel} from '../../playground/__tests__/mocks'
import {mockResizeObserver} from '../../playground/components/GettingStartedDialog/__tests__/mocks'
import {setupMatchMediaMock} from '../../playground/components/__tests__/mocks'
import {ModelsPromptRoute} from '../ModelsPromptRoute'

jest.mock('@github-ui/react-core/use-feature-flag')
const mockUseFeatureFlags = jest.mocked(useFeatureFlags)

const mockVerifiedFetchJSON = jest.fn().mockName('verifiedFetchJSON')
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
    test('renders when feature is enabled', () => {
      const routePayload = mockGettingStartedPayload()
      const pathname = modelPromptPath(routePayload.model)
      mockUseFeatureFlags.mockReturnValue({github_models_prompt_editor: true})

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

    test('does not render when feature is disabled', () => {
      const routePayload = mockGettingStartedPayload()
      const pathname = modelPromptPath(routePayload.model)
      mockUseFeatureFlags.mockReturnValue({github_models_prompt_editor: false})

      const {container} = render(<ModelsPromptRoute />, {routePayload, pathname})

      expect(container).toBeEmptyDOMElement()
    })
  })

  describe('/evals', () => {
    test('renders when feature is enabled', async () => {
      const routePayload = mockGettingStartedPayload()
      const pathname = modelEvalsPath(routePayload.model)
      mockUseFeatureFlags.mockReturnValue({github_models_prompt_evals: true})
      const modelsPayload: Model[] = [mockModel, mockModel]
      mockVerifiedFetchJSON.mockResolvedValue({status: 200, ok: true, json: async () => modelsPayload})

      render(<ModelsPromptRoute />, {routePayload, pathname})

      await waitFor(() => {
        expect(mockVerifiedFetchJSON).toHaveBeenCalledWith('/marketplace/models')
      })

      expect(screen.getAllByRole('link', {name: 'Give feedback'}).length).toBeGreaterThanOrEqual(1)

      expect(screen.getByRole('button', {name: 'Switch model'})).toBeInTheDocument()
      expect(screen.getByRole('button', {name: 'Show model info'})).toBeInTheDocument()
      expect(screen.getByRole('button', {name: 'Playground'})).toBeInTheDocument()
      expect(screen.getByRole('button', {name: 'Use this model'})).toBeInTheDocument()

      expect(screen.getByRole('button', {name: 'Chat'})).toBeInTheDocument()
      expect(screen.getByRole('button', {name: 'Run ( control enter )'})).toBeInTheDocument()
      expect(screen.getByRole('button', {name: 'Prompt'})).toBeInTheDocument()
      expect(screen.getByRole('button', {name: 'Evaluate'})).toBeInTheDocument()
      expect(screen.getByRole('button', {name: 'Import rows'})).toBeInTheDocument()
      expect(screen.getByRole('button', {name: 'Add row'})).toBeInTheDocument()
      expect(screen.getByRole('button', {name: 'Add test criteria'})).toBeInTheDocument()
      expect(screen.getByRole('button', {name: 'Actions'})).toBeInTheDocument()
      expect(screen.getByRole('columnheader', {name: 'input'})).toBeInTheDocument()
      expect(screen.getByRole('columnheader', {name: 'expected'})).toBeInTheDocument()
      expect(screen.getByRole('columnheader', {name: 'Output'})).toBeInTheDocument()
      expect(screen.getByRole('columnheader', {name: 'Actions'})).toBeInTheDocument()
    })

    test('does not render when feature is disabled', () => {
      const routePayload = mockGettingStartedPayload()
      const pathname = modelEvalsPath(routePayload.model)
      mockUseFeatureFlags.mockReturnValue({github_models_prompt_evals: false})

      const {container} = render(<ModelsPromptRoute />, {routePayload, pathname})

      expect(container).toBeEmptyDOMElement()
    })
  })
})
