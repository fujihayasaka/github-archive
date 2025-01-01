import {screen, within} from '@testing-library/react'
import {render as htmlRender} from '@github-ui/react-core/test-utils'
import type {GettingStarted, PlaygroundState} from '../../../../../types'
import GettingStartedDialog from '../GettingStartedDialog'
import {PlaygroundStateProvider} from '../../../../../contexts/PlaygroundStateContext'
import {mockPlaygroundState, mockResizeObserver, mockSDK} from './mocks'

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
      <GettingStartedDialog
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
  })

  test('renders code container with given properties', async () => {
    const gettingStarted: GettingStarted = {
      ts: {
        name: 'TypeScript',
        sdks: {someSdk: mockSDK({name: "I Can't Believe It's This SDK"})},
      },
    }
    const playgroundState = mockPlaygroundState({selectedLanguage: 'ts', selectedSDK: 'someSdk'})

    render(
      <GettingStartedDialog
        onClose={onClose}
        openInCodespaceUrl={openInCodespaceUrl}
        showCodespacesSuggestion
        modelName={modelName}
        gettingStarted={gettingStarted}
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
    expect(within(codeContainerEl).getByRole('button', {name: 'Language: TypeScript'})).toBeInTheDocument()
    expect(
      within(codeContainerEl).getByRole('button', {name: "SDK: I Can't Believe It's This SDK"}),
    ).toBeInTheDocument()
  })
})

function render(component: JSX.Element, state?: PlaygroundState) {
  const stateValue = state ?? mockPlaygroundState()
  return htmlRender(<PlaygroundStateProvider state={stateValue}>{component}</PlaygroundStateProvider>)
}
