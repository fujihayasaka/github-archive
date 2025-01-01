import {screen, within} from '@testing-library/react'
import {render as htmlRender, type TestRenderOptions} from '@github-ui/react-core/test-utils'
import {PlaygroundStateProvider} from '../../../../contexts/PlaygroundStateContext'
import type {PlaygroundState} from '../../../../types'
import {mockPlaygroundState, setupMatchMediaMock} from './mocks'
import {mockGettingStarted, mockLocalStorageUiState} from '../../__tests__/mocks'
import {mockResizeObserver} from '../GettingStartedDialog/__tests__/mocks'
import {PlaygroundCodeSDK} from '../PlaygroundCodeSDK'

const setSelectedSDK = jest.fn().mockName('setSelectedSDK')
const mockHandleSelectedSDK = jest.fn().mockName('handleSelectedSDK')

describe('PlaygroundCodeSDK', () => {
  beforeEach(() => {
    // Avoids "TypeError: Cannot read properties of undefined (reading 'addEventListener')" error when all tests run.
    setupMatchMediaMock()

    // Avoids 'TypeError: observer.observe is not a function' error when all tests are run.
    mockResizeObserver()
  })

  afterEach(() => {
    jest.resetAllMocks()
  })

  test('renders available SDKs in menu', async () => {
    const selectedSDK = 'azure-ruby-sdk'
    const selectedLanguage = 'ruby'
    const selectedSDKName = 'Azure Ruby SDK'
    const otherSDK = 'other-sdk'
    const otherSDKName = 'Other SDK'
    const gettingStarted = Object.assign({}, mockGettingStarted, {
      [selectedLanguage]: {sdks: {[selectedSDK]: {name: selectedSDKName}, [otherSDK]: {name: otherSDKName}}},
    })
    const playgroundState = mockPlaygroundState({})

    const uiState = {...mockLocalStorageUiState, preferredLanguage: selectedLanguage, preferredSdk: selectedSDK}
    const {container, user} = render(
      <PlaygroundCodeSDK gettingStarted={gettingStarted} uiState={uiState} handleSelectSDK={mockHandleSelectedSDK} />,
      {playgroundState},
    )

    const menuToggleButton = within(container).getByRole('button', {name: selectedSDKName})
    expect(menuToggleButton).toBeInTheDocument()

    await user.click(menuToggleButton)

    const menu = screen.getByRole('menu', {name: selectedSDKName})
    expect(menu).toBeInTheDocument()
    expect(within(menu).getByRole('menuitemradio', {name: selectedSDKName})).toHaveAttribute('aria-checked', 'true')
    const otherSDKMenuItem = within(menu).getByRole('menuitemradio', {name: otherSDKName})
    expect(otherSDKMenuItem).toHaveAttribute('aria-checked', 'false')
    expect(mockHandleSelectedSDK).not.toHaveBeenCalled()

    await user.click(otherSDKMenuItem)

    expect(mockHandleSelectedSDK).toHaveBeenCalledTimes(1)
    expect(mockHandleSelectedSDK).toHaveBeenCalledWith(otherSDK)
  })

  test('renders when a language and SDK are selected and there is getting-started content for them', () => {
    const selectedSDK = 'azure-ruby-sdk'
    const selectedLanguage = 'ruby'
    const selectedSDKName = 'Azure Ruby SDK'
    const gettingStarted = Object.assign({}, mockGettingStarted, {
      [selectedLanguage]: {sdks: {[selectedSDK]: {name: selectedSDKName}}},
    })
    const playgroundState = mockPlaygroundState()

    const uiState = {...mockLocalStorageUiState, preferredLanguage: selectedLanguage, preferredSdk: selectedSDK}

    const {container} = render(
      <PlaygroundCodeSDK gettingStarted={gettingStarted} uiState={uiState} handleSelectSDK={mockHandleSelectedSDK} />,
      {playgroundState},
    )

    expect(within(container).getByRole('button', {name: selectedSDKName})).toBeInTheDocument()
    expect(mockHandleSelectedSDK).not.toHaveBeenCalled()
  })

  test('does not render when selected language has getting-started content but there is no SDK', () => {
    const selectedLanguage = 'elixir'
    const gettingStarted = Object.assign({}, mockGettingStarted, {[selectedLanguage]: {sdks: {}}})
    const playgroundState = mockPlaygroundState()

    const uiState = {...mockLocalStorageUiState, preferredLanguage: selectedLanguage, preferredSdk: ''}

    const {container} = render(
      <PlaygroundCodeSDK gettingStarted={gettingStarted} uiState={uiState} handleSelectSDK={mockHandleSelectedSDK} />,
      {playgroundState},
    )

    expect(container).toBeEmptyDOMElement()
    expect(setSelectedSDK).not.toHaveBeenCalled()
  })

  test('does not render when there is no getting-started content for the selected language', () => {
    const selectedLanguage = 'lolcode'
    const gettingStarted = Object.assign({}, mockGettingStarted)
    delete gettingStarted[selectedLanguage]
    const playgroundState = mockPlaygroundState()

    const uiState = {...mockLocalStorageUiState, preferredLanguage: selectedLanguage, preferredSdk: 'lolcode'}

    const {container} = render(
      <PlaygroundCodeSDK gettingStarted={gettingStarted} uiState={uiState} handleSelectSDK={mockHandleSelectedSDK} />,
      {playgroundState},
    )

    expect(container).toBeEmptyDOMElement()
    expect(setSelectedSDK).not.toHaveBeenCalled()
  })
})

function render(
  component: JSX.Element,
  {playgroundState, ...opts}: TestRenderOptions & {playgroundState?: PlaygroundState} = {},
) {
  return htmlRender(
    <PlaygroundStateProvider state={playgroundState ?? mockPlaygroundState()}>{component}</PlaygroundStateProvider>,
    opts,
  )
}
