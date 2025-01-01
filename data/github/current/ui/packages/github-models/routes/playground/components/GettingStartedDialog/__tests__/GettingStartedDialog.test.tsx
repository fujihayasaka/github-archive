import {useRef} from 'react'
import {screen, within} from '@testing-library/react'
import {render as htmlRender} from '@github-ui/react-core/test-utils'
import type {GettingStarted, PlaygroundState} from '../../../../../types'
import GettingStartedDialog, {type GettingStartedDialogProps} from '../GettingStartedDialog'
import {PlaygroundStateProvider} from '../../../../../contexts/PlaygroundStateContext'
import {mockPlaygroundState, mockResizeObserver, mockSDK} from './mocks'
import {mockLocalStorageUiState} from '../../../__tests__/mocks'

const setUiState = jest.fn().mockName('setUiState')

describe('GettingStartedDialog', () => {
  const onClose = jest.fn()
  const openInCodespaceUrl = '/some/url'
  const modelName = 'I Love This Model'

  beforeEach(() => {
    // Necessary to avoid a 'TypeError: observer.observe is not a function' error when all the GettingStartedDialog
    // tests are run.
    mockResizeObserver()
  })

  afterEach(() => {
    jest.resetAllMocks()
  })

  test('renders and can be closed', async () => {
    const gettingStarted: GettingStarted = {}

    const {user} = render(
      <TestComponent
        onClose={onClose}
        openInCodespaceUrl={openInCodespaceUrl}
        showCodespacesSuggestion
        modelName={modelName}
        gettingStarted={gettingStarted}
      />,
    )

    const dialog = screen.getByRole('dialog', {name: 'Get API key'})
    const closeButton = within(dialog).getByRole('button', {name: 'Close'})
    expect(closeButton).toBeInTheDocument()
    expect(onClose).not.toHaveBeenCalled()
    expect(within(dialog).getByTestId('code-container')).toBeInTheDocument()

    await user.click(closeButton)

    expect(onClose).toHaveBeenCalledTimes(1)
    expect(setUiState).not.toHaveBeenCalled()
  })

  test('renders code container with given properties', async () => {
    const gettingStarted: GettingStarted = {
      ts: {
        name: 'TypeScript',
        sdks: {someSdk: mockSDK({name: "I Can't Believe It's This SDK"})},
      },
    }
    const playgroundState = mockPlaygroundState()
    const uiState = mockLocalStorageUiState

    const {user} = render(
      <TestComponent
        onClose={onClose}
        openInCodespaceUrl={openInCodespaceUrl}
        showCodespacesSuggestion
        modelName={modelName}
        gettingStarted={gettingStarted}
        uiState={uiState}
        setUiState={setUiState}
      />,
      playgroundState,
    )

    const dialog = screen.getByRole('dialog', {name: 'Get API key'})
    expect(within(dialog).getByRole('button', {name: 'Close'})).toBeInTheDocument()
    expect(onClose).not.toHaveBeenCalled()
    const codeContainerEl = within(dialog).getByTestId('code-container')
    expect(codeContainerEl).toBeInTheDocument()
    expect(within(codeContainerEl).getByRole('link', {name: 'Run codespace'})).toHaveAttribute(
      'href',
      openInCodespaceUrl,
    )
    const languageButton = within(codeContainerEl).getByRole('button', {name: 'Language: TypeScript'})
    expect(languageButton).toBeInTheDocument()
    const sdkButton = within(codeContainerEl).getByRole('button', {name: "SDK: I Can't Believe It's This SDK"})
    expect(sdkButton).toBeInTheDocument()

    await user.click(languageButton)

    const langMenu = screen.getByRole('menu', {name: 'Language: TypeScript'})
    expect(langMenu).toBeInTheDocument()
    const langMenuItem = within(langMenu).getByRole('menuitemradio', {name: 'TypeScript'})
    expect(langMenuItem).toBeInTheDocument()
    expect(setUiState).not.toHaveBeenCalled()

    await user.click(langMenuItem)

    expect(setUiState).toHaveBeenCalledTimes(1)
    expect(setUiState).toHaveBeenCalledWith({...uiState, preferredLanguage: 'ts', preferredSdk: 'someSdk'})

    await user.click(sdkButton)

    const sdkMenu = screen.getByRole('menu', {name: "SDK: I Can't Believe It's This SDK"})
    expect(sdkMenu).toBeInTheDocument()
    const sdkMenuItem = within(sdkMenu).getByRole('menuitemradio', {
      name: "I Can't Believe It's This SDK",
    })
    expect(sdkMenuItem).toBeInTheDocument()

    await user.click(sdkMenuItem)

    expect(setUiState).toHaveBeenCalledWith({...uiState, preferredLanguage: 'ts', preferredSdk: 'someSdk'})
  }, 10000)
})

function TestComponent(props: Omit<GettingStartedDialogProps, 'returnFocusRef'>) {
  const ref = useRef(null)
  return (
    <>
      <button ref={ref}>Toggle dialog</button>
      <GettingStartedDialog returnFocusRef={ref} {...props} />
    </>
  )
}

function render(component: JSX.Element, state?: PlaygroundState) {
  const stateValue = state ?? mockPlaygroundState()

  return htmlRender(<PlaygroundStateProvider state={stateValue}>{component}</PlaygroundStateProvider>)
}
