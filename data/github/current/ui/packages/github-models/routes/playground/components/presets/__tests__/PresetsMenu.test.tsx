import {render as htmlRender, type TestRenderOptions} from '@github-ui/react-core/test-utils'
import {screen, waitFor, within} from '@testing-library/react'
import {PresetsMenu} from '../PresetsMenu'
import {
  mockDefaultParameters,
  mockModelInputSchema,
  mockPreset,
  mockTokenUsage,
  mockUsageStats,
} from '../../../__tests__/mocks'
import {mockModelState, mockPlaygroundState, mockStoredMessage} from '../../__tests__/mocks'
import {Panel, type PlaygroundManager} from '../../../../../utils/playground-manager'
import {PlaygroundManagerProvider} from '../../../../../contexts/PlaygroundManagerContext'
import {PlaygroundStateProvider} from '../../../../../contexts/PlaygroundStateContext'
import type {PlaygroundRequestParameters, PlaygroundState, PresetsPayload} from '../../../../../types'
import {mockResizeObserver} from '../../GettingStartedDialog/__tests__/mocks'

const mockVerifiedFetchJSON = jest.fn().mockName('verifiedFetchJSON')
const setModelState = jest.fn().mockName('setModelState')
// eslint-disable-next-line no-restricted-syntax
jest.mock('@github-ui/verified-fetch', () => {
  return {
    verifiedFetchJSON: (...args: unknown[]) => mockVerifiedFetchJSON(...args),
  }
})

describe('PresetsMenu', () => {
  beforeEach(() => {
    // Necessary to avoid a 'TypeError: observer.observe is not a function' error when all PresetsMenu tests are run.
    mockResizeObserver()
    mockVerifiedFetchJSON.mockClear()
    setModelState.mockClear()
  })

  afterEach(() => {
    jest.resetAllMocks()
  })

  describe('when a preset is not selected', () => {
    test('renders when default preset is selected', async () => {
      const presetParams: PlaygroundRequestParameters = {system_prompt: 'Respond in one sentence'}
      const preset = {
        ...mockPreset,
        parameters: presetParams,
      }
      const presetsPayload: PresetsPayload = {presets: [preset], limit_per_user: 50}
      mockVerifiedFetchJSON.mockResolvedValue({status: 200, ok: true, json: async () => presetsPayload})
      const messages = [mockStoredMessage]
      const modelState = mockModelState({
        messages,
        modelInputSchema: {...mockModelInputSchema, capabilities: {systemPrompt: true}},
      })
      const playgroundState = mockPlaygroundState({models: [modelState]})

      const {user, container} = render(<PresetsMenu />, {playgroundState})

      await waitFor(() => {
        expect(mockVerifiedFetchJSON).toHaveBeenCalledWith('/marketplace/models/presets')
      })

      expect(mockVerifiedFetchJSON).toHaveBeenCalledTimes(1)
      const menuToggleButton = await within(container).findByRole('button', {name: 'Preset: Default'})
      expect(menuToggleButton).toBeInTheDocument()

      await user.click(menuToggleButton)

      expect(screen.getByRole('menu', {name: 'Preset: Default'})).toBeInTheDocument()
      const defaultPresetRadio = screen.getByRole('menuitemradio', {name: 'Default'})
      expect(defaultPresetRadio).toBeInTheDocument()
      expect(defaultPresetRadio).toHaveAttribute('aria-checked', 'true')
      const otherPresetRadio = screen.getByRole('menuitemradio', {name: preset.name})
      expect(otherPresetRadio).toBeInTheDocument()
      expect(otherPresetRadio).toHaveAttribute('aria-checked', 'false')
      expect(setModelState).not.toHaveBeenCalled()

      await user.click(otherPresetRadio)

      expect(setModelState).toHaveBeenCalledTimes(1)
      expect(setModelState).toHaveBeenCalledWith(Panel.Main, {
        ...modelState,
        messages: [],
        isLoading: false,
        isUseIndexSelected: false,
        chatInput: '',
        chatClosed: false,
        parameters: mockDefaultParameters,
        parametersHasChanges: true,
        responseFormat: 'text',
        jsonSchema: '',
        systemPrompt: presetParams.system_prompt,
        tokenUsage: mockTokenUsage,
        usageStats: mockUsageStats,
      })

      // Now switch back to the default
      await user.click(menuToggleButton)

      setModelState.mockClear()

      const newDefaultPresetRadio = screen.getByRole('menuitemradio', {name: 'Default'})
      expect(newDefaultPresetRadio).toBeInTheDocument()
      expect(newDefaultPresetRadio).toHaveAttribute('aria-checked', 'false')

      await user.click(newDefaultPresetRadio)

      expect(setModelState).toHaveBeenCalledTimes(1)
      expect(setModelState).toHaveBeenCalledWith(Panel.Main, {
        ...modelState,
        messages: [],
        chatInput: '',
        parameters: mockDefaultParameters,
        jsonSchema: '',
        systemPrompt: '',
      })
    })

    test('does not render preset actions when there is no system prompt, chat input, or message', async () => {
      const modelState = mockModelState({systemPrompt: '', messages: [], chatInput: ''})
      const playgroundState = mockPlaygroundState({models: [modelState]})

      const {user} = render(<PresetsMenu />, {playgroundState})
      await user.click(screen.getByRole('button', {name: 'Preset: Default'}))

      expect(screen.queryByText('Save prompt as new preset')).not.toBeInTheDocument()
      expect(screen.queryByText('Update')).not.toBeInTheDocument()
      expect(screen.queryByText('Delete')).not.toBeInTheDocument()
      expect(screen.queryByText('Share')).not.toBeInTheDocument()
    })

    test('does not render preset actions when system prompt is an empty string', async () => {
      const modelState = mockModelState({systemPrompt: '   ', messages: [], chatInput: ''})
      const playgroundState = mockPlaygroundState({models: [modelState]})

      const {user} = render(<PresetsMenu />, {playgroundState})
      await user.click(screen.getByRole('button', {name: 'Preset: Default'}))

      expect(screen.queryByText('Save prompt as new preset')).not.toBeInTheDocument()
      expect(screen.queryByText('Update')).not.toBeInTheDocument()
      expect(screen.queryByText('Delete')).not.toBeInTheDocument()
      expect(screen.queryByText('Share')).not.toBeInTheDocument()
    })

    test('renders only the save prompt item when system prompt, chat input, or message exists', async () => {
      const modelState = mockModelState()
      const playgroundState = mockPlaygroundState({models: [modelState]})

      const {user} = render(<PresetsMenu />, {playgroundState})
      await user.click(screen.getByRole('button', {name: 'Preset: Default'}))

      expect(screen.getByText('Save prompt as new preset')).toBeInTheDocument()
      expect(screen.queryByText('Update')).not.toBeInTheDocument()
      expect(screen.queryByText('Delete')).not.toBeInTheDocument()
      expect(screen.queryByText('Share')).not.toBeInTheDocument()
    })
  })

  describe('when a preset is selected', () => {
    test('renders selected private preset based on URL, case insensitive', async () => {
      const privatePreset = Object.assign({}, mockPreset, {
        urlIdentifier: 'all-lowercase',
        name: 'A Very Secret Preset',
        private: true,
      })
      const presetsPayload: PresetsPayload = {presets: [privatePreset], limit_per_user: 50}
      mockVerifiedFetchJSON.mockResolvedValue({status: 200, ok: true, json: async () => presetsPayload})

      const {user, container} = render(<PresetsMenu />, {
        search: `?preset=${privatePreset.urlIdentifier.toUpperCase()}`,
      })

      await waitFor(() => {
        expect(mockVerifiedFetchJSON).toHaveBeenCalledWith('/marketplace/models/presets')
      })

      expect(mockVerifiedFetchJSON).toHaveBeenCalledTimes(1)
      const menuToggleButton = await within(container).findByRole('button', {name: `Preset: ${privatePreset.name}`})
      expect(menuToggleButton).toBeInTheDocument()

      await user.click(menuToggleButton)

      expect(screen.getByRole('menu', {name: `Preset: ${privatePreset.name}`})).toBeInTheDocument()
      const defaultPresetRadio = screen.getByRole('menuitemradio', {name: 'Default'})
      expect(defaultPresetRadio).toBeInTheDocument()
      expect(defaultPresetRadio).toHaveAttribute('aria-checked', 'false')
      const privatePresetRadio = screen.getByRole('menuitemradio', {name: privatePreset.name})
      expect(privatePresetRadio).toBeInTheDocument()
      expect(privatePresetRadio).toHaveAttribute('aria-checked', 'true')
    })

    test('does not render create or update actions when there is no system prompt, chat input, or message', async () => {
      const presetsPayload: PresetsPayload = {presets: [mockPreset], limit_per_user: 50}
      mockVerifiedFetchJSON.mockResolvedValue({status: 200, ok: true, json: async () => presetsPayload})

      const modelState = mockModelState({systemPrompt: '', messages: [], chatInput: ''})
      const playgroundState = mockPlaygroundState({models: [modelState]})

      const {container, user} = render(<PresetsMenu />, {
        playgroundState,
        search: `?preset=${mockPreset.urlIdentifier}`,
      })

      await waitFor(() => {
        expect(mockVerifiedFetchJSON).toHaveBeenCalledWith('/marketplace/models/presets')
      })

      const menuToggleButton = await within(container).findByRole('button', {name: `Preset: ${mockPreset.name}`})
      await user.click(menuToggleButton)

      expect(screen.queryByText('Save prompt as new preset')).not.toBeInTheDocument()
      expect(screen.queryByText('Update')).not.toBeInTheDocument()
      expect(screen.getByText('Delete')).toBeInTheDocument()
      expect(screen.queryByText('Share')).not.toBeInTheDocument()
    })

    test('does not render create or update actions when system prompt is an empty string', async () => {
      const presetsPayload: PresetsPayload = {presets: [mockPreset], limit_per_user: 50}
      mockVerifiedFetchJSON.mockResolvedValue({status: 200, ok: true, json: async () => presetsPayload})

      const modelState = mockModelState({systemPrompt: '   ', messages: [], chatInput: ''})
      const playgroundState = mockPlaygroundState({models: [modelState]})

      const {container, user} = render(<PresetsMenu />, {
        playgroundState,
        search: `?preset=${mockPreset.urlIdentifier}`,
      })

      await waitFor(() => {
        expect(mockVerifiedFetchJSON).toHaveBeenCalledWith('/marketplace/models/presets')
      })

      const menuToggleButton = await within(container).findByRole('button', {name: `Preset: ${mockPreset.name}`})
      await user.click(menuToggleButton)

      expect(screen.queryByText('Save prompt as new preset')).not.toBeInTheDocument()
      expect(screen.queryByText('Update')).not.toBeInTheDocument()
      expect(screen.getByText('Delete')).toBeInTheDocument()
      expect(screen.queryByText('Share')).not.toBeInTheDocument()
    })

    test('renders create, update, and delete actions when system prompt exists', async () => {
      const presetsPayload: PresetsPayload = {presets: [mockPreset], limit_per_user: 50}
      mockVerifiedFetchJSON.mockResolvedValue({status: 200, ok: true, json: async () => presetsPayload})

      const modelState = mockModelState()
      const playgroundState = mockPlaygroundState({models: [modelState]})

      const {container, user} = render(<PresetsMenu />, {
        playgroundState,
        search: `?preset=${mockPreset.urlIdentifier}`,
      })

      await waitFor(() => {
        expect(mockVerifiedFetchJSON).toHaveBeenCalledWith('/marketplace/models/presets')
      })

      const menuToggleButton = await within(container).findByRole('button', {name: `Preset: ${mockPreset.name}`})
      await user.click(menuToggleButton)

      expect(screen.getByText('Save prompt as new preset')).toBeInTheDocument()
      expect(screen.getByText('Update')).toBeInTheDocument()
      expect(screen.getByText('Delete')).toBeInTheDocument()
      expect(screen.queryByText('Share')).not.toBeInTheDocument()
    })

    test('renders create, update, delete, and share actions when preset is public', async () => {
      const presetsPayload: PresetsPayload = {presets: [{...mockPreset, private: false}], limit_per_user: 50}
      mockVerifiedFetchJSON.mockResolvedValue({status: 200, ok: true, json: async () => presetsPayload})

      const modelState = mockModelState()
      const playgroundState = mockPlaygroundState({models: [modelState]})

      const {container, user} = render(<PresetsMenu />, {
        playgroundState,
        search: `?preset=${mockPreset.urlIdentifier}`,
      })

      await waitFor(() => {
        expect(mockVerifiedFetchJSON).toHaveBeenCalledWith('/marketplace/models/presets')
      })

      const menuToggleButton = await within(container).findByRole('button', {name: `Preset: ${mockPreset.name}`})
      await user.click(menuToggleButton)

      expect(screen.getByText('Save prompt as new preset')).toBeInTheDocument()
      expect(screen.getByText('Update')).toBeInTheDocument()
      expect(screen.getByText('Delete')).toBeInTheDocument()
      expect(screen.getByText('Share')).toBeInTheDocument()
    })

    test('runs when a save prompt is successful', async () => {
      const presetsPayload: PresetsPayload = {presets: [mockPreset], limit_per_user: 50}
      mockVerifiedFetchJSON.mockResolvedValue({status: 200, ok: true, json: async () => presetsPayload})

      const modelState = mockModelState()
      const playgroundState = mockPlaygroundState({models: [modelState]})

      const {container, user} = render(<PresetsMenu />, {playgroundState})

      await waitFor(() => {
        expect(mockVerifiedFetchJSON).toHaveBeenCalledWith('/marketplace/models/presets')
      })

      // Reset the mock so we can check the arguments passed to the next call
      mockVerifiedFetchJSON.mockClear()

      const menuToggleButton = await within(container).findByRole('button', {name: 'Preset: Default'})

      await user.click(menuToggleButton)
      await user.click(screen.getByText('Save prompt as new preset'))

      expect(screen.getByText('Create prompt')).toBeInTheDocument()

      const nameInput = screen.getByRole('textbox', {name: 'Name *'})

      await user.clear(nameInput)
      await user.type(nameInput, 'New preset name')

      await user.click(screen.getByText('Save prompt'))

      await waitFor(() => {
        expect(mockVerifiedFetchJSON).toHaveBeenCalledWith('/marketplace/models/presets')
      })
    })

    test('runs when an update prompt is successful', async () => {
      const presetsPayload: PresetsPayload = {presets: [mockPreset], limit_per_user: 50}
      mockVerifiedFetchJSON.mockResolvedValue({status: 200, ok: true, json: async () => presetsPayload})

      const modelState = mockModelState()
      const playgroundState = mockPlaygroundState({models: [modelState]})

      const {container, user} = render(<PresetsMenu />, {
        playgroundState,
        search: `?preset=${mockPreset.urlIdentifier}`,
      })

      await waitFor(() => {
        expect(mockVerifiedFetchJSON).toHaveBeenCalledWith('/marketplace/models/presets')
      })

      // Reset the mock so we can check the arguments passed to the next call
      mockVerifiedFetchJSON.mockClear()

      const menuToggleButton = await within(container).findByRole('button', {name: `Preset: ${mockPreset.name}`})

      await user.click(menuToggleButton)
      await user.click(screen.getByText('Update'))

      expect(screen.getByRole('dialog', {name: 'Update prompt'})).toBeInTheDocument()

      const nameInput = screen.getByRole('textbox', {name: 'Name *'})

      await user.clear(nameInput)
      await user.type(nameInput, 'New preset name')

      await user.click(screen.getByRole('button', {name: 'Update prompt'}))

      await waitFor(() => {
        expect(mockVerifiedFetchJSON).toHaveBeenCalledWith('/marketplace/models/presets')
      })

      await waitFor(() => {
        expect(menuToggleButton).toHaveFocus()
      })
    })

    test('runs when a delete prompt is successful', async () => {
      const presetsPayload: PresetsPayload = {presets: [mockPreset], limit_per_user: 50}
      mockVerifiedFetchJSON.mockResolvedValue({status: 200, ok: true, json: async () => presetsPayload})

      const modelState = mockModelState()
      const playgroundState = mockPlaygroundState({models: [modelState]})

      const {container, user} = render(<PresetsMenu />, {
        playgroundState,
        search: `?preset=${mockPreset.urlIdentifier}`,
      })

      await waitFor(() => {
        expect(mockVerifiedFetchJSON).toHaveBeenCalledWith('/marketplace/models/presets')
      })

      // Reset the mock so we can check the arguments passed to the next call
      mockVerifiedFetchJSON.mockClear()

      const menuToggleButton = await within(container).findByRole('button', {name: `Preset: ${mockPreset.name}`})

      await user.click(menuToggleButton)
      await user.click(screen.getByText('Delete'))

      expect(screen.getByText('Delete prompt')).toBeInTheDocument()

      await user.click(screen.getByText('Delete'))

      await waitFor(() => {
        expect(mockVerifiedFetchJSON).toHaveBeenCalledWith('/marketplace/models/presets')
      })

      await waitFor(() => {
        expect(menuToggleButton).toHaveFocus()
      })
    })

    test('opens the share prompt dialog when the share prompt button is clicked', async () => {
      const preset = {
        ...mockPreset,
        private: false,
      }
      const presetsPayload: PresetsPayload = {presets: [preset], limit_per_user: 50}
      mockVerifiedFetchJSON.mockResolvedValue({status: 200, ok: true, json: async () => presetsPayload})

      const modelState = mockModelState()
      const playgroundState = mockPlaygroundState({models: [modelState]})
      const {user, container} = render(<PresetsMenu />, {
        playgroundState,
        search: `?preset=${mockPreset.urlIdentifier}`,
      })

      await waitFor(() => {
        expect(mockVerifiedFetchJSON).toHaveBeenCalledWith('/marketplace/models/presets')
      })

      const menuToggleButton = await within(container).findByRole('button', {name: `Preset: ${preset.name}`})
      await user.click(menuToggleButton)

      await user.click(screen.getByText('Share'))

      expect(screen.getByTestId('share-preset-dialog')).toBeInTheDocument()

      const close = screen.getByRole('button', {name: 'Close'})
      expect(close).toBeInTheDocument()
      await user.click(close)
      expect(screen.queryByTestId('share-preset-dialog')).not.toBeInTheDocument()

      await waitFor(() => {
        expect(menuToggleButton).toHaveFocus()
      })
    })
  })

  test('autofocus the anchor when the save dialog closes with an escape key', async () => {
    const presetsPayload: PresetsPayload = {presets: [mockPreset], limit_per_user: 50}
    mockVerifiedFetchJSON.mockResolvedValue({status: 200, ok: true, json: async () => presetsPayload})

    const modelState = mockModelState()
    const playgroundState = mockPlaygroundState({models: [modelState]})

    const {user} = render(<PresetsMenu />, {playgroundState})

    const menuToggleButton = await screen.findByRole('button', {name: 'Preset: Default'})

    await user.click(menuToggleButton)
    await user.click(screen.getByText('Save prompt as new preset'))

    expect(screen.getByText('Create prompt')).toBeInTheDocument()

    await user.keyboard('{escape}')

    await waitFor(() => {
      expect(menuToggleButton).toHaveFocus()
    })
  })

  test('autofocus the anchor when the share dialog closes with an escape key', async () => {
    const preset = {
      ...mockPreset,
      private: false,
    }

    const presetsPayload: PresetsPayload = {presets: [preset], limit_per_user: 50}
    mockVerifiedFetchJSON.mockResolvedValue({status: 200, ok: true, json: async () => presetsPayload})

    const modelState = mockModelState()
    const playgroundState = mockPlaygroundState({models: [modelState]})

    const {user} = render(<PresetsMenu />, {
      playgroundState,
      search: `?preset=${mockPreset.urlIdentifier}`,
    })

    const menuToggleButton = await screen.findByRole('button', {name: `Preset: ${preset.name}`})
    await user.click(menuToggleButton)

    await user.click(screen.getByText('Share'))

    expect(screen.getByTestId('share-preset-dialog')).toBeInTheDocument()

    await user.click(menuToggleButton)

    await user.click(screen.getByText('Share'))

    expect(screen.getByTestId('share-preset-dialog')).toBeInTheDocument()

    await user.keyboard('{escape}')

    await waitFor(() => {
      expect(menuToggleButton).toHaveFocus()
    })
  })
})

function render(
  component: JSX.Element,
  {playgroundState, ...opts}: TestRenderOptions & {playgroundState?: PlaygroundState} = {},
) {
  const manager = {} as PlaygroundManager
  manager.setModelState = setModelState

  return htmlRender(
    <PlaygroundStateProvider state={playgroundState ?? mockPlaygroundState()}>
      <PlaygroundManagerProvider manager={manager}>{component}</PlaygroundManagerProvider>
    </PlaygroundStateProvider>,
    opts,
  )
}
