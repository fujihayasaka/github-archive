import {render as htmlRender} from '@github-ui/react-core/test-utils'
import {screen, within} from '@testing-library/react'
import {ComparisonModeMenu} from '../ComparisonModeMenu'
import {Panel, PlaygroundManagerContext, type PlaygroundManager} from '../../../../utils/playground-manager'
import {PlaygroundStateProvider} from '../../../../contexts/PlaygroundStateContext'
import {mockModelState, mockPlaygroundState} from './mocks'
import {mockModel, mockModelInputSchema} from '../../__tests__/mocks'
import {mockResizeObserver} from '../GettingStartedDialog/__tests__/mocks'
import type {PlaygroundState} from '../../../../types'

const setSyncInputs = jest.fn().mockName('setSyncInputs')
const setModelState = jest.fn().mockName('setModelState')
const setParameters = jest.fn().mockName('setParameters')
const resetParamsAndSystemPrompt = jest.fn().mockName('resetParamsAndSystemPrompt')

describe('ComparisonModeMenu', () => {
  beforeEach(() => {
    // Necessary to avoid a 'TypeError: observer.observe is not a function' error when all the GettingStartedDialog
    // tests are run.
    mockResizeObserver()
  })

  afterEach(() => {
    jest.resetAllMocks()
  })

  test('renders when inputs are synced', async () => {
    const modelState = mockModelState()
    const playgroundState = mockPlaygroundState({syncInputs: true})

    const {container, user} = render(
      <ComparisonModeMenu modelState={modelState} position={Panel.Main} />,
      playgroundState,
    )

    const showParamsSettingButton = within(container).getByRole('button', {name: 'Show parameters setting'})
    expect(showParamsSettingButton).toBeInTheDocument()
    expect(screen.queryByRole('menu', {name: 'Show model info'})).not.toBeInTheDocument()

    // Open parameters setting menu:
    await user.click(showParamsSettingButton)
    const paramsSettingMenu = screen.getByRole('menu', {name: 'Show parameters setting'})
    expect(paramsSettingMenu).toBeInTheDocument()
    expect(within(paramsSettingMenu).getByTestId('model-parameters')).toBeInTheDocument()
    expect(within(paramsSettingMenu).getByRole('heading', {name: 'Parameters', level: 1})).toBeInTheDocument()
    expect(within(paramsSettingMenu).queryByRole('button', {name: 'Reset to default inputs'})).not.toBeInTheDocument()
    const syncCheckbox = within(paramsSettingMenu).getByRole('checkbox', {name: 'Sync chat input and parameters'})
    expect(syncCheckbox).toBeInTheDocument()
    expect(syncCheckbox).toBeChecked()
    expect(setSyncInputs).not.toHaveBeenCalled()

    await user.click(syncCheckbox)

    expect(setSyncInputs).toHaveBeenCalledTimes(1)
    expect(setSyncInputs).toHaveBeenCalledWith(false)
    expect(setModelState).not.toHaveBeenCalled()
    expect(setParameters).not.toHaveBeenCalled()
    expect(resetParamsAndSystemPrompt).not.toHaveBeenCalled()
  })

  test('renders when inputs are not synced', async () => {
    const systemPrompt = 'hello world'
    const chatInput = 'Some Chat Input'
    const modelState = mockModelState({chatInput, systemPrompt})
    const otherModel = Object.assign({}, mockModel, {id: `${mockModel.id}-other`, name: `${mockModel.name}-other`})
    const otherModelState = mockModelState({catalogData: otherModel})
    const models = [modelState, otherModelState]
    const playgroundState = mockPlaygroundState({syncInputs: false, models})

    const {container, user} = render(
      <ComparisonModeMenu modelState={modelState} position={Panel.Main} />,
      playgroundState,
    )

    const showParamsSettingButton = within(container).getByRole('button', {name: 'Show parameters setting'})
    expect(showParamsSettingButton).toBeInTheDocument()

    // Open parameters setting menu:
    await user.click(showParamsSettingButton)
    const paramsSettingMenu = screen.getByRole('menu', {name: 'Show parameters setting'})
    expect(paramsSettingMenu).toBeInTheDocument()
    const syncCheckbox = within(paramsSettingMenu).getByRole('checkbox', {name: 'Sync chat input and parameters'})
    expect(syncCheckbox).toBeInTheDocument()
    expect(syncCheckbox).not.toBeChecked()
    expect(setSyncInputs).not.toHaveBeenCalled()

    await user.click(syncCheckbox)

    expect(setSyncInputs).toHaveBeenCalledTimes(1)
    expect(setSyncInputs).toHaveBeenCalledWith(true)
    expect(setModelState).toHaveBeenCalledTimes(1)
    const expectedNewModelState = Object.assign({}, otherModelState, {chatInput, systemPrompt})
    expect(setModelState).toHaveBeenCalledWith(Panel.Side, expectedNewModelState)
    expect(setParameters).not.toHaveBeenCalled()
    expect(resetParamsAndSystemPrompt).not.toHaveBeenCalled()
  })

  test('allows resetting inputs', async () => {
    const modelInputSchema = Object.assign({}, mockModelInputSchema, {capabilities: {systemPrompt: true}})
    const modelState = mockModelState({modelInputSchema, parametersHasChanges: true})
    const models = [modelState]
    const playgroundState = mockPlaygroundState({syncInputs: true, models})
    const position = Panel.Main

    const {container, user} = render(
      <ComparisonModeMenu modelState={modelState} position={position} />,
      playgroundState,
    )

    const showParamsSettingButton = within(container).getByRole('button', {name: 'Show parameters setting'})
    expect(showParamsSettingButton).toBeInTheDocument()

    // Open parameters setting menu:
    await user.click(showParamsSettingButton)
    const paramsSettingMenu = screen.getByRole('menu', {name: 'Show parameters setting'})
    expect(paramsSettingMenu).toBeInTheDocument()

    const resetInputsButton = within(paramsSettingMenu).getByRole('button', {name: 'Reset to default inputs'})
    expect(resetInputsButton).toBeInTheDocument()
    expect(resetParamsAndSystemPrompt).not.toHaveBeenCalled()

    await user.click(resetInputsButton)

    expect(resetParamsAndSystemPrompt).toHaveBeenCalledTimes(1)
    expect(resetParamsAndSystemPrompt).toHaveBeenCalledWith(position, {
      catalogData: modelState.catalogData,
      modelInputSchema: modelState.modelInputSchema,
      gettingStarted: modelState.gettingStarted,
    })
  })
})

function render(component: JSX.Element, playgroundState?: PlaygroundState) {
  const manager = {} as PlaygroundManager
  manager.setSyncInputs = setSyncInputs
  manager.setModelState = setModelState
  manager.setParameters = setParameters
  manager.resetParamsAndSystemPrompt = resetParamsAndSystemPrompt

  return htmlRender(component, {
    wrapper: ({children}) => (
      <PlaygroundManagerContext.Provider value={manager}>
        <PlaygroundStateProvider state={playgroundState ?? mockPlaygroundState()}>{children}</PlaygroundStateProvider>
      </PlaygroundManagerContext.Provider>
    ),
  })
}
