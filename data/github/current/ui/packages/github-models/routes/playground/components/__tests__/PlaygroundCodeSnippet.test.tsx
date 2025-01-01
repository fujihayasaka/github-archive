import {act, within} from '@testing-library/react'
import {render as htmlRender, type TestRenderOptions} from '@github-ui/react-core/test-utils'
import {modelPlaygroundPath} from '@github-ui/paths'
import {PlaygroundCodeSnippet, type language} from '../PlaygroundCodeSnippet'
import {mockModelState, mockPlaygroundState} from './mocks'
import {mockGettingStarted, mockLocalStorageUiState} from '../../__tests__/mocks'
import {PlaygroundStateProvider} from '../../../../contexts/PlaygroundStateContext'
import type {PlaygroundState} from '../../../../types'

describe('PlaygroundCodeSnippet', () => {
  test('renders code editor when there is a starter snippet for the selected language', async () => {
    const selectedLanguage: language = 'js'
    const gettingStarted = Object.assign({}, mockGettingStarted)
    gettingStarted[selectedLanguage] = {
      name: 'JavaScript',
      sdks: {
        'default-sdk': {
          name: 'Some nice SDK',
          content: 'sample content',
          tocHeadings: [],
          codeSamples: 'alert("I am a code sample for JavaScript");',
        },
      },
    }
    const modelState = mockModelState({gettingStarted})
    const playgroundState = mockPlaygroundState({models: [modelState]})
    const uiState = {...mockLocalStorageUiState, preferredLanguage: selectedLanguage, preferredSdk: 'default-sdk'}

    const {container} = await render(<PlaygroundCodeSnippet model={modelState} uiState={uiState} />, playgroundState, {
      routePayload: {playgroundUrl: `${modelPlaygroundPath(modelState.catalogData)}/code`},
    })

    expect(within(container).getByRole('button', {name: 'Copy to clipboard'})).toBeInTheDocument()
    expect(within(container).getByTestId('codemirror-editor')).toBeInTheDocument()
  })

  test('renders Code not available when there is no starter snippet for the selected language', async () => {
    const selectedLanguage: language = 'csharp'
    const gettingStarted = Object.assign({}, mockGettingStarted)
    delete gettingStarted[selectedLanguage]
    const modelState = mockModelState({gettingStarted})
    const playgroundState = mockPlaygroundState({models: [modelState]})
    const uiState = {...mockLocalStorageUiState, preferredLanguage: selectedLanguage, preferredSdk: 'default-sdk'}

    const {container} = await render(<PlaygroundCodeSnippet model={modelState} uiState={uiState} />, playgroundState, {
      routePayload: {playgroundUrl: `${modelPlaygroundPath(modelState.catalogData)}/code`},
    })

    expect(within(container).getByRole('button', {name: 'Copy to clipboard'})).toBeInTheDocument()
    expect(within(container).getByTestId('codemirror-editor')).toBeInTheDocument()
    expect(within(container).getByText('Code snippet not available')).toBeInTheDocument()
  })

  test('renders Code not available when there is no sdk available for the selected language', async () => {
    const selectedLanguage: language = 'csharp'
    const gettingStarted = Object.assign({}, mockGettingStarted)

    const modelState = mockModelState({gettingStarted})
    const playgroundState = mockPlaygroundState({models: [modelState]})
    const uiState = {...mockLocalStorageUiState, preferredLanguage: selectedLanguage, preferredSdk: 'default-sdk'}

    const {container} = await render(<PlaygroundCodeSnippet model={modelState} uiState={uiState} />, playgroundState, {
      routePayload: {playgroundUrl: `${modelPlaygroundPath(modelState.catalogData)}/code`},
    })

    expect(within(container).getByRole('button', {name: 'Copy to clipboard'})).toBeInTheDocument()
    expect(within(container).getByTestId('codemirror-editor')).toBeInTheDocument()
    expect(within(container).getByText('Code snippet not available')).toBeInTheDocument()
  })

  test('renders Code not available when there is no code snippet available for the selected sdk', async () => {
    const selectedLanguage: string = 'go'
    const gettingStarted = Object.assign({}, mockGettingStarted)

    const modelState = mockModelState({gettingStarted})
    const playgroundState = mockPlaygroundState({models: [modelState]})
    const uiState = {...mockLocalStorageUiState, preferredLanguage: selectedLanguage, preferredSdk: 'azure-go-sdk'}

    const {container} = await render(<PlaygroundCodeSnippet model={modelState} uiState={uiState} />, playgroundState, {
      routePayload: {playgroundUrl: `${modelPlaygroundPath(modelState.catalogData)}/code`},
    })

    expect(within(container).getByRole('button', {name: 'Copy to clipboard'})).toBeInTheDocument()
    expect(within(container).getByTestId('codemirror-editor')).toBeInTheDocument()
    expect(within(container).getByText('Code snippet not available')).toBeInTheDocument()
  })
})

async function render(component: JSX.Element, playgroundState: PlaygroundState, opts?: TestRenderOptions) {
  // PlaygroundCodeSnippet has a Suspense around use of CodeMirror.
  // eslint-disable-next-line testing-library/no-unnecessary-act
  return await act(async () => {
    return htmlRender(<PlaygroundStateProvider state={playgroundState}>{component}</PlaygroundStateProvider>, opts)
  })
}
