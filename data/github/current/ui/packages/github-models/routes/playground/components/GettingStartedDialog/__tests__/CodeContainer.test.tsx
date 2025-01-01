import {screen, within} from '@testing-library/react'
import type {SafeHTMLString} from '@github-ui/safe-html'
import {render as htmlRender} from '@github-ui/react-core/test-utils'
import {CodeContainer} from '../CodeContainer'
import {mockGettingStarted, mockLocalStorageUiState} from '../../../__tests__/mocks'
import type {GettingStarted} from '../../../../../types'
import type {PlaygroundManager} from '../../../../../utils/playground-manager'
import {PlaygroundManagerProvider} from '../../../../../contexts/PlaygroundManagerContext'
import {PlaygroundStateProvider} from '../../../../../contexts/PlaygroundStateContext'
import {mockPlaygroundState, mockSDK} from './mocks'
import {getLocalStorageUiState, UI_STATE_KEY} from '../../../../../utils/playground-local-storage'
import safeStorage from '@github-ui/safe-storage'

const selectedLanguage = 'intercal'
const selectedSDK = 'some-sdk'

const setUiState = jest.fn().mockName('setUiState')

describe('CodeContainer', () => {
  const safeLocalStorage = safeStorage('localStorage')
  afterEach(() => {
    safeLocalStorage.removeItem(UI_STATE_KEY)
    jest.clearAllMocks()
  })

  const openInCodespaceUrl = '/some/codespaces/url'
  const modelName = 'SomeNiceModel'
  const languageName = 'Intercal'
  const sdkName = 'Some SDK'

  test('renders for language and SDK with documentation', () => {
    const docsContent = 'Here is the documentation.'
    const gettingStarted: GettingStarted = {
      [selectedLanguage]: {
        name: languageName,
        sdks: {[selectedSDK]: mockSDK({name: sdkName, content: docsContent})},
      },
    }

    const {container} = render(
      <CodeContainer
        openInCodespaceUrl={openInCodespaceUrl}
        showCodespacesSuggestion
        gettingStarted={gettingStarted}
        modelName={modelName}
      />,
    )

    const codeContainerEl = within(container).getByTestId('code-container')
    expect(within(codeContainerEl).getByRole('button', {name: `Language: ${languageName}`})).toBeInTheDocument()
    expect(within(codeContainerEl).getByRole('button', {name: `SDK: ${sdkName}`})).toBeInTheDocument()
    expect(within(codeContainerEl).getByRole('button', {name: 'Share feedback'})).toBeInTheDocument()
    expect(within(codeContainerEl).getByRole('link', {name: 'Run codespace'})).toHaveAttribute(
      'href',
      openInCodespaceUrl,
    )
    expect(within(codeContainerEl).getByRole('link', {name: 'Product Terms'})).toBeInTheDocument()
    expect(within(codeContainerEl).getByRole('link', {name: 'Privacy Statement'})).toBeInTheDocument()
    expect(
      within(codeContainerEl).queryByRole('heading', {
        level: 2,
        name: 'Documentation for this language and SDK combination is unavailable',
      }),
    ).not.toBeInTheDocument()
    expect(
      within(codeContainerEl).getByRole('heading', {name: 'Or set it up yourself...', level: 2}),
    ).toBeInTheDocument()
    expect(within(codeContainerEl).getByText(docsContent)).toBeInTheDocument()
  })

  test('renders for language and SDK without documentation', () => {
    const gettingStarted: GettingStarted = {
      [selectedLanguage]: {
        name: languageName,
        sdks: {[selectedSDK]: mockSDK({name: sdkName, content: ''})},
      },
    }

    const {container} = render(
      <CodeContainer
        openInCodespaceUrl={openInCodespaceUrl}
        showCodespacesSuggestion
        gettingStarted={gettingStarted}
        modelName={modelName}
      />,
    )

    const codeContainerEl = within(container).getByTestId('code-container')
    expect(within(codeContainerEl).getByRole('button', {name: `Language: ${languageName}`})).toBeInTheDocument()
    expect(within(codeContainerEl).getByRole('button', {name: `SDK: ${sdkName}`})).toBeInTheDocument()
    expect(within(codeContainerEl).getByRole('button', {name: 'Share feedback'})).toBeInTheDocument()
    expect(within(codeContainerEl).getByRole('link', {name: 'Run codespace'})).toHaveAttribute(
      'href',
      openInCodespaceUrl,
    )
    expect(within(codeContainerEl).getByRole('link', {name: 'Product Terms'})).toBeInTheDocument()
    expect(within(codeContainerEl).getByRole('link', {name: 'Privacy Statement'})).toBeInTheDocument()
    expect(
      within(codeContainerEl).getByRole('heading', {
        level: 2,
        name: 'Documentation for this language and SDK combination is unavailable',
      }),
    ).toBeInTheDocument()
    expect(
      within(codeContainerEl).queryByRole('heading', {name: 'Or set it up yourself...', level: 2}),
    ).not.toBeInTheDocument()
  })

  test('renders without Codespace suggestion when specified', () => {
    const {container} = render(
      <CodeContainer
        openInCodespaceUrl={openInCodespaceUrl}
        showCodespacesSuggestion={false}
        gettingStarted={mockGettingStarted}
        modelName={modelName}
      />,
    )

    const codeContainerEl = within(container).getByTestId('code-container')
    expect(codeContainerEl).toBeInTheDocument()
    expect(within(codeContainerEl).queryByRole('link', {name: 'Run codespace'})).not.toBeInTheDocument()
  })

  test('renders error when selected SDK cannot be found', () => {
    const gettingStarted: GettingStarted = {}

    const {container} = render(
      <CodeContainer
        openInCodespaceUrl={openInCodespaceUrl}
        showCodespacesSuggestion
        gettingStarted={gettingStarted}
        modelName={modelName}
      />,
    )

    const codeContainerEl = within(container).getByTestId('code-container')
    expect(codeContainerEl).toBeInTheDocument()
    expect(codeContainerEl).toHaveTextContent('Error')
    expect(within(codeContainerEl).queryByRole('link', {name: 'Product Terms'})).not.toBeInTheDocument()
    expect(within(codeContainerEl).queryByRole('link', {name: 'Privacy Statement'})).not.toBeInTheDocument()
    expect(within(codeContainerEl).queryByRole('link', {name: 'Run codespace'})).not.toBeInTheDocument()
    expect(
      within(codeContainerEl).queryByRole('heading', {name: 'Or set it up yourself...', level: 2}),
    ).not.toBeInTheDocument()
    expect(
      within(codeContainerEl).queryByRole('heading', {
        level: 2,
        name: 'Documentation for this language and SDK combination is unavailable',
      }),
    ).not.toBeInTheDocument()
  })

  test('renders table of contents', () => {
    const tocHeadingText1 = 'Some Heading'
    const tocHeadingText2 = 'Most glorious heading'
    const tocLowerLevelHeadingText = 'A less important heading'
    const gettingStarted: GettingStarted = {
      [selectedLanguage]: {
        name: languageName,
        sdks: {
          [selectedSDK]: mockSDK({
            tocHeadings: [
              {
                level: 2,
                anchor: 'some-id',
                text: tocHeadingText1 as SafeHTMLString,
                htmlText: `<marquee>${tocHeadingText1}</marquee>` as SafeHTMLString,
              },
              {
                level: 3,
                anchor: 'will-be-skipped-bc-not-level-2',
                text: tocLowerLevelHeadingText as SafeHTMLString,
                htmlText: `<strong>${tocLowerLevelHeadingText}</strong>` as SafeHTMLString,
              },
              {
                level: 2,
                anchor: 'other-id',
                text: tocHeadingText2 as SafeHTMLString,
                htmlText: '<em>Most</em> glorious heading' as SafeHTMLString,
              },
            ],
          }),
        },
      },
    }

    const {container} = render(
      <CodeContainer
        openInCodespaceUrl={openInCodespaceUrl}
        showCodespacesSuggestion
        gettingStarted={gettingStarted}
        modelName={modelName}
      />,
    )

    const codeContainerEl = within(container).getByTestId('code-container')
    const chapterList = within(codeContainerEl).getByRole('list', {name: 'Chapters'})
    expect(chapterList).toBeInTheDocument()
    expect(within(chapterList).getByRole('listitem', {name: tocHeadingText1})).toBeInTheDocument()
    expect(within(chapterList).getByRole('listitem', {name: tocHeadingText2})).toBeInTheDocument()
    expect(within(codeContainerEl).queryByText(tocLowerLevelHeadingText)).not.toBeInTheDocument()
  })

  test('displays preferred language and first available sdk when preferred language is set in the local storage', () => {
    const preferredLanguage = `preferred-${selectedLanguage}`
    const preferredLanguageName = `preferred-${languageName}`

    const mockUiState = {...mockLocalStorageUiState, preferredLanguage}
    safeLocalStorage.setItem(UI_STATE_KEY, JSON.stringify(mockUiState))

    const gettingStarted: GettingStarted = {
      [selectedLanguage]: {
        name: selectedLanguage,
        sdks: {[selectedSDK]: mockSDK({name: sdkName})},
      },
      [preferredLanguage]: {
        name: preferredLanguageName,
        sdks: {[selectedSDK]: mockSDK({name: sdkName})},
      },
    }

    const {container} = render(
      <CodeContainer
        openInCodespaceUrl={openInCodespaceUrl}
        showCodespacesSuggestion
        gettingStarted={gettingStarted}
        modelName={modelName}
      />,
    )

    const codeContainerEl = within(container).getByTestId('code-container')
    const languageButton = within(codeContainerEl).getByRole('button', {name: `Language: ${preferredLanguageName}`})
    expect(languageButton).toBeInTheDocument()
    const sdkButton = within(codeContainerEl).getByRole('button', {name: `SDK: ${sdkName}`})
    expect(sdkButton).toBeInTheDocument()
  })

  test('displays preferred language and sdk when they are set in the local storage', () => {
    const preferredLanguage = `preferred-${selectedLanguage}`
    const preferredLanguageName = `preferred-${languageName}`
    const preferredSdk = `preferred-${selectedSDK}`
    const preferredSdkName = `preferred-${sdkName}`

    const mockUiState = {...mockLocalStorageUiState, preferredLanguage, preferredSdk}
    safeLocalStorage.setItem(UI_STATE_KEY, JSON.stringify(mockUiState))

    const gettingStarted: GettingStarted = {
      [selectedLanguage]: {
        name: selectedLanguage,
        sdks: {[selectedSDK]: mockSDK({name: sdkName})},
      },
      [preferredLanguage]: {
        name: preferredLanguageName,
        sdks: {[selectedSDK]: mockSDK({name: sdkName}), [preferredSdk]: mockSDK({name: preferredSdkName})},
      },
    }

    const {container} = render(
      <CodeContainer
        openInCodespaceUrl={openInCodespaceUrl}
        showCodespacesSuggestion
        gettingStarted={gettingStarted}
        modelName={modelName}
      />,
    )

    const codeContainerEl = within(container).getByTestId('code-container')
    const languageButton = within(codeContainerEl).getByRole('button', {name: `Language: ${preferredLanguageName}`})
    expect(languageButton).toBeInTheDocument()
    const sdkButton = within(codeContainerEl).getByRole('button', {name: `SDK: ${preferredSdkName}`})
    expect(sdkButton).toBeInTheDocument()
  })

  test('displays first available language and first available sdk when preferred language and sdk are unavailable', () => {
    const preferredLanguage = `preferred-${selectedLanguage}`
    const preferredSdk = `preferred-${selectedSDK}`

    const mockUiState = {...mockLocalStorageUiState, preferredLanguage, preferredSdk}
    safeLocalStorage.setItem(UI_STATE_KEY, JSON.stringify(mockUiState))

    const gettingStarted: GettingStarted = {
      [selectedLanguage]: {
        name: languageName,
        sdks: {[selectedSDK]: mockSDK({name: sdkName})},
      },
    }

    const {container} = render(
      <CodeContainer
        openInCodespaceUrl={openInCodespaceUrl}
        showCodespacesSuggestion
        gettingStarted={gettingStarted}
        modelName={modelName}
      />,
    )

    const codeContainerEl = within(container).getByTestId('code-container')
    const languageButton = within(codeContainerEl).getByRole('button', {name: `Language: ${languageName}`})
    expect(languageButton).toBeInTheDocument()
    const sdkButton = within(codeContainerEl).getByRole('button', {name: `SDK: ${sdkName}`})
    expect(sdkButton).toBeInTheDocument()
  })

  test('displays first available language and selected sdk when preferred language is unavailable', () => {
    const preferredLanguage = `preferred-${selectedLanguage}`
    const preferredSdk = `preferred-${selectedSDK}`
    const preferredSdkName = `preferred-${sdkName}`

    const mockUiState = {...mockLocalStorageUiState, preferredLanguage, preferredSdk}
    safeLocalStorage.setItem(UI_STATE_KEY, JSON.stringify(mockUiState))

    const gettingStarted: GettingStarted = {
      [selectedLanguage]: {
        name: languageName,
        sdks: {[selectedSDK]: mockSDK({name: sdkName}), [preferredSdk]: mockSDK({name: preferredSdkName})},
      },
    }

    const {container} = render(
      <CodeContainer
        openInCodespaceUrl={openInCodespaceUrl}
        showCodespacesSuggestion
        gettingStarted={gettingStarted}
        modelName={modelName}
      />,
    )

    const codeContainerEl = within(container).getByTestId('code-container')
    const languageButton = within(codeContainerEl).getByRole('button', {name: `Language: ${languageName}`})
    expect(languageButton).toBeInTheDocument()
    const sdkButton = within(codeContainerEl).getByRole('button', {name: `SDK: ${preferredSdkName}`})
    expect(sdkButton).toBeInTheDocument()
  })

  // Playground view specific - selected language and sdk are passed as props
  test('displays passed language and sdk props', () => {
    const preferredLanguage = `preferred-${selectedLanguage}`
    const preferredLanguageName = `preferred-${languageName}`
    const preferredSdk = `preferred-${selectedSDK}`
    const preferredSdkName = `preferred-${sdkName}`

    const mockUiState = {...mockLocalStorageUiState, preferredLanguage, preferredSdk}
    safeLocalStorage.setItem(UI_STATE_KEY, JSON.stringify(mockUiState))

    const gettingStarted: GettingStarted = {
      [selectedLanguage]: {
        name: languageName,
        sdks: {[selectedSDK]: mockSDK({name: sdkName}), [preferredSdk]: mockSDK({name: preferredSdkName})},
      },
      [preferredLanguage]: {
        name: preferredLanguageName,
        sdks: {[selectedSDK]: mockSDK({name: sdkName}), [preferredSdk]: mockSDK({name: preferredSdkName})},
      },
    }

    const {container} = render(
      <CodeContainer
        openInCodespaceUrl={openInCodespaceUrl}
        showCodespacesSuggestion
        gettingStarted={gettingStarted}
        modelName={modelName}
        uiState={{...mockLocalStorageUiState, preferredLanguage: selectedLanguage, preferredSdk: selectedSDK}}
      />,
    )

    const codeContainerEl = within(container).getByTestId('code-container')
    const languageButton = within(codeContainerEl).getByRole('button', {name: `Language: ${languageName}`})
    expect(languageButton).toBeInTheDocument()
    const sdkButton = within(codeContainerEl).getByRole('button', {name: `SDK: ${sdkName}`})
    expect(sdkButton).toBeInTheDocument()
  })

  test('renders error when there is no sdk', () => {
    const gettingStarted = {...mockGettingStarted}

    const {container} = render(
      <CodeContainer
        openInCodespaceUrl={openInCodespaceUrl}
        showCodespacesSuggestion
        gettingStarted={gettingStarted}
        modelName={modelName}
        uiState={{...mockLocalStorageUiState, preferredLanguage: 'csharp', preferredSdk: selectedSDK}}
      />,
    )

    const codeContainerEl = within(container).getByTestId('code-container')
    expect(within(codeContainerEl).getByText('Error')).toBeInTheDocument()
  })

  test('renders error when there is no available language', () => {
    const gettingStarted = {}

    const {container} = render(
      <CodeContainer
        openInCodespaceUrl={openInCodespaceUrl}
        showCodespacesSuggestion
        gettingStarted={gettingStarted}
        modelName={modelName}
      />,
    )

    const codeContainerEl = within(container).getByTestId('code-container')
    expect(within(codeContainerEl).getByText('Error')).toBeInTheDocument()
  })

  test('allows changing selected SDK and updates the values in the local storage', async () => {
    const otherSDK = `${selectedSDK}-123`
    const otherSDKName = `${sdkName} But Better`
    const gettingStarted: GettingStarted = {
      [selectedLanguage]: {
        name: languageName,
        sdks: {[selectedSDK]: mockSDK({name: sdkName}), [otherSDK]: mockSDK({name: otherSDKName})},
      },
    }

    const {container, user} = render(
      <CodeContainer
        openInCodespaceUrl={openInCodespaceUrl}
        showCodespacesSuggestion
        gettingStarted={gettingStarted}
        modelName={modelName}
        uiState={{...mockLocalStorageUiState, preferredLanguage: selectedLanguage, preferredSdk: sdkName}}
        setUiState={setUiState}
      />,
    )

    const codeContainerEl = within(container).getByTestId('code-container')
    const sdkButton = within(codeContainerEl).getByRole('button', {name: `SDK: ${sdkName}`})
    expect(sdkButton).toBeInTheDocument()
    expect(screen.queryByRole('menuitemradio', {name: otherSDKName})).not.toBeInTheDocument()

    await user.click(sdkButton)

    const sdkMenu = screen.getByRole('menu', {name: `SDK: ${sdkName}`})
    expect(sdkMenu).toBeInTheDocument()
    const otherSDKMenuItem = within(sdkMenu).getByRole('menuitemradio', {name: otherSDKName})
    expect(otherSDKMenuItem).toBeInTheDocument()
    expect(otherSDKMenuItem).toHaveAttribute('aria-checked', 'false')
    expect(within(sdkMenu).getByRole('menuitemradio', {name: sdkName})).toHaveAttribute('aria-checked', 'true')

    await user.click(otherSDKMenuItem)

    expect(setUiState).toHaveBeenCalledTimes(1)
    expect(within(codeContainerEl).queryByRole('button', {name: `SDK: ${sdkName}`})).not.toBeInTheDocument()
    expect(within(codeContainerEl).getByRole('button', {name: `SDK: ${otherSDKName}`})).toBeInTheDocument()

    const uiState = getLocalStorageUiState()
    expect(uiState.preferredSdk).toEqual(otherSDK)
  })

  test('allows changing selected language and updates the values in the local storage', async () => {
    const otherLanguage = `${selectedLanguage}-v2`
    const otherLanguageName = `${languageName} Version 2.0`
    const gettingStarted: GettingStarted = {
      [selectedLanguage]: {
        name: languageName,
        sdks: {[selectedSDK]: mockSDK({name: sdkName})},
      },
      [otherLanguage]: {
        name: otherLanguageName,
        sdks: {[selectedSDK]: mockSDK({name: sdkName})},
      },
    }

    const {container, user} = render(
      <CodeContainer
        openInCodespaceUrl={openInCodespaceUrl}
        showCodespacesSuggestion
        gettingStarted={gettingStarted}
        modelName={modelName}
        uiState={{...mockLocalStorageUiState, preferredLanguage: selectedLanguage, preferredSdk: selectedSDK}}
        setUiState={setUiState}
      />,
    )

    const codeContainerEl = within(container).getByTestId('code-container')
    const languageButton = within(codeContainerEl).getByRole('button', {name: `Language: ${languageName}`})
    expect(languageButton).toBeInTheDocument()
    expect(screen.queryByRole('menuitemradio', {name: otherLanguageName})).not.toBeInTheDocument()

    await user.click(languageButton)

    const languageMenu = screen.getByRole('menu', {name: `Language: ${languageName}`})
    expect(languageMenu).toBeInTheDocument()
    const otherLanguageMenuItem = within(languageMenu).getByRole('menuitemradio', {name: otherLanguageName})
    expect(otherLanguageMenuItem).toBeInTheDocument()
    expect(otherLanguageMenuItem).toHaveAttribute('aria-checked', 'false')
    expect(within(languageMenu).getByRole('menuitemradio', {name: languageName})).toHaveAttribute(
      'aria-checked',
      'true',
    )

    await user.click(otherLanguageMenuItem)

    expect(setUiState).toHaveBeenCalledTimes(1)
    expect(within(codeContainerEl).queryByRole('button', {name: `Language: ${languageName}`})).not.toBeInTheDocument()
    expect(within(codeContainerEl).getByRole('button', {name: `Language: ${otherLanguageName}`})).toBeInTheDocument()
    const uiState = getLocalStorageUiState()
    expect(uiState.preferredLanguage).toEqual(otherLanguage)
    expect(uiState.preferredSdk).toEqual(selectedSDK)
  })
})

function render(component: JSX.Element, manager?: PlaygroundManager) {
  const managerValue = manager ?? ({} as PlaygroundManager)
  const stateValue = mockPlaygroundState()
  return htmlRender(
    <PlaygroundManagerProvider manager={managerValue}>
      <PlaygroundStateProvider state={stateValue}>{component}</PlaygroundStateProvider>
    </PlaygroundManagerProvider>,
  )
}
