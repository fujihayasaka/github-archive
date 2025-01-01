import {render as htmlRender, type TestRenderOptions} from '@github-ui/react-core/test-utils'
import {screen, waitFor, within} from '@testing-library/react'
import {PresetsMenu} from '../PresetsMenu'
import {mockModelDetails, mockPreset} from '../../../__tests__/mocks'
import {mockModelState, mockPlaygroundState, mockStoredMessage} from '../../__tests__/mocks'
import {Panel, type PlaygroundManager, PlaygroundManagerContext} from '../../../../../utils/playground-manager'
import {PlaygroundStateProvider} from '../../../../../contexts/PlaygroundStateContext'
import type {PlaygroundRequestParameters, PlaygroundState, PresetsPayload} from '../../../../../types'
import {mockResizeObserver} from '../../GettingStartedDialog/__tests__/mocks'

const mockVerifiedFetchJSON = jest.fn().mockName('verifiedFetchJSON')
const setModelState = jest.fn().mockName('setModelState')
window.performance.clearResourceTimings = jest.fn()
window.performance.mark = jest.fn()

jest.mock('@github-ui/verified-fetch', () => {
  return {
    verifiedFetchJSON: (...args: unknown[]) => mockVerifiedFetchJSON(...args),
  }
})

describe('PresetsMenu', () => {
  beforeEach(() => {
    // Necessary to avoid a 'TypeError: observer.observe is not a function' error when all PresetsMenu tests are run.
    mockResizeObserver()
  })

  afterEach(() => {
    jest.resetAllMocks()
  })

  test('renders when default preset is selected', async () => {
    const presetParams: PlaygroundRequestParameters = {
      system_prompt: 'Respond in one sentence',
      max_tokens: 1000,
      temperature: 1,
      top_p: 1,
      stop: [],
    }
    const preset = Object.assign({}, mockPreset, {parameters: presetParams})
    const presetsPayload: PresetsPayload = {presets: [preset], limit_per_user: 50}
    mockVerifiedFetchJSON.mockResolvedValue({status: 200, ok: true, json: async () => presetsPayload})
    const messages = [mockStoredMessage]
    const playgroundState = mockPlaygroundState({models: [mockModelState({messages})]})

    const {user, container} = render(<PresetsMenu modelDetails={mockModelDetails} />, {playgroundState})

    await waitFor(() => {
      expect(mockVerifiedFetchJSON).toHaveBeenCalledWith('/marketplace/models/presets')
    })

    expect(mockVerifiedFetchJSON).toHaveBeenCalledTimes(1)
    const menuToggleButton = await within(container).findByRole('button', {name: 'Preset: Default'})
    expect(menuToggleButton).toBeInTheDocument()

    await user.click(menuToggleButton)

    expect(screen.getByRole('menu', {name: 'Preset: Default'})).toBeInTheDocument()
    expect(screen.getByRole('menuitem', {name: 'Create new preset'})).toBeInTheDocument()
    expect(screen.queryByRole('menuitem', {name: 'Edit preset'})).not.toBeInTheDocument()
    expect(screen.queryByRole('menuitem', {name: 'Delete preset'})).not.toBeInTheDocument()
    expect(screen.queryByRole('menuitem', {name: 'Share preset'})).not.toBeInTheDocument()
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
      ...mockModelDetails,
      messages,
      isLoading: false,
      isUseIndexSelected: false,
      chatInput: '',
      chatClosed: false,
      parameters: {
        max_tokens: presetParams.max_tokens,
        stop: presetParams.stop,
        temperature: presetParams.temperature,
        top_p: presetParams.top_p,
      },
      parametersHasChanges: true,
      responseFormat: 'text',
      systemPrompt: presetParams.system_prompt,
    })
  })

  test('renders selected private preset based on URL, case insensitive', async () => {
    const privatePreset = Object.assign({}, mockPreset, {
      urlIdentifier: 'all-lowercase',
      name: 'A Very Secret Preset',
      private: true,
    })
    const presetsPayload: PresetsPayload = {presets: [privatePreset], limit_per_user: 50}
    mockVerifiedFetchJSON.mockResolvedValue({status: 200, ok: true, json: async () => presetsPayload})

    const {user, container} = render(<PresetsMenu modelDetails={mockModelDetails} />, {
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
    expect(screen.getByRole('menuitem', {name: 'Create new preset'})).toBeInTheDocument()
    expect(screen.getByRole('menuitem', {name: 'Edit preset'})).toBeInTheDocument()
    const deletePresetMenuItem = screen.getByRole('menuitem', {name: 'Delete preset'})
    expect(deletePresetMenuItem).toBeInTheDocument()
    expect(screen.queryByRole('menuitem', {name: 'Share preset'})).not.toBeInTheDocument()
    const defaultPresetRadio = screen.getByRole('menuitemradio', {name: 'Default'})
    expect(defaultPresetRadio).toBeInTheDocument()
    expect(defaultPresetRadio).toHaveAttribute('aria-checked', 'false')
    const privatePresetRadio = screen.getByRole('menuitemradio', {name: privatePreset.name})
    expect(privatePresetRadio).toBeInTheDocument()
    expect(privatePresetRadio).toHaveAttribute('aria-checked', 'true')
    expect(screen.queryByTestId('delete-preset-dialog')).not.toBeInTheDocument()

    await user.click(deletePresetMenuItem)

    expect(screen.getByTestId('delete-preset-dialog')).toBeInTheDocument()
    expect(setModelState).not.toHaveBeenCalled()
  })

  test('after creating a new preset, preset is properly selected in menu', async () => {
    const existingPreset = Object.assign({}, mockPreset, {name: 'Apple 123'})
    const newPreset = Object.assign({}, mockPreset, {name: 'Apple'})
    const presetsPayload: PresetsPayload = {presets: [existingPreset], limit_per_user: 50}
    const newPresetsPayload: PresetsPayload = {presets: [newPreset, existingPreset], limit_per_user: 50}
    mockVerifiedFetchJSON.mockResolvedValue({status: 200, ok: true, json: async () => presetsPayload})

    mockVerifiedFetchJSON.mockImplementation(path => {
      if (path === '/marketplace/models/presets') {
        return {status: 200, ok: true, json: async () => presetsPayload}
      }
      return {ok: true}
    })

    const {user} = render(<PresetsMenu modelDetails={mockModelDetails} />)
    const menuToggleButton = await screen.findByRole('button', {name: `Preset: Default`})
    expect(menuToggleButton).toBeInTheDocument()

    await user.click(menuToggleButton)

    const createPresetButton = screen.getByRole('menuitem', {name: 'Create new preset'})
    expect(createPresetButton).toBeInTheDocument()

    await user.click(createPresetButton)

    mockVerifiedFetchJSON.mockResolvedValueOnce({status: 200, ok: true, json: async () => newPreset})
    const createButton = screen.getByRole('button', {name: 'Create preset'})
    expect(createButton).toBeInTheDocument()
    const nameInput = screen.getByRole('textbox', {name: 'Name *'})
    expect(nameInput).toBeInTheDocument()

    mockVerifiedFetchJSON.mockResolvedValue({status: 200, ok: true, json: async () => newPresetsPayload})

    await user.type(nameInput, 'Apple')
    await user.click(createButton)

    const updatedMenuButtonName = await screen.findByRole('button', {name: `Preset: Apple`})
    expect(updatedMenuButtonName).toBeInTheDocument()
  })

  test('renders shareable preset', async () => {
    const publicPreset = Object.assign({}, mockPreset, {name: 'Public Shareable Preset', private: false})
    const presetsPayload: PresetsPayload = {presets: [publicPreset], limit_per_user: 50}
    mockVerifiedFetchJSON.mockResolvedValue({status: 200, ok: true, json: async () => presetsPayload})

    const {user, container} = render(<PresetsMenu modelDetails={mockModelDetails} />, {
      search: `?preset=${publicPreset.urlIdentifier}`,
    })

    await waitFor(() => {
      expect(mockVerifiedFetchJSON).toHaveBeenCalledWith('/marketplace/models/presets')
    })

    expect(mockVerifiedFetchJSON).toHaveBeenCalledTimes(1)
    const menuToggleButton = await within(container).findByRole('button', {name: `Preset: ${publicPreset.name}`})
    expect(menuToggleButton).toBeInTheDocument()

    await user.click(menuToggleButton)

    expect(screen.getByRole('menu', {name: `Preset: ${publicPreset.name}`})).toBeInTheDocument()
    expect(screen.getByRole('menuitem', {name: 'Create new preset'})).toBeInTheDocument()
    expect(screen.getByRole('menuitem', {name: 'Edit preset'})).toBeInTheDocument()
    expect(screen.getByRole('menuitem', {name: 'Delete preset'})).toBeInTheDocument()
    const sharePresetMenuItem = screen.getByRole('menuitem', {name: 'Share preset'})
    expect(sharePresetMenuItem).toBeInTheDocument()
    const defaultPresetRadio = screen.getByRole('menuitemradio', {name: 'Default'})
    expect(defaultPresetRadio).toBeInTheDocument()
    expect(defaultPresetRadio).toHaveAttribute('aria-checked', 'false')
    const publicPresetRadio = screen.getByRole('menuitemradio', {name: `${publicPreset.name} Shared`})
    expect(publicPresetRadio).toBeInTheDocument()
    expect(publicPresetRadio).toHaveAttribute('aria-checked', 'true')
    expect(screen.queryByRole('heading', {level: 1, name: 'Share preset'})).not.toBeInTheDocument()

    await user.click(sharePresetMenuItem)

    const sharePresetDialog = screen.getByRole('dialog', {name: 'Share preset'})
    expect(sharePresetDialog).toBeInTheDocument()
    expect(within(sharePresetDialog).getByRole('heading', {level: 1, name: 'Share preset'})).toBeInTheDocument()
    expect(within(sharePresetDialog).getByRole('button', {name: 'Close'})).toBeInTheDocument()
    expect(within(sharePresetDialog).getByRole('button', {name: 'Copy url to clipboard'})).toBeInTheDocument()
    expect(setModelState).not.toHaveBeenCalled()
  })

  test('allows editing preset', async () => {
    const mainModelParameters: PlaygroundRequestParameters = {
      system_prompt: 'Respond in one sentence',
      max_tokens: 1000,
      temperature: 1,
      top_p: 1,
      stop: [],
    }
    const mainModelSystemPrompt = 'Give me all the details, please'
    const mainModel = mockModelState({parameters: mainModelParameters, systemPrompt: mainModelSystemPrompt})
    const models = []
    models[Panel.Main] = mainModel
    const editablePreset = Object.assign({}, mockPreset, {name: 'some original name'})
    const presetsPayload: PresetsPayload = {presets: [editablePreset], limit_per_user: 50}
    mockVerifiedFetchJSON.mockImplementation(path => {
      if (path === '/marketplace/models/presets') {
        return {status: 200, ok: true, json: async () => presetsPayload}
      }
      return {ok: true}
    })

    const {user, container} = render(<PresetsMenu modelDetails={mockModelDetails} />, {
      search: `?preset=${editablePreset.urlIdentifier}`,
      playgroundState: mockPlaygroundState({models}),
    })

    await waitFor(() => {
      expect(mockVerifiedFetchJSON).toHaveBeenCalledWith('/marketplace/models/presets')
    })

    expect(mockVerifiedFetchJSON).toHaveBeenCalledTimes(1)
    const menuToggleButton = await within(container).findByRole('button', {name: `Preset: ${editablePreset.name}`})
    expect(menuToggleButton).toBeInTheDocument()

    await user.click(menuToggleButton)

    const editPresetMenuItem = screen.getByRole('menuitem', {name: 'Edit preset'})
    expect(editPresetMenuItem).toBeInTheDocument()

    await user.click(editPresetMenuItem)

    const editPresetDialog = screen.getByRole('dialog', {name: 'Edit preset'})
    expect(editPresetDialog).toBeInTheDocument()
    expect(within(editPresetDialog).getByRole('heading', {level: 1, name: 'Edit preset'})).toBeInTheDocument()
    expect(within(editPresetDialog).getByRole('button', {name: 'Close'})).toBeInTheDocument()
    expect(within(editPresetDialog).getByRole('button', {name: 'Cancel'})).toBeInTheDocument()
    const updatePresetButton = within(editPresetDialog).getByRole('button', {name: 'Update preset'})
    expect(updatePresetButton).toBeInTheDocument()
    const presetNameField = within(editPresetDialog).getByRole('textbox', {name: 'Name *'})
    expect(presetNameField).toBeInTheDocument()
    expect(presetNameField).toHaveValue(editablePreset.name)

    await user.clear(presetNameField)
    await user.type(presetNameField, 'Brand new name')

    // Note: this error occurs because of the Banner component that is added to the UI. The
    // CSS parser for jsdom does not support some of the styling syntax for Banner and will fail with an error
    // containing the message below. Tracking issue: https://github.com/github/primer/issues/3882
    // eslint-disable-next-line no-console
    const originalConsoleError = console.error
    jest.spyOn(console, 'error').mockImplementation((value, ...args) => {
      if (!value?.message?.includes('Could not parse CSS stylesheet')) {
        originalConsoleError(value, ...args)
      }
    })

    await user.click(updatePresetButton)

    const expectedBody = {
      preset: {
        name: 'Brand new name',
        description: editablePreset.description,
        private: editablePreset.private,
        conversation_history: [],
        parameters: Object.assign(
          {},
          mainModelParameters,
          {system_prompt: mainModelSystemPrompt},
          {response_format: 'text'},
        ),
      },
    }
    const expectedPath = `/marketplace/models/presets/${encodeURIComponent(editablePreset.urlIdentifier)}`
    expect(mockVerifiedFetchJSON).toHaveBeenCalledWith(expectedPath, {body: expectedBody, method: 'PUT'})
    expect(setModelState).not.toHaveBeenCalled()
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
      <PlaygroundManagerContext.Provider value={manager}>{component}</PlaygroundManagerContext.Provider>
    </PlaygroundStateProvider>,
    opts,
  )
}
