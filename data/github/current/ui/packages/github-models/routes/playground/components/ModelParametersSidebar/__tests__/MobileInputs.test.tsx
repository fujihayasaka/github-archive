import {fireEvent, screen, within} from '@testing-library/react'
import {render as htmlRender} from '@github-ui/react-core/test-utils'
import {type ModelState, type PlaygroundState, SidebarSelectionOptions} from '../../../../../types'
import {mockModelState, mockPlaygroundState} from '../../__tests__/mocks'
import {mockModelInputSchema} from '../../../__tests__/mocks'
import {Panel, type PlaygroundManager} from '../../../../../utils/playground-manager'
import {MobileInputs} from '../MobileInputs'
import {mockResizeObserver} from '../../GettingStartedDialog/__tests__/mocks'
import {PlaygroundManagerProvider} from '../../../../../contexts/PlaygroundManagerContext'
import {PlaygroundStateProvider} from '../../../../../contexts/PlaygroundStateContext'

const handleShowSidebarOnMobile = jest.fn().mockName('handleShowSidebarOnMobile')
const doReset = jest.fn().mockName('doReset')
const setParameters = jest.fn().mockName('setParameters')
const setParametersHasChanges = jest.fn().mockName('setParametersHasChanges')
const setSystemPrompt = jest.fn().mockName('setSystemPrompt')
const setIsUseIndexSelected = jest.fn().mockName('setIsUseIndexSelected')

describe('MobileInputs', () => {
  beforeEach(() => {
    // Necessary to avoid a 'TypeError: observer.observe is not a function' error when all MobileInputs tests are run.
    mockResizeObserver()
  })

  afterEach(() => {
    jest.resetAllMocks()
  })

  test('renders model details in dialog', async () => {
    const modelState = mockModelState({parameters: {max_tokens: 2048}})
    const resetLabel = 'Reset this please'

    const {user} = render(
      <MobileInputs
        handleShowSidebarOnMobile={handleShowSidebarOnMobile}
        sidebarTab={SidebarSelectionOptions.DETAILS}
        modelState={modelState}
        doReset={doReset}
        position={Panel.Main}
        resetLabel={resetLabel}
      />,
    )

    const dialog = screen.getByRole('dialog', {name: 'Info'})
    expect(dialog).toBeInTheDocument()
    expect(within(dialog).getByRole('heading', {name: 'Info', level: 1})).toBeInTheDocument()
    const closeButton = within(dialog).getByRole('button', {name: 'Close'})
    expect(closeButton).toBeInTheDocument()
    expect(within(dialog).getByRole('heading', {name: 'About', level: 2})).toBeInTheDocument()
    expect(within(dialog).getByRole('heading', {name: 'Tags', level: 2})).toBeInTheDocument()
    expect(within(dialog).getByRole('heading', {name: 'Languages', level: 2})).toBeInTheDocument()
    expect(within(dialog).getByTestId('model-details')).toBeInTheDocument()
    expect(within(dialog).queryByRole('button', {name: resetLabel})).not.toBeInTheDocument()
    expect(within(dialog).queryByRole('spinbutton', {name: 'max_tokens', hidden: true})).not.toBeInTheDocument()
    expect(doReset).not.toHaveBeenCalled()
    expect(handleShowSidebarOnMobile).not.toHaveBeenCalled()

    await user.click(closeButton)

    expect(handleShowSidebarOnMobile).toHaveBeenCalledTimes(1)
    expect(handleShowSidebarOnMobile).toHaveBeenCalledWith(false)
    expect(setParameters).not.toHaveBeenCalled()
    expect(setParametersHasChanges).not.toHaveBeenCalled()
    expect(setSystemPrompt).not.toHaveBeenCalled()
    expect(setIsUseIndexSelected).not.toHaveBeenCalled()
  })

  test('renders model parameters in dialog when parameters have no changes', async () => {
    const maxTokens = 1234
    const currentSystemPrompt = 'write stuff'
    const modelInputSchema = Object.assign({}, mockModelInputSchema, {capabilities: {systemPrompt: true}})
    const modelState = mockModelState({
      modelInputSchema,
      parametersHasChanges: false,
      parameters: {max_tokens: maxTokens},
      systemPrompt: currentSystemPrompt,
    })
    const resetLabel = 'Reset this please'
    const position = Panel.Main
    const models: ModelState[] = []
    models[position] = modelState
    const playgroundState = mockPlaygroundState({models})

    const {user} = render(
      <MobileInputs
        handleShowSidebarOnMobile={handleShowSidebarOnMobile}
        sidebarTab={SidebarSelectionOptions.PARAMETERS}
        modelState={modelState}
        doReset={doReset}
        position={position}
        resetLabel={resetLabel}
      />,
      {playgroundState},
    )

    const dialog = screen.getByRole('dialog', {name: 'Parameters'})
    expect(dialog).toBeInTheDocument()
    expect(within(dialog).getByRole('heading', {name: 'Parameters', level: 1})).toBeInTheDocument()
    expect(within(dialog).getByRole('button', {name: 'Close'})).toBeInTheDocument()
    expect(within(dialog).queryByTestId('model-details')).not.toBeInTheDocument()
    expect(within(dialog).getByRole('spinbutton', {name: 'max_tokens', hidden: true})).toHaveValue(maxTokens)
    expect(within(dialog).queryByRole('button', {name: resetLabel})).not.toBeInTheDocument()
    const systemPromptInput = within(dialog).getByRole('textbox', {name: 'System prompt'})
    expect(systemPromptInput).toBeInTheDocument()
    expect(doReset).not.toHaveBeenCalled()
    expect(handleShowSidebarOnMobile).not.toHaveBeenCalled()
    expect(setParameters).not.toHaveBeenCalled()
    expect(setParametersHasChanges).not.toHaveBeenCalled()
    expect(setSystemPrompt).not.toHaveBeenCalled()
    expect(setIsUseIndexSelected).not.toHaveBeenCalled()

    const newSystemPrompt = 'foo'
    await user.type(systemPromptInput, newSystemPrompt)

    expect(setSystemPrompt).toHaveBeenCalledTimes(newSystemPrompt.length)
    expect(setSystemPrompt).toHaveBeenCalledWith(position, `${currentSystemPrompt}${newSystemPrompt.charAt(0)}`)
    expect(setParametersHasChanges).toHaveBeenCalledTimes(newSystemPrompt.length)
    expect(setParametersHasChanges).toHaveBeenCalledWith(position, true)
  })

  test('renders model parameters in dialog when parameters have changes', async () => {
    const maxTokens = 1234
    const modelState = mockModelState({parametersHasChanges: true, parameters: {max_tokens: maxTokens}})
    const resetLabel = 'Reset this please'
    const position = Panel.Main
    const models: ModelState[] = []
    models[position] = modelState
    const playgroundState = mockPlaygroundState({models})

    const {user} = render(
      <MobileInputs
        handleShowSidebarOnMobile={handleShowSidebarOnMobile}
        sidebarTab={SidebarSelectionOptions.PARAMETERS}
        modelState={modelState}
        doReset={doReset}
        position={position}
        resetLabel={resetLabel}
      />,
      {playgroundState},
    )

    const dialog = screen.getByRole('dialog', {name: 'Parameters'})
    expect(dialog).toBeInTheDocument()
    expect(within(dialog).getByRole('heading', {name: 'Parameters', level: 1})).toBeInTheDocument()
    expect(within(dialog).getByRole('button', {name: 'Close'})).toBeInTheDocument()
    expect(within(dialog).queryByTestId('model-details')).not.toBeInTheDocument()
    const numberInput = within(dialog).getByRole('spinbutton', {name: 'max_tokens', hidden: true})
    expect(numberInput).toHaveValue(maxTokens)
    const resetButton = within(dialog).getByRole('button', {name: resetLabel})
    expect(resetButton).toBeInTheDocument()
    expect(doReset).not.toHaveBeenCalled()
    expect(handleShowSidebarOnMobile).not.toHaveBeenCalled()

    await user.click(resetButton)

    expect(doReset).toHaveBeenCalledTimes(1)
    expect(setParameters).not.toHaveBeenCalled()
    expect(setParametersHasChanges).not.toHaveBeenCalled()
    expect(setSystemPrompt).not.toHaveBeenCalled()
    expect(setIsUseIndexSelected).not.toHaveBeenCalled()

    const newMaxTokens = maxTokens - 1
    // eslint-disable-next-line testing-library/prefer-user-event
    fireEvent.change(numberInput, {target: {value: newMaxTokens}})

    expect(setParameters).toHaveBeenCalledTimes(1)
    expect(setParameters).toHaveBeenCalledWith(position, {max_tokens: newMaxTokens.toString()})
    expect(setParametersHasChanges).toHaveBeenCalledTimes(1)
    expect(setParametersHasChanges).toHaveBeenCalledWith(position, true)
  })
})

function render(component: JSX.Element, {playgroundState}: {playgroundState?: PlaygroundState} = {}) {
  const manager = {} as PlaygroundManager
  manager.setParameters = setParameters
  manager.setParametersHasChanges = setParametersHasChanges
  manager.setSystemPrompt = setSystemPrompt
  manager.setIsUseIndexSelected = setIsUseIndexSelected

  return htmlRender(
    <PlaygroundStateProvider state={playgroundState ?? mockPlaygroundState()}>
      <PlaygroundManagerProvider manager={manager}>{component}</PlaygroundManagerProvider>
    </PlaygroundStateProvider>,
  )
}
