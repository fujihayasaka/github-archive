import {screen, within} from '@testing-library/react'
import {useResponsiveValue} from '@primer/react'
import {render as htmlRender} from '@github-ui/react-core/test-utils'
import {type PlaygroundManager, Panel} from '../../../../utils/playground-manager'
import {PlaygroundManagerProvider} from '../../../../contexts/PlaygroundManagerContext'
import {PlaygroundInputs} from '../PlaygroundInputs'
import {mockModelState, setupMatchMediaMock} from './mocks'
import {SidebarSelectionOptions} from '../../../../types'
import {mockModel, mockModelInputSchema, mockGettingStarted} from '../../__tests__/mocks'
import type {ModelInputSchemaParameter} from '../../../../types'
import {mockResizeObserver} from '../GettingStartedDialog/__tests__/mocks'

jest.mock('@primer/react', () => {
  const original = jest.requireActual('@primer/react')
  return {...original, useResponsiveValue: jest.fn()}
})

const resetParamsAndSystemPrompt = jest.fn().mockName('resetParamsAndSystemPrompt')
const handleSetSidebarTab = jest.fn().mockName('handleSetSidebarTab')
const handleShowSidebar = jest.fn().mockName('handleShowSidebar')
const handleShowSidebarOnMobile = jest.fn().mockName('handleShowSidebarOnMobile')
const mockUseResponsiveValue = jest.mocked(useResponsiveValue)

describe('PlaygroundInputs', () => {
  beforeEach(() => {
    // Avoids a 'TypeError: Cannot read properties of undefined (reading 'addEventListener')' error.
    setupMatchMediaMock()

    // Necessary to avoid a 'TypeError: observer.observe is not a function' error when all the PlaygroundInputs tests
    // are run.
    mockResizeObserver()
  })

  afterEach(() => {
    jest.resetAllMocks()
  })

  test('renders when not on mobile', async () => {
    mockUseResponsiveValue.mockReturnValue(false)
    const paramKey = 'TotalNumberOfTokens'
    const parameter: ModelInputSchemaParameter = {
      key: paramKey,
      type: 'integer',
      payloadPath: 'total_tokens',
      default: 2048,
      min: 100,
      max: 4096,
      required: true,
    }
    const modelInputSchema = Object.assign({}, mockModelInputSchema, {parameters: [parameter]})
    const modelState = mockModelState({modelInputSchema})

    const {container, user} = render(
      <PlaygroundInputs
        model={modelState}
        position={Panel.Main}
        sidebarTab={SidebarSelectionOptions.PARAMETERS}
        showSidebar
        showSidebarOnMobile
        handleSetSidebarTab={handleSetSidebarTab}
        handleShowSidebar={handleShowSidebar}
        handleShowSidebarOnMobile={handleShowSidebarOnMobile}
        repository={undefined}
      />,
    )

    const segmentedControl = within(container).getByRole('list', {hidden: true, name: 'Mode'})
    expect(segmentedControl).toBeInTheDocument()
    const parametersButton = within(segmentedControl).getByRole('button', {hidden: true, name: 'Parameters'})
    expect(parametersButton).toBeInTheDocument()
    expect(parametersButton).toHaveAttribute('aria-current', 'true')
    expect(within(segmentedControl).getByRole('button', {hidden: true, name: 'Details'})).toBeInTheDocument()
    const hideParamsButton = within(container).getByRole('button', {hidden: true, name: 'Hide parameters setting'})
    expect(hideParamsButton).toBeInTheDocument()
    expect(within(container).getByRole('list', {hidden: true, name: 'Mode'})).toBeInTheDocument()
    expect(within(container).getByRole('spinbutton', {hidden: true, name: paramKey})).toBeInTheDocument()
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
    expect(handleShowSidebar).not.toHaveBeenCalled()

    await user.click(hideParamsButton)

    expect(handleShowSidebar).toHaveBeenCalledTimes(1)
    expect(handleShowSidebar).toHaveBeenCalledWith(false)
    expect(resetParamsAndSystemPrompt).not.toHaveBeenCalled()
    expect(handleShowSidebarOnMobile).not.toHaveBeenCalled()
    expect(handleSetSidebarTab).not.toHaveBeenCalled()
  })

  test('renders on mobile when showSidebarOnMobile=true', async () => {
    mockUseResponsiveValue.mockReturnValue(true)
    const modelState = mockModelState()

    const {user} = render(
      <PlaygroundInputs
        model={modelState}
        position={Panel.Main}
        sidebarTab={SidebarSelectionOptions.PARAMETERS}
        showSidebar
        showSidebarOnMobile
        handleSetSidebarTab={handleSetSidebarTab}
        handleShowSidebar={handleShowSidebar}
        handleShowSidebarOnMobile={handleShowSidebarOnMobile}
        repository={undefined}
      />,
    )

    const dialog = screen.getByRole('dialog', {name: 'Parameters'})
    expect(dialog).toBeInTheDocument()
    expect(within(dialog).getByRole('heading', {name: 'Parameters', level: 1})).toBeInTheDocument()
    const closeButton = within(dialog).getByRole('button', {name: 'Close'})
    expect(closeButton).toBeInTheDocument()
    expect(handleShowSidebarOnMobile).not.toHaveBeenCalled()

    await user.click(closeButton)

    expect(handleShowSidebarOnMobile).toHaveBeenCalledTimes(1)
    expect(handleShowSidebarOnMobile).toHaveBeenCalledWith(false)
    expect(resetParamsAndSystemPrompt).not.toHaveBeenCalled()
    expect(handleSetSidebarTab).not.toHaveBeenCalled()
    expect(handleShowSidebar).not.toHaveBeenCalled()
  })

  test('does not render mobile dialog when on mobile if showSidebarOnMobile=false', async () => {
    mockUseResponsiveValue.mockReturnValue(true)
    const modelState = mockModelState()

    const {container, user} = render(
      <PlaygroundInputs
        model={modelState}
        position={Panel.Main}
        sidebarTab={SidebarSelectionOptions.DETAILS}
        showSidebar
        showSidebarOnMobile={false}
        handleSetSidebarTab={handleSetSidebarTab}
        handleShowSidebar={handleShowSidebar}
        handleShowSidebarOnMobile={handleShowSidebarOnMobile}
        repository={undefined}
      />,
    )

    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
    const detailsButton = within(container).getByRole('button', {hidden: true, name: 'Details'})
    expect(detailsButton).toBeInTheDocument()
    expect(detailsButton).toHaveAttribute('aria-current', 'true')
    const parametersButton = within(container).getByRole('button', {hidden: true, name: 'Parameters'})
    expect(parametersButton).toBeInTheDocument()
    expect(handleSetSidebarTab).not.toHaveBeenCalled()

    await user.click(detailsButton)

    expect(handleSetSidebarTab).toHaveBeenCalledTimes(1)
    expect(handleSetSidebarTab).toHaveBeenCalledWith(SidebarSelectionOptions.DETAILS)
    expect(resetParamsAndSystemPrompt).not.toHaveBeenCalled()
    expect(handleShowSidebar).not.toHaveBeenCalled()
    expect(handleShowSidebarOnMobile).not.toHaveBeenCalled()
  })

  test('allows resetting parameters to defaults', async () => {
    mockUseResponsiveValue.mockReturnValue(false)
    const catalogData = mockModel
    const modelInputSchema = mockModelInputSchema
    const gettingStarted = mockGettingStarted
    const modelState = mockModelState({parametersHasChanges: true, catalogData, modelInputSchema, gettingStarted})

    const {container, user} = render(
      <PlaygroundInputs
        model={modelState}
        position={Panel.Main}
        sidebarTab={SidebarSelectionOptions.PARAMETERS}
        showSidebar
        showSidebarOnMobile
        handleSetSidebarTab={handleSetSidebarTab}
        handleShowSidebar={handleShowSidebar}
        handleShowSidebarOnMobile={handleShowSidebarOnMobile}
        repository={undefined}
      />,
    )

    const resetButton = within(container).getByRole('button', {hidden: true, name: 'Reset to default inputs'})
    expect(resetButton).toBeInTheDocument()
    expect(resetParamsAndSystemPrompt).not.toHaveBeenCalled()

    await user.click(resetButton)

    expect(resetParamsAndSystemPrompt).toHaveBeenCalledTimes(1)
    expect(resetParamsAndSystemPrompt).toHaveBeenCalledWith(Panel.Main, {catalogData, modelInputSchema, gettingStarted})
    expect(handleShowSidebar).not.toHaveBeenCalled()
    expect(handleShowSidebarOnMobile).not.toHaveBeenCalled()
    expect(handleSetSidebarTab).not.toHaveBeenCalled()
  })

  test('renders the create prompt.yml file button when on repo playground', () => {
    mockUseResponsiveValue.mockReturnValue(false)
    const repository = {
      name: 'repo-name',
      ownerLogin: 'owner-login',
    }

    const {container} = render(
      <PlaygroundInputs
        model={mockModelState()}
        position={Panel.Main}
        sidebarTab={SidebarSelectionOptions.PARAMETERS}
        showSidebar
        showSidebarOnMobile
        handleSetSidebarTab={handleSetSidebarTab}
        handleShowSidebar={handleShowSidebar}
        handleShowSidebarOnMobile={handleShowSidebarOnMobile}
        repository={repository}
      />,
    )

    const button = within(container).getByRole('button', {name: 'Create prompt.yml file'})
    expect(button).toBeInTheDocument()
  })

  test('does not render the create prompt.yml file button when on marketplace playground', () => {
    mockUseResponsiveValue.mockReturnValue(false)

    const {container} = render(
      <PlaygroundInputs
        model={mockModelState()}
        position={Panel.Main}
        sidebarTab={SidebarSelectionOptions.PARAMETERS}
        showSidebar
        showSidebarOnMobile
        handleSetSidebarTab={handleSetSidebarTab}
        handleShowSidebar={handleShowSidebar}
        handleShowSidebarOnMobile={handleShowSidebarOnMobile}
        repository={undefined}
      />,
    )

    expect(within(container).queryByRole('button', {name: 'Create prompt.yml file'})).not.toBeInTheDocument()
  })
})

function render(component: JSX.Element) {
  const manager = {} as PlaygroundManager
  manager.resetParamsAndSystemPrompt = resetParamsAndSystemPrompt
  return htmlRender(<PlaygroundManagerProvider manager={manager}>{component}</PlaygroundManagerProvider>)
}
