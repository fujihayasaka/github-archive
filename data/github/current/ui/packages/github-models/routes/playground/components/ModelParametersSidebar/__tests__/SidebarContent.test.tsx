import {within} from '@testing-library/react'
import {render as htmlRender} from '@github-ui/react-core/test-utils'
import {Panel, type PlaygroundManager} from '../../../../../utils/playground-manager'
import {PlaygroundManagerProvider} from '../../../../../contexts/PlaygroundManagerContext'
import {SidebarSelectionOptions} from '../../../../../types'
import {SidebarContent} from '../SidebarContent'
import {mockModelState} from '../../__tests__/mocks'
import {mockModel} from '../../../__tests__/mocks'
import type {PlaygroundRequestParameters} from '../../../../../types'

describe('SidebarContent', () => {
  test('renders details tab', () => {
    const summary = 'hello world this is my model'
    const model = Object.assign({}, mockModel, {summary})
    const modelState = mockModelState({catalogData: model, parameters: {max_tokens: 2048}})

    const {container} = render(
      <SidebarContent activeTab={SidebarSelectionOptions.DETAILS} modelState={modelState} position={Panel.Main} />,
    )

    expect(within(container).queryByRole('spinbutton', {name: 'max_tokens', hidden: true})).not.toBeInTheDocument()
    expect(within(container).getByRole('heading', {name: 'About', level: 3})).toBeInTheDocument()
    expect(within(container).getByTestId('summary')).toHaveTextContent(summary)
    expect(within(container).getByTestId('model-details')).toBeInTheDocument()
    expect(within(container).getByRole('heading', {name: 'Tags', level: 3})).toBeInTheDocument()
    expect(within(container).getByRole('heading', {name: 'Languages', level: 3})).toBeInTheDocument()
  })

  test('renders parameters tab', () => {
    const maxTokens = 2048
    const temperature = 0.8
    const topP = 0.1
    const parameters: PlaygroundRequestParameters = {max_tokens: maxTokens, temperature, top_p: topP, stop: undefined}
    const modelState = mockModelState({parameters})

    const {container} = render(
      <SidebarContent activeTab={SidebarSelectionOptions.PARAMETERS} modelState={modelState} position={Panel.Main} />,
    )

    expect(within(container).queryByTestId('model-details')).not.toBeInTheDocument()
    expect(within(container).getByRole('spinbutton', {name: 'max_tokens', hidden: true})).toHaveValue(maxTokens)
    expect(within(container).getByRole('spinbutton', {name: 'temperature', hidden: true})).toHaveValue(temperature)
    expect(within(container).getByRole('spinbutton', {name: 'top_p', hidden: true})).toHaveValue(topP)
    expect(within(container).getByRole('textbox', {name: 'stop', hidden: true})).toHaveValue('')
  })
})

function render(component: JSX.Element) {
  const manager = {} as PlaygroundManager
  return htmlRender(<PlaygroundManagerProvider manager={manager}>{component}</PlaygroundManagerProvider>)
}
