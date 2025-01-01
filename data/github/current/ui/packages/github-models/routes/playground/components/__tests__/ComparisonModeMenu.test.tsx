import {render as htmlRender} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import {ComparisonModeMenu} from '../ComparisonModeMenu'
import {Panel, type PlaygroundManager} from '../../../../utils/playground-manager'
import {PlaygroundManagerProvider} from '../../../../contexts/PlaygroundManagerContext'
import {PlaygroundStateProvider} from '../../../../contexts/PlaygroundStateContext'
import {mockModelState, mockPlaygroundState} from './mocks'
import {mockModel} from '../../__tests__/mocks'
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

    const {user} = render(<ComparisonModeMenu modelState={modelState} position={Panel.Main} />, playgroundState)

    const syncCheckbox = screen.getByRole('checkbox', {name: 'Sync chat input and parameters'})
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

    const {user} = render(<ComparisonModeMenu modelState={modelState} position={Panel.Main} />, playgroundState)

    const syncCheckbox = screen.getByRole('checkbox', {name: 'Sync chat input and parameters'})
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

  test('renders the Create prompt.yml file button when on repo playground', () => {
    const modelState = mockModelState()
    const otherModel = Object.assign({}, mockModel, {id: `${mockModel.id}-other`, name: `${mockModel.name}-other`})
    const otherModelState = mockModelState({catalogData: otherModel})
    const models = [modelState, otherModelState]
    const playgroundState = mockPlaygroundState({syncInputs: false, models})

    const repository = {
      name: 'test-repo',
      ownerLogin: 'test-owner',
    }

    render(
      <ComparisonModeMenu modelState={modelState} position={Panel.Main} repository={repository} />,
      playgroundState,
    )

    expect(screen.getByRole('button', {name: 'Create prompt.yml file'})).toBeInTheDocument()
  })

  test('does not render the Create prompt.yml file button when on marketplace playground', () => {
    const modelState = mockModelState()
    const otherModel = Object.assign({}, mockModel, {id: `${mockModel.id}-other`, name: `${mockModel.name}-other`})
    const otherModelState = mockModelState({catalogData: otherModel})
    const models = [modelState, otherModelState]
    const playgroundState = mockPlaygroundState({syncInputs: false, models})

    render(<ComparisonModeMenu modelState={modelState} position={Panel.Main} />, playgroundState)

    expect(screen.queryByRole('button', {name: 'Create prompt.yml file'})).not.toBeInTheDocument()
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
      <PlaygroundManagerProvider manager={manager}>
        <PlaygroundStateProvider state={playgroundState ?? mockPlaygroundState()}>{children}</PlaygroundStateProvider>
      </PlaygroundManagerProvider>
    ),
  })
}
