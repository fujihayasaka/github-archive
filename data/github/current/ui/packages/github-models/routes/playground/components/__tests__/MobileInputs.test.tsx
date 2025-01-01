import {screen, within} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {SidebarSelectionOptions} from '../../../../types'
import {mockModelState} from './mocks'
import {Panel} from '../../../../utils/playground-manager'
import {MobileInputs} from '../MobileInputs'
import {mockResizeObserver} from '../GettingStartedDialog/__tests__/mocks'

const handleShowSidebarOnMobile = jest.fn().mockName('handleShowSidebarOnMobile')
const doReset = jest.fn().mockName('doReset')

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
  })

  test('renders model parameters in dialog when parameters have no changes', () => {
    const maxTokens = 1234
    const modelState = mockModelState({parametersHasChanges: false, parameters: {max_tokens: maxTokens}})
    const resetLabel = 'Reset this please'

    render(
      <MobileInputs
        handleShowSidebarOnMobile={handleShowSidebarOnMobile}
        sidebarTab={SidebarSelectionOptions.PARAMETERS}
        modelState={modelState}
        doReset={doReset}
        position={Panel.Main}
        resetLabel={resetLabel}
      />,
    )

    const dialog = screen.getByRole('dialog', {name: 'Parameters'})
    expect(dialog).toBeInTheDocument()
    expect(within(dialog).getByRole('heading', {name: 'Parameters', level: 1})).toBeInTheDocument()
    expect(within(dialog).getByRole('button', {name: 'Close'})).toBeInTheDocument()
    expect(within(dialog).queryByTestId('model-details')).not.toBeInTheDocument()
    expect(within(dialog).getByRole('spinbutton', {name: 'max_tokens', hidden: true})).toHaveValue(maxTokens)
    expect(within(dialog).queryByRole('button', {name: resetLabel})).not.toBeInTheDocument()
    expect(doReset).not.toHaveBeenCalled()
    expect(handleShowSidebarOnMobile).not.toHaveBeenCalled()
  })

  test('renders model parameters in dialog when parameters have changes', async () => {
    const maxTokens = 1234
    const modelState = mockModelState({parametersHasChanges: true, parameters: {max_tokens: maxTokens}})
    const resetLabel = 'Reset this please'

    const {user} = render(
      <MobileInputs
        handleShowSidebarOnMobile={handleShowSidebarOnMobile}
        sidebarTab={SidebarSelectionOptions.PARAMETERS}
        modelState={modelState}
        doReset={doReset}
        position={Panel.Main}
        resetLabel={resetLabel}
      />,
    )

    const dialog = screen.getByRole('dialog', {name: 'Parameters'})
    expect(dialog).toBeInTheDocument()
    expect(within(dialog).getByRole('heading', {name: 'Parameters', level: 1})).toBeInTheDocument()
    expect(within(dialog).getByRole('button', {name: 'Close'})).toBeInTheDocument()
    expect(within(dialog).queryByTestId('model-details')).not.toBeInTheDocument()
    expect(within(dialog).getByRole('spinbutton', {name: 'max_tokens', hidden: true})).toHaveValue(maxTokens)
    const resetButton = within(dialog).getByRole('button', {name: resetLabel})
    expect(resetButton).toBeInTheDocument()
    expect(doReset).not.toHaveBeenCalled()
    expect(handleShowSidebarOnMobile).not.toHaveBeenCalled()

    await user.click(resetButton)

    expect(doReset).toHaveBeenCalledTimes(1)
  })
})
