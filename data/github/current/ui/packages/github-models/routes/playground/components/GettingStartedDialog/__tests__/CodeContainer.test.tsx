import {screen, within} from '@testing-library/react'
import type {SafeHTMLString} from '@github-ui/safe-html'
import {render as htmlRender} from '@github-ui/react-core/test-utils'
import {CodeContainer} from '../CodeContainer'
import {mockGettingStarted} from '../../../__tests__/mocks'
import type {GettingStarted} from '../../../../../types'
import {type PlaygroundManager, PlaygroundManagerContext} from '../../../../../utils/playground-manager'
import {PlaygroundStateProvider} from '../../../../../contexts/PlaygroundStateContext'
import {mockPlaygroundState, mockSDK} from './mocks'

const selectedLanguage = 'intercal'
const selectedSDK = 'some-sdk'

describe('CodeContainer', () => {
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
    expect(within(codeContainerEl).getByText(tocHeadingText1)).toBeInTheDocument()
    expect(within(codeContainerEl).getByText(tocHeadingText2)).toBeInTheDocument()
    expect(within(codeContainerEl).queryByText(tocLowerLevelHeadingText)).not.toBeInTheDocument()
  })

  test('allows changing selected SDK', async () => {
    const otherSDK = `${selectedSDK}-123`
    const otherSDKName = `${sdkName} But Better`
    const gettingStarted: GettingStarted = {
      [selectedLanguage]: {
        name: languageName,
        sdks: {[selectedSDK]: mockSDK({name: sdkName}), [otherSDK]: mockSDK({name: otherSDKName})},
      },
    }
    const setSelectedSDK = jest.fn()
    const manager = {} as PlaygroundManager
    manager.setSelectedSDK = setSelectedSDK

    const {container, user} = render(
      <CodeContainer
        openInCodespaceUrl={openInCodespaceUrl}
        showCodespacesSuggestion
        gettingStarted={gettingStarted}
        modelName={modelName}
      />,
      manager,
    )

    const codeContainerEl = within(container).getByTestId('code-container')
    const sdkButton = within(codeContainerEl).getByRole('button', {name: `SDK: ${sdkName}`})
    expect(sdkButton).toBeInTheDocument()
    expect(setSelectedSDK).not.toHaveBeenCalled()
    expect(screen.queryByRole('menuitemradio', {name: otherSDKName})).not.toBeInTheDocument()

    await user.click(sdkButton)

    const sdkMenu = screen.getByRole('menu', {name: `SDK: ${sdkName}`})
    expect(sdkMenu).toBeInTheDocument()
    const otherSDKMenuItem = within(sdkMenu).getByRole('menuitemradio', {name: otherSDKName})
    expect(otherSDKMenuItem).toBeInTheDocument()
    expect(otherSDKMenuItem).toHaveAttribute('aria-checked', 'false')
    expect(within(sdkMenu).getByRole('menuitemradio', {name: sdkName})).toHaveAttribute('aria-checked', 'true')

    await user.click(otherSDKMenuItem)

    expect(setSelectedSDK).toHaveBeenCalledTimes(1)
    expect(setSelectedSDK).toHaveBeenCalledWith(otherSDK)
    expect(within(codeContainerEl).queryByRole('button', {name: `SDK: ${sdkName}`})).not.toBeInTheDocument()
    expect(within(codeContainerEl).getByRole('button', {name: `SDK: ${otherSDKName}`})).toBeInTheDocument()
  })

  test('allows changing selected language', async () => {
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
    const setSelectedLanguage = jest.fn()
    const manager = {} as PlaygroundManager
    manager.setSelectedLanguage = setSelectedLanguage

    const {container, user} = render(
      <CodeContainer
        openInCodespaceUrl={openInCodespaceUrl}
        showCodespacesSuggestion
        gettingStarted={gettingStarted}
        modelName={modelName}
      />,
      manager,
    )

    const codeContainerEl = within(container).getByTestId('code-container')
    const languageButton = within(codeContainerEl).getByRole('button', {name: `Language: ${languageName}`})
    expect(languageButton).toBeInTheDocument()
    expect(setSelectedLanguage).not.toHaveBeenCalled()
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

    expect(setSelectedLanguage).toHaveBeenCalledTimes(1)
    expect(setSelectedLanguage).toHaveBeenCalledWith(gettingStarted, otherLanguage, selectedSDK)
    expect(within(codeContainerEl).queryByRole('button', {name: `Language: ${languageName}`})).not.toBeInTheDocument()
    expect(within(codeContainerEl).getByRole('button', {name: `Language: ${otherLanguageName}`})).toBeInTheDocument()
  })
})

function render(component: JSX.Element, manager?: PlaygroundManager) {
  const managerValue = manager ?? ({} as PlaygroundManager)
  const stateValue = mockPlaygroundState({selectedLanguage, selectedSDK})
  return htmlRender(
    <PlaygroundManagerContext.Provider value={managerValue}>
      <PlaygroundStateProvider state={stateValue}>{component}</PlaygroundStateProvider>
    </PlaygroundManagerContext.Provider>,
  )
}
