import {screen, within} from '@testing-library/react'
import {render as htmlRender, type TestRenderOptions} from '@github-ui/react-core/test-utils'
import {modelPlaygroundPath} from '@github-ui/paths'
import {PlaygroundHeader} from '../PlaygroundHeader'
import {
  mockLocalStorageUiState,
  mockGettingStarted,
  mockGettingStartedPayload,
  mockModelInputSchema,
  mockModel,
  mockModelState,
  mockO1Model,
} from '../../__tests__/mocks'
import {Panel, type PlaygroundManager} from '../../../../utils/playground-manager'
import {PlaygroundStateProvider} from '../../../../contexts/PlaygroundStateContext'
import {PlaygroundManagerProvider} from '../../../../contexts/PlaygroundManagerContext'
import type {ModelState, PlaygroundState} from '../../../../types'
import {mockPlaygroundState, mockUser} from './mocks'
import {sendEvent} from '@github-ui/hydro-analytics'
import {GettingStartedButtonClicked} from '../../../../utils/playground-types'
import {getQueryClient} from '@github-ui/react-core/query-client'
import {PUBLISHER} from '../../../../utils/normalize-model-strings'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'
import {useFeatureFlags} from '@github-ui/react-core/use-feature-flag'

jest.mock('@github-ui/react-core/use-feature-flag')

const mockVerifiedFetchJSON = verifiedFetchJSON as jest.Mock
jest.mock('@github-ui/verified-fetch', () => ({
  verifiedFetchJSON: jest.fn(),
}))

const mockUseFeatureFlag = jest.mocked(useFeatureFlags).mockReturnValue({})
const handleSetSidebarTab = jest.fn().mockName('handleSetSidebarTab')
const setUiState = jest.fn().mockName('setUiState')
const setModelState = jest.fn().mockName('setModelState')

const mockNavigateFn = jest.fn()
const mockSetSearchParams = jest.fn()
let mockSearchParamsFn = [new URLSearchParams(''), mockSetSearchParams]
jest.mock('@github-ui/use-navigate', () => {
  return {
    useNavigate: () => mockNavigateFn,
    useSearchParams: () => mockSearchParamsFn,
  }
})

jest.mock('@github-ui/hydro-analytics', () => {
  return {
    sendEvent: jest.fn(),
  }
})

afterEach(() => {
  jest.clearAllMocks()
})

describe('PlaygroundHeader', () => {
  afterEach(() => {
    jest.clearAllMocks()
    mockSearchParamsFn = [new URLSearchParams(''), mockSetSearchParams]
  })

  test('renders when not in comparison mode', async () => {
    const friendlyName = 'A Very Fun Model'
    const model = Object.assign({}, mockModel, {friendly_name: friendlyName})
    const modelState = Object.assign({}, mockModelState, {model})
    const models: ModelState[] = []
    const position = Panel.Main
    models[position] = modelState
    const state = mockPlaygroundState({models})

    mockVerifiedFetchJSON.mockResolvedValueOnce({
      ok: true,
      statusText: 'OK',
      json: async () => {
        return [mockModel, mockO1Model]
      },
    })

    const {container, user} = render(
      <PlaygroundHeader
        model={model}
        position={position}
        gettingStarted={mockGettingStarted}
        uiState={mockLocalStorageUiState}
        setUiState={setUiState}
        handleSetSidebarTab={handleSetSidebarTab}
      />,
      state,
      {routePayload: mockGettingStartedPayload()},
    )

    expect(within(container).getByRole('button', {name: 'Switch model'})).toBeInTheDocument()
    expect(within(container).getByTestId('get-api-key-button')).toBeInTheDocument()
    expect(within(container).getByTestId('model-friendly-name')).toHaveTextContent(friendlyName)
    expect(within(container).queryByRole('button', {name: 'Close model'})).not.toBeInTheDocument()

    const compareButton = within(container).getByTestId('compare-model-button')
    expect(compareButton).toBeInTheDocument()

    await user.click(compareButton)

    expect(screen.getAllByRole('option')).toHaveLength(2)

    await user.click(screen.getByText('O1 Mini'))

    expect(mockSetSearchParams).toHaveBeenCalledWith({compare_to: mockO1Model.name})
    expect(setModelState).not.toHaveBeenCalled()
  })

  test('allows opening API key dialog', async () => {
    const registry = 'somemodelprovider'
    const modelName = 'a-nice-model'
    const publisher = PUBLISHER.AI21Labs
    const model = Object.assign({}, mockModel, {registry, name: modelName, publisher})
    const modelState = Object.assign({}, mockModelState, {model})
    const models: ModelState[] = []
    const position = Panel.Main
    models[position] = modelState
    const gettingStarted = mockGettingStarted
    const routePayload = mockGettingStartedPayload({gettingStarted})
    const appPayload = {current_user: Object.assign({}, mockUser, {analyticsTrackingId: '8675309'})}

    const {container, user} = render(
      <PlaygroundHeader
        model={model}
        position={position}
        gettingStarted={gettingStarted}
        handleSetSidebarTab={handleSetSidebarTab}
        uiState={mockLocalStorageUiState}
        setUiState={setUiState}
      />,
      mockPlaygroundState({models}),
      {appPayload, routePayload},
    )

    const getApiKeyButton = within(container).getByTestId('get-api-key-button')
    expect(getApiKeyButton).toBeInTheDocument()
    expect(screen.queryByRole('dialog', {name: 'Get API key'})).not.toBeInTheDocument()

    await user.click(getApiKeyButton)

    expect(screen.getByRole('dialog', {name: 'Get API key'})).toBeInTheDocument()
    expect(sendEvent).toHaveBeenCalledTimes(1)
    expect(sendEvent).toHaveBeenCalledWith(GettingStartedButtonClicked, {
      registry,
      model: modelName,
      publisher,
      analyticsTrackingId: '8675309',
      label: 'Use this model',
    })
    expect(setModelState).not.toHaveBeenCalled()
  })

  test('renders in comparison mode for a model in the main panel', async () => {
    const model1 = mockModel
    const model2 = Object.assign({}, model1, {
      id: `${model1.id}-v2`,
      name: `${model1.name}v2`,
      original_name: `${model1.original_name}-v2`,
      friendly_name: `${model1.friendly_name} v2`,
    })
    const modelState1 = Object.assign({}, mockModelState, {
      model: model1,
      gettingStarted: mockGettingStarted,
      modelInputSchema: mockModelInputSchema,
    })
    const modelState2 = Object.assign({}, modelState1, {model: model2})
    const modelsInPlaygroundState = [modelState1, modelState2]
    const state = mockPlaygroundState({models: modelsInPlaygroundState})

    mockSearchParamsFn = [new URLSearchParams(`compare_to=${model2.name}`), mockSetSearchParams]

    const {container, user} = render(
      <PlaygroundHeader
        model={model1}
        position={Panel.Main}
        gettingStarted={mockGettingStarted}
        uiState={mockLocalStorageUiState}
        setUiState={setUiState}
        handleSetSidebarTab={handleSetSidebarTab}
      />,
      state,
    )

    expect(within(container).getByRole('button', {name: 'Switch model'})).toBeInTheDocument()
    expect(within(container).getByTestId('get-api-key-button')).toBeInTheDocument()
    expect(within(container).getByText(model1.friendly_name)).toBeInTheDocument()
    expect(within(container).queryByText(model2.friendly_name)).not.toBeInTheDocument()
    expect(within(container).queryByRole('button', {name: 'Compare'})).not.toBeInTheDocument()
    const closeModelButton = within(container).getByRole('button', {name: 'Close model'})
    expect(closeModelButton).toBeInTheDocument()

    await user.click(closeModelButton)

    expect(mockNavigateFn).toHaveBeenCalledWith({
      pathname: modelPlaygroundPath(model1),
      search: 'retain=1',
    })
    expect(sendEvent).not.toHaveBeenCalled()
    expect(setModelState).not.toHaveBeenCalled()
  }, 5000) // set timeout to 5 seconds

  test('updates the url when the model changes', async () => {
    const model1 = mockModel
    const model2 = Object.assign({}, model1, {
      id: `${model1.id}-v2`,
      name: `${model1.name}v2`,
      original_name: `${model1.original_name}-v2`,
      friendly_name: `${model1.friendly_name} v2`,
    })

    const client = getQueryClient()
    client.setQueryData(['github-models', 'models'], [model1, model2])

    const modelState = Object.assign({}, mockModelState, {
      model: model1,
      gettingStarted: mockGettingStarted,
      modelInputSchema: mockModelInputSchema,
    })
    const state = mockPlaygroundState({models: [modelState]})

    const {user} = render(
      <PlaygroundHeader
        model={model1}
        position={Panel.Main}
        gettingStarted={mockGettingStarted}
        handleSetSidebarTab={handleSetSidebarTab}
        uiState={mockLocalStorageUiState}
        setUiState={setUiState}
      />,
      state,
    )

    await user.click(screen.getByLabelText('Switch model'))
    await user.click(screen.getByText(model2.friendly_name))

    expect(mockNavigateFn).toHaveBeenCalledWith({
      pathname: modelPlaygroundPath(model2),
      search: '',
    })
    expect(setModelState).not.toHaveBeenCalled()
  })

  test('deletes the suggestion query parameter in the url when the model changes', async () => {
    const model1 = mockModel
    const model2 = Object.assign({}, model1, {
      id: `${model1.id}-v2`,
      name: `${model1.name}v2`,
      original_name: `${model1.original_name}-v2`,
      friendly_name: `${model1.friendly_name} v2`,
    })

    const client = getQueryClient()
    client.setQueryData(['github-models', 'models'], [model1, model2])
    mockSearchParamsFn = [new URLSearchParams('resend-user-prompt'), mockSetSearchParams]
    const spy = jest.spyOn(URLSearchParams.prototype, 'delete')
    const modelState = Object.assign({}, mockModelState, {
      model: model1,
      gettingStarted: mockGettingStarted,
      modelInputSchema: mockModelInputSchema,
    })
    const state = mockPlaygroundState({models: [modelState]})

    const {user} = render(
      <PlaygroundHeader
        model={model1}
        position={Panel.Main}
        gettingStarted={mockGettingStarted}
        handleSetSidebarTab={handleSetSidebarTab}
        uiState={mockLocalStorageUiState}
        setUiState={setUiState}
      />,
      state,
    )

    await user.click(screen.getByLabelText('Switch model'))
    await user.click(screen.getByText(model2.friendly_name))

    expect(spy).toHaveBeenCalledWith('resend-user-prompt')
    expect(mockNavigateFn).toHaveBeenCalledWith({
      pathname: modelPlaygroundPath(model2),
      search: '',
    })
    expect(setModelState).not.toHaveBeenCalled()
  })

  test('keeps the compare_to query string when the model changes', async () => {
    const model1 = mockModel
    const model2 = Object.assign({}, model1, {
      id: `${model1.id}-v2`,
      name: `${model1.name}v2`,
      original_name: `${model1.original_name}-v2`,
      friendly_name: `${model1.friendly_name} v2`,
    })

    const model3 = Object.assign({}, model1, {
      id: `${model1.id}-v3`,
      name: `${model1.name}v3`,
      original_name: `${model1.original_name}-v3`,
      friendly_name: `${model1.friendly_name} v3`,
    })

    const client = getQueryClient()
    client.setQueryData(['github-models', 'models'], [model1, model2])

    const modelState = Object.assign({}, mockModelState, {
      model: model1,
      gettingStarted: mockGettingStarted,
      modelInputSchema: mockModelInputSchema,
    })
    const modelState3 = Object.assign({}, modelState, {model: model3})
    const state = mockPlaygroundState({models: [modelState, modelState3]})

    mockSearchParamsFn = [new URLSearchParams(`compare_to=${model3.name}`), mockSetSearchParams]

    const {user} = render(
      <PlaygroundHeader
        model={model1}
        position={Panel.Main}
        gettingStarted={mockGettingStarted}
        handleSetSidebarTab={handleSetSidebarTab}
        uiState={mockLocalStorageUiState}
        setUiState={setUiState}
      />,
      state,
    )

    await user.click(screen.getByLabelText('Switch model'))
    await user.click(screen.getByText(model2.friendly_name))

    expect(mockNavigateFn).toHaveBeenCalledWith({
      pathname: modelPlaygroundPath(model2),
      search: `compare_to=${model3.name}`,
    })
    expect(setModelState).not.toHaveBeenCalled()
  })

  test('renders the prompt editor button when the feature flag is enabled and not in comparison mode', () => {
    mockUseFeatureFlag.mockReturnValue({
      github_models_prompt_editor: true,
    })
    const model = mockModel
    const state = mockPlaygroundState()

    const {container} = render(
      <PlaygroundHeader
        model={model}
        position={Panel.Main}
        gettingStarted={mockGettingStarted}
        uiState={mockLocalStorageUiState}
        setUiState={setUiState}
        handleSetSidebarTab={handleSetSidebarTab}
      />,
      state,
    )

    expect(within(container).getByRole('link', {name: 'Prompt editor'})).toBeInTheDocument()
  })

  test('does not render the prompt editor button when the feature flag is disabled', () => {
    mockUseFeatureFlag.mockReturnValue({
      github_models_prompt_evals: false,
      github_models_prompt_editor: false,
    })
    const model = mockModel
    const state = mockPlaygroundState()

    const {container} = render(
      <PlaygroundHeader
        model={model}
        position={Panel.Main}
        gettingStarted={mockGettingStarted}
        uiState={mockLocalStorageUiState}
        setUiState={setUiState}
        handleSetSidebarTab={handleSetSidebarTab}
      />,
      state,
    )

    expect(within(container).queryByRole('button', {name: 'Prompt editor'})).not.toBeInTheDocument()
  })

  test('does not render the prompt editor button when in comparison mode', () => {
    mockUseFeatureFlag.mockReturnValue({
      github_models_prompt_evals: true,
    })

    const model = mockModel
    const state = mockPlaygroundState({models: [mockModelState, mockModelState]})

    const {container} = render(
      <PlaygroundHeader
        model={model}
        position={Panel.Main}
        gettingStarted={mockGettingStarted}
        uiState={mockLocalStorageUiState}
        setUiState={setUiState}
        handleSetSidebarTab={handleSetSidebarTab}
      />,
      state,
    )

    expect(within(container).queryByRole('button', {name: 'Prompt editor'})).not.toBeInTheDocument()
  })
})

function render(component: JSX.Element, playgroundState: PlaygroundState, opts: TestRenderOptions = {}) {
  const manager = {} as PlaygroundManager
  manager.setModelState = setModelState

  return htmlRender(
    <PlaygroundStateProvider state={playgroundState}>
      <PlaygroundManagerProvider manager={manager}>{component}</PlaygroundManagerProvider>
    </PlaygroundStateProvider>,
    opts,
  )
}
