import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {useFeatureFlags} from '@github-ui/react-core/use-feature-flag'
import {render} from '@github-ui/react-core/test-utils'
import {screen, within} from '@testing-library/react'
import {ModelsPlaygroundRoute} from '../ModelsPlaygroundRoute'
import {mockModel, mockGettingStartedPayload, mockModelDetails} from './mocks'
import {useResponsiveValue} from '@primer/react'
import {setLocalStorageUiState} from '../../../utils/playground-local-storage'
import {SidebarSelectionOptions} from '../../../types'
import {Panel} from '../../../utils/playground-manager'
import type {Model} from '@github-ui/marketplace-common'

jest.mock('@github-ui/react-core/use-route-payload')
jest.mock('@github-ui/react-core/use-feature-flag')

jest.mock('@primer/react', () => {
  const original = jest.requireActual('@primer/react')
  return {...original, useResponsiveValue: jest.fn()}
})
jest.mock('../../../utils/playground-local-storage', () => {
  return {
    getDefaultUiState: () => ({}),
    setLocalStorageUiState: jest.fn(),
    getSavedPlaygroundMessages: jest.fn().mockName('getSavedPlaygroundMessages'),
  }
})
const {Playground: RealPlayground} = jest.requireActual('../components/Playground')
jest.mock('../components/Playground', () => ({
  Playground: jest.fn(() => <div data-testid="mock-playground" />),
}))

const mockNavigateFn = jest.fn().mockName('useNavigate')
let mockUseSearchParams = [new URLSearchParams(''), jest.fn()]
jest.mock('@github-ui/use-navigate', () => {
  return {
    useNavigate: () => mockNavigateFn,
    useSearchParams: () => mockUseSearchParams,
  }
})

const mockUseResponsiveValue = jest.mocked(useResponsiveValue)
const mockUseRoutePayload = jest.mocked(useRoutePayload)
const mockUseFeatureFlags = jest.mocked(useFeatureFlags)
mockUseFeatureFlags.mockReturnValue({
  project_neutron_rag: false,
})

const getPlaygroundProps = (props: Partial<Parameters<typeof RealPlayground>[0]> = {}) => ({
  featuredModels: undefined,
  modelState: undefined,
  position: Panel.Main,
  ...props,
})
const getMockModel = (model: Partial<Model>) => ({
  ...mockModel,
  ...model,
})
const getModelDetails = (model: Partial<Model>) => ({
  ...mockModelDetails,
  catalogData: getMockModel(model),
})

describe('ModelsPlaygroundRoute', () => {
  let Playground: jest.Mock

  beforeEach(() => {
    Playground = jest.requireMock('../components/Playground').Playground
  })

  afterEach(() => {
    jest.clearAllMocks()
  })

  test('loads the playground view without a model', async () => {
    mockUseRoutePayload.mockReturnValue(mockGettingStartedPayload({model: undefined}))

    render(<ModelsPlaygroundRoute />)

    expect(setLocalStorageUiState).toHaveBeenCalledWith({sidebarTab: SidebarSelectionOptions.DETAILS})
    expect(Playground).toHaveBeenCalledWith(getPlaygroundProps(), {})
  })

  test('loads the playground view with a model', async () => {
    mockUseRoutePayload.mockReturnValue(mockGettingStartedPayload({model: mockModel}))

    render(<ModelsPlaygroundRoute />)

    expect(setLocalStorageUiState).not.toHaveBeenCalled()
    expect(Playground).toHaveBeenCalledWith(
      getPlaygroundProps({
        modelState: expect.objectContaining({
          catalogData: mockModel,
        }),
      }),
      {},
    )
  })

  test('updates the playground view when the model changes', async () => {
    const model1 = getMockModel({name: 'model1'})
    const model2 = getMockModel({name: 'model2'})

    mockUseRoutePayload.mockReturnValue(mockGettingStartedPayload({model: model1}))

    const view = render(<ModelsPlaygroundRoute />)

    expect(setLocalStorageUiState).not.toHaveBeenCalled()
    expect(Playground).toHaveBeenCalledWith(
      getPlaygroundProps({modelState: expect.objectContaining({catalogData: model1})}),
      {},
    )

    // Update the model and ensure the playground is re-rendered
    mockUseRoutePayload.mockReturnValue(mockGettingStartedPayload({model: model2}))

    view.rerender(<ModelsPlaygroundRoute />)

    expect(Playground).toHaveBeenCalledWith(
      getPlaygroundProps({modelState: expect.objectContaining({catalogData: model2})}),
      {},
    )
  })

  test('updates the playground when a side model is added', async () => {
    const model1 = getMockModel({name: 'model1'})
    const model2 = getMockModel({name: 'model2'})

    mockUseRoutePayload.mockReturnValue(mockGettingStartedPayload({model: model1}))

    const view = render(<ModelsPlaygroundRoute />)

    expect(setLocalStorageUiState).not.toHaveBeenCalled()
    expect(Playground).toHaveBeenCalledWith(
      getPlaygroundProps({modelState: expect.objectContaining({catalogData: model1})}),
      {},
    )

    // Add a side model
    mockUseRoutePayload.mockReturnValue(
      mockGettingStartedPayload({model: model1, comparedModelDetails: getModelDetails(model2)}),
    )

    view.rerender(<ModelsPlaygroundRoute />)

    expect(Playground).toHaveBeenCalledWith(
      getPlaygroundProps({
        modelState: expect.objectContaining({catalogData: model1}),
      }),
      {},
    )
    expect(Playground).toHaveBeenCalledWith(
      getPlaygroundProps({
        modelState: expect.objectContaining({catalogData: model2}),
        position: Panel.Side,
      }),
      {},
    )
  })

  test('loads a main and side model directly', async () => {
    const model1 = getMockModel({name: 'model1'})
    const model2 = getMockModel({name: 'model2'})

    mockUseRoutePayload.mockReturnValue(
      mockGettingStartedPayload({model: model1, comparedModelDetails: getModelDetails(model2)}),
    )

    render(<ModelsPlaygroundRoute />)

    expect(setLocalStorageUiState).not.toHaveBeenCalled()
    expect(Playground).toHaveBeenCalledWith(
      getPlaygroundProps({
        modelState: expect.objectContaining({catalogData: model1}),
      }),
      {},
    )
    expect(Playground).toHaveBeenCalledWith(
      getPlaygroundProps({
        modelState: expect.objectContaining({catalogData: model2}),
        position: Panel.Side,
      }),
      {},
    )
  })

  test('changes the side model independently of the main model', async () => {
    const model1 = getMockModel({name: 'model1'})
    const model2 = getMockModel({name: 'model2'})
    const model3 = getMockModel({name: 'model3'})

    mockUseRoutePayload.mockReturnValue(
      mockGettingStartedPayload({model: model1, comparedModelDetails: getModelDetails(model2)}),
    )

    const view = render(<ModelsPlaygroundRoute />)

    expect(setLocalStorageUiState).not.toHaveBeenCalled()
    expect(Playground).toHaveBeenCalledWith(
      getPlaygroundProps({
        modelState: expect.objectContaining({catalogData: model1}),
      }),
      {},
    )
    expect(Playground).toHaveBeenCalledWith(
      getPlaygroundProps({
        modelState: expect.objectContaining({catalogData: model2}),
        position: Panel.Side,
      }),
      {},
    )

    // Switch the side model
    mockUseRoutePayload.mockReturnValue(
      mockGettingStartedPayload({model: model1, comparedModelDetails: getModelDetails(model3)}),
    )

    view.rerender(<ModelsPlaygroundRoute />)

    expect(Playground).toHaveBeenCalledWith(
      getPlaygroundProps({
        modelState: expect.objectContaining({catalogData: model1}),
      }),
      {},
    )
    expect(Playground).toHaveBeenCalledWith(
      getPlaygroundProps({
        modelState: expect.objectContaining({catalogData: model3}),
        position: Panel.Side,
      }),
      {},
    )
  })

  test('leaves the main model when the side model is removed', async () => {
    const model1 = getMockModel({name: 'model1'})
    const model2 = getMockModel({name: 'model2'})

    mockUseRoutePayload.mockReturnValue(
      mockGettingStartedPayload({model: model1, comparedModelDetails: getModelDetails(model2)}),
    )

    const view = render(<ModelsPlaygroundRoute />)

    expect(Playground).toHaveBeenCalledWith(
      getPlaygroundProps({
        modelState: expect.objectContaining({catalogData: model1}),
      }),
      {},
    )
    expect(Playground).toHaveBeenCalledWith(
      getPlaygroundProps({
        modelState: expect.objectContaining({catalogData: model2}),
        position: Panel.Side,
      }),
      {},
    )

    // Remove the side model
    mockUseRoutePayload.mockReturnValue(mockGettingStartedPayload({model: model1}))

    view.rerender(<ModelsPlaygroundRoute />)

    expect(Playground).toHaveBeenCalledWith(
      getPlaygroundProps({
        modelState: expect.objectContaining({catalogData: model1}),
      }),
      {},
    )
  })

  test('sets the side model to the main model when the main model is removed', async () => {
    const model1 = getMockModel({name: 'model1'})
    const model2 = getMockModel({name: 'model2'})

    mockUseRoutePayload.mockReturnValue(
      mockGettingStartedPayload({model: model1, comparedModelDetails: getModelDetails(model2)}),
    )

    const view = render(<ModelsPlaygroundRoute />)

    expect(setLocalStorageUiState).not.toHaveBeenCalled()
    expect(Playground).toHaveBeenCalledWith(
      getPlaygroundProps({
        modelState: expect.objectContaining({catalogData: model1}),
      }),
      {},
    )
    expect(Playground).toHaveBeenCalledWith(
      getPlaygroundProps({
        modelState: expect.objectContaining({catalogData: model2}),
        position: Panel.Side,
      }),
      {},
    )

    // Remove the main model, making the side model the new main model
    mockUseSearchParams = [new URLSearchParams('retain=1'), jest.fn()]
    mockUseRoutePayload.mockReturnValue(mockGettingStartedPayload({model: model2}))

    view.rerender(<ModelsPlaygroundRoute />)

    expect(Playground).toHaveBeenCalledWith(
      getPlaygroundProps({
        modelState: expect.objectContaining({catalogData: model2}),
      }),
      {},
    )
  })

  test('loads with an icebreaker message when provided', async () => {
    mockUseRoutePayload.mockReturnValue(
      mockGettingStartedPayload({
        model: mockModel,
        miniplaygroundIcebreaker: 'icebreaker message',
      }),
    )

    render(<ModelsPlaygroundRoute />)

    expect(setLocalStorageUiState).not.toHaveBeenCalled()
    expect(Playground).toHaveBeenCalledWith(
      getPlaygroundProps({
        modelState: expect.objectContaining({catalogData: mockModel}),
      }),
      {},
    )
  })

  test('does not display side model when on mobile', async () => {
    const model1 = getMockModel({name: 'model1'})
    const model2 = getMockModel({name: 'model2'})

    mockUseResponsiveValue.mockReturnValue(true)
    mockUseRoutePayload.mockReturnValue(
      mockGettingStartedPayload({model: model1, comparedModelDetails: getModelDetails(model2)}),
    )

    render(<ModelsPlaygroundRoute />)

    expect(setLocalStorageUiState).not.toHaveBeenCalled()
    expect(Playground).toHaveBeenCalledWith(
      getPlaygroundProps({
        modelState: expect.objectContaining({catalogData: model1}),
      }),
      {},
    )
    expect(Playground).not.toHaveBeenCalledWith(
      getPlaygroundProps({
        modelState: expect.objectContaining({catalogData: model2}),
        position: Panel.Side,
      }),
      {},
    )
  })

  // https://github.com/github/models/issues/399
  test('preserves chat input when toggling mobile view on and off in comparison mode', async () => {
    Playground.mockImplementation(RealPlayground)
    const model1 = getMockModel({name: 'model1'})
    const model2 = getMockModel({name: 'model2'})
    mockUseResponsiveValue.mockReturnValue(false) // not mobile
    mockUseRoutePayload.mockReturnValue(
      mockGettingStartedPayload({model: model1, comparedModelDetails: getModelDetails(model2)}),
    )

    const view = render(<ModelsPlaygroundRoute />)

    let promptInputs = screen.getAllByRole('textbox', {name: 'Prompt'})
    expect(promptInputs).toHaveLength(2)

    await view.user.type(promptInputs[0]!, 'a')

    expect(promptInputs[0]!).toHaveValue('a')
    expect(promptInputs[1]!).toHaveValue('a')

    mockUseResponsiveValue.mockReturnValue(true) // mobile
    view.rerender(<ModelsPlaygroundRoute />)

    promptInputs = screen.getAllByRole('textbox', {name: 'Prompt'})
    expect(promptInputs).toHaveLength(1)
    expect(promptInputs[0]!).toHaveValue('a')

    mockUseResponsiveValue.mockReturnValue(false) // not mobile
    view.rerender(<ModelsPlaygroundRoute />)

    promptInputs = screen.getAllByRole('textbox', {name: 'Prompt'})
    expect(promptInputs).toHaveLength(2)
    expect(promptInputs[0]!).toHaveValue('a')
    expect(promptInputs[1]!).toHaveValue('a')
  })

  it('renders data-hpc attribute without a model', () => {
    Playground.mockImplementation(RealPlayground)
    mockUseRoutePayload.mockReturnValue(mockGettingStartedPayload({model: undefined}))

    render(<ModelsPlaygroundRoute />)

    const featuredModelContainer = screen.getByTestId('featured-model-container')
    expect(featuredModelContainer).toHaveAttribute('data-hpc')
  })

  it('renders data-hpc attribute with a model', () => {
    Playground.mockImplementation(RealPlayground)
    mockUseRoutePayload.mockReturnValue(mockGettingStartedPayload({model: mockModel}))

    const {container} = render(<ModelsPlaygroundRoute />)

    const promptTextarea = within(container).getByRole('textbox', {name: 'Prompt'})
    expect(promptTextarea).toHaveAttribute('data-hpc')
  })
})
