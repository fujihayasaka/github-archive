import {screen, within} from '@testing-library/react'
import {render as htmlRender, type TestRenderOptions} from '@github-ui/react-core/test-utils'
import {PlaygroundManagerContext, type PlaygroundManager} from '../../../../utils/playground-manager'
import {PlaygroundStateProvider} from '../../../../contexts/PlaygroundStateContext'
import type {PlaygroundState} from '../../../../types'
import {mockPlaygroundState, setupMatchMediaMock} from './mocks'
import {mockGettingStarted} from '../../__tests__/mocks'
import {mockResizeObserver} from '../GettingStartedDialog/__tests__/mocks'
import {PlaygroundCodeSDK} from '../PlaygroundCodeSDK'

const setSelectedSDK = jest.fn().mockName('setSelectedSDK')

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
    const playgroundState = mockPlaygroundState({selectedSDK, selectedLanguage})

    const {container, user} = render(<PlaygroundCodeSDK gettingStarted={gettingStarted} />, {playgroundState})

    const menuToggleButton = within(container).getByRole('button', {name: selectedSDKName})
    expect(menuToggleButton).toBeInTheDocument()

    await user.click(menuToggleButton)

    const menu = screen.getByRole('menu', {name: selectedSDKName})
    expect(menu).toBeInTheDocument()
    expect(within(menu).getByRole('menuitemradio', {name: selectedSDKName})).toHaveAttribute('aria-checked', 'true')
    const otherSDKMenuItem = within(menu).getByRole('menuitemradio', {name: otherSDKName})
    expect(otherSDKMenuItem).toHaveAttribute('aria-checked', 'false')
    expect(setSelectedSDK).not.toHaveBeenCalled()

    await user.click(otherSDKMenuItem)

    expect(setSelectedSDK).toHaveBeenCalledTimes(1)
    expect(setSelectedSDK).toHaveBeenCalledWith(otherSDK)
  })

  test('renders when a language and SDK are selected and there is getting-started content for them', () => {
    const selectedSDK = 'azure-ruby-sdk'
    const selectedLanguage = 'ruby'
    const selectedSDKName = 'Azure Ruby SDK'
    const gettingStarted = Object.assign({}, mockGettingStarted, {
      [selectedLanguage]: {sdks: {[selectedSDK]: {name: selectedSDKName}}},
    })
    const playgroundState = mockPlaygroundState({selectedSDK, selectedLanguage})

    const {container} = render(<PlaygroundCodeSDK gettingStarted={gettingStarted} />, {playgroundState})

    expect(within(container).getByRole('button', {name: selectedSDKName})).toBeInTheDocument()
    expect(setSelectedSDK).not.toHaveBeenCalled()
  })

  test('renders when a language is selected that has getting-started content and there is a default SDK', () => {
    const selectedLanguage = 'piet'
    const defaultSDKName = 'Fancy Piet SDK'
    const gettingStarted = Object.assign({}, mockGettingStarted, {
      [selectedLanguage]: {sdks: {'some-sdk': {name: defaultSDKName}}},
    })
    const playgroundState = mockPlaygroundState({selectedSDK: undefined, selectedLanguage})

    const {container} = render(<PlaygroundCodeSDK gettingStarted={gettingStarted} />, {playgroundState})

    expect(within(container).getByRole('button', {name: defaultSDKName})).toBeInTheDocument()
    expect(setSelectedSDK).not.toHaveBeenCalled()
  })

  test('does not render when selected language has getting-started content but there is no SDK', () => {
    const selectedLanguage = 'elixir'
    const gettingStarted = Object.assign({}, mockGettingStarted, {[selectedLanguage]: {sdks: {}}})
    const playgroundState = mockPlaygroundState({selectedSDK: undefined, selectedLanguage})

    const {container} = render(<PlaygroundCodeSDK gettingStarted={gettingStarted} />, {playgroundState})

    expect(container).toBeEmptyDOMElement()
    expect(setSelectedSDK).not.toHaveBeenCalled()
  })

  test('does not render when there is no getting-started content for the selected language', () => {
    const selectedLanguage = 'lolcode'
    const gettingStarted = Object.assign({}, mockGettingStarted)
    delete gettingStarted[selectedLanguage]
    const playgroundState = mockPlaygroundState({selectedLanguage})

    const {container} = render(<PlaygroundCodeSDK gettingStarted={gettingStarted} />, {playgroundState})

    expect(container).toBeEmptyDOMElement()
    expect(setSelectedSDK).not.toHaveBeenCalled()
  })
})

function render(
  component: JSX.Element,
  {playgroundState, ...opts}: TestRenderOptions & {playgroundState?: PlaygroundState} = {},
) {
  const manager = {} as PlaygroundManager
  manager.setSelectedSDK = setSelectedSDK

  return htmlRender(
    <PlaygroundManagerContext.Provider value={manager}>
      <PlaygroundStateProvider state={playgroundState ?? mockPlaygroundState()}>{component}</PlaygroundStateProvider>
    </PlaygroundManagerContext.Provider>,
    opts,
  )
}
