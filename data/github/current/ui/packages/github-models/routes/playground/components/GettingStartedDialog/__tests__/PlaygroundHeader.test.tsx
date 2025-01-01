import {screen, within} from '@testing-library/react'
import {render as htmlRender, RouteContext, type TestRenderOptions} from '@github-ui/react-core/test-utils'
import {PlaygroundHeader} from '../PlaygroundHeader'
import {ModelUrlHelper} from '../../../../../utils/model-url-helper'
import {mockGettingStarted, mockModelInputSchema, mockModel, mockModelState} from '../../../__tests__/mocks'
import {Panel, PlaygroundManagerContext, type PlaygroundManager} from '../../../../../utils/playground-manager'
import {PlaygroundStateProvider} from '../../../../../contexts/PlaygroundStateContext'
import type {PlaygroundState} from '../../../../../types'
import {mockPlaygroundState} from './mocks'
import {sendEvent} from '@github-ui/hydro-analytics'
import {GettingStartedButtonClicked} from '../../../../../utils/playground-types'
import {getQueryClient} from '@github-ui/react-core/query-client'

const setSyncInputs = jest.fn().mockName('setSyncInputs')
const removeModel = jest.fn().mockName('removeModel')
const handleSetSidebarTab = jest.fn().mockName('handleSetSidebarTab')
const getSideModel = jest.fn().mockName('getSideModel')
jest.mock('@github-ui/hydro-analytics', () => {
  return {
    sendEvent: jest.fn(),
  }
})

describe('PlaygroundHeader', () => {
  afterEach(() => {
    jest.clearAllMocks()
  })

  test('renders when not in comparison mode', async () => {
    const modelState = Object.assign({}, mockModelState, {
      model: mockModel,
      gettingStarted: mockGettingStarted,
      modelInputSchema: mockModelInputSchema,
    })
    const state = mockPlaygroundState({models: [modelState]})
    const startingPathname = ModelUrlHelper.playgroundUrl(mockModel)
    const startingSearch = ''

    const {container, user} = render(
      <PlaygroundHeader
        model={mockModel}
        modelInputSchema={mockModelInputSchema}
        canUseO1Models
        position={Panel.Main}
        gettingStarted={mockGettingStarted}
        handleSetSidebarTab={handleSetSidebarTab}
      />,
      state,
      {pathname: startingPathname, search: startingSearch},
    )

    expect(within(container).getByRole('button', {name: 'Switch model'})).toBeInTheDocument()
    const getApiKeyButton = within(container).getByRole('button', {name: 'Get API key'})
    expect(getApiKeyButton).toBeInTheDocument()
    expect(within(container).getByText(mockModel.friendly_name)).toBeInTheDocument()
    expect(within(container).queryByRole('button', {name: 'Close model'})).not.toBeInTheDocument()
    expect(setSyncInputs).not.toHaveBeenCalled()
    expect(removeModel).not.toHaveBeenCalled()
    expect(RouteContext.location?.pathname).toEqual(startingPathname)
    expect(RouteContext.location?.search).toEqual(startingSearch)
    expect(screen.queryByRole('dialog', {name: 'Get API key'})).not.toBeInTheDocument()

    await user.click(getApiKeyButton)

    expect(screen.getByRole('dialog', {name: 'Get API key'})).toBeInTheDocument()
    expect(sendEvent).toHaveBeenCalledTimes(1)
    expect(sendEvent).toHaveBeenCalledWith(GettingStartedButtonClicked, {
      registry: mockModel.registry,
      model: mockModel.name,
      publisher: mockModel.publisher,
    })
  }, 5000) // set timeout to 5 seconds

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
    const startingPathname = ModelUrlHelper.playgroundUrl(model1)
    const startingSearch = `?compare_to=${model2.id}`

    const {container, user} = render(
      <PlaygroundHeader
        model={model1}
        modelInputSchema={mockModelInputSchema}
        canUseO1Models
        position={Panel.Main}
        gettingStarted={mockGettingStarted}
        handleSetSidebarTab={handleSetSidebarTab}
      />,
      state,
      {pathname: startingPathname, search: startingSearch},
    )

    expect(within(container).getByRole('button', {name: 'Switch model'})).toBeInTheDocument()
    expect(within(container).getByRole('button', {name: 'Get API key'})).toBeInTheDocument()
    expect(within(container).getByText(model1.friendly_name)).toBeInTheDocument()
    expect(within(container).queryByText(model2.friendly_name)).not.toBeInTheDocument()
    const closeModelButton = within(container).getByRole('button', {name: 'Close model'})
    expect(closeModelButton).toBeInTheDocument()
    expect(setSyncInputs).not.toHaveBeenCalled()
    expect(removeModel).not.toHaveBeenCalled()

    await user.click(closeModelButton)

    expect(setSyncInputs).toHaveBeenCalledTimes(1)
    expect(setSyncInputs).toHaveBeenCalledWith(false)
    expect(removeModel).toHaveBeenCalledTimes(1)
    expect(removeModel).toHaveBeenCalledWith(Panel.Main)
    expect(RouteContext.location?.pathname).toEqual(ModelUrlHelper.playgroundUrl(model1))
    expect(RouteContext.location?.search).toEqual('')
    expect(sendEvent).not.toHaveBeenCalled()
  })

  test('should update the url when the model changes', async () => {
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
    const startingPathname = ModelUrlHelper.playgroundUrl(mockModel)
    const startingSearch = ''

    const {user} = render(
      <PlaygroundHeader
        model={model1}
        modelInputSchema={mockModelInputSchema}
        canUseO1Models
        position={Panel.Main}
        gettingStarted={mockGettingStarted}
        handleSetSidebarTab={handleSetSidebarTab}
      />,
      state,
      {pathname: startingPathname, search: startingSearch},
    )

    await user.click(screen.getByLabelText('Switch model'))
    await user.click(screen.getByText(model2.friendly_name))

    expect(RouteContext.location?.pathname).toEqual(ModelUrlHelper.playgroundUrl(model2))
  })
})

function render(component: JSX.Element, playgroundState: PlaygroundState, opts: TestRenderOptions = {}) {
  const manager = {} as PlaygroundManager
  manager.setSyncInputs = setSyncInputs
  manager.removeModel = removeModel
  manager.getSideModel = getSideModel
  return htmlRender(
    <PlaygroundManagerContext.Provider value={manager}>
      <PlaygroundStateProvider state={playgroundState}>{component}</PlaygroundStateProvider>
    </PlaygroundManagerContext.Provider>,
    opts,
  )
}
