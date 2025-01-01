import {act, within} from '@testing-library/react'
import {render as htmlRender, type TestRenderOptions} from '@github-ui/react-core/test-utils'
import {PlaygroundCodeSnippet, type language} from '../PlaygroundCodeSnippet'
import {mockModelState, mockPlaygroundState} from './mocks'
import {mockGettingStarted} from '../../__tests__/mocks'
import {ModelUrlHelper} from '../../../../utils/model-url-helper'
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
    const playgroundState = mockPlaygroundState({selectedLanguage, models: [modelState]})

    const {container} = await render(<PlaygroundCodeSnippet model={modelState} />, playgroundState, {
      routePayload: {playgroundUrl: `${ModelUrlHelper.playgroundUrl(modelState.catalogData)}/code`},
    })

    expect(within(container).getByRole('button', {name: 'Copy to clipboard'})).toBeInTheDocument()
    expect(within(container).getByTestId('codemirror-editor')).toBeInTheDocument()
  })

  test('does not render when there is no starter snippet for the selected language', async () => {
    const selectedLanguage: language = 'csharp'
    const gettingStarted = Object.assign({}, mockGettingStarted)
    delete gettingStarted[selectedLanguage]
    const modelState = mockModelState({gettingStarted})
    const playgroundState = mockPlaygroundState({selectedLanguage, models: [modelState]})

    const {container} = await render(<PlaygroundCodeSnippet model={modelState} />, playgroundState, {
      routePayload: {playgroundUrl: `${ModelUrlHelper.playgroundUrl(modelState.catalogData)}/code`},
    })

    expect(within(container).queryByRole('button', {name: 'Copy to clipboard'})).not.toBeInTheDocument()
    expect(within(container).queryByTestId('codemirror-editor')).not.toBeInTheDocument()
  })
})

async function render(component: JSX.Element, playgroundState: PlaygroundState, opts?: TestRenderOptions) {
  // PlaygroundCodeSnippet has a Suspense around use of CodeMirror.
  // eslint-disable-next-line testing-library/no-unnecessary-act
  return await act(async () => {
    return htmlRender(<PlaygroundStateProvider state={playgroundState}>{component}</PlaygroundStateProvider>, opts)
  })
}
