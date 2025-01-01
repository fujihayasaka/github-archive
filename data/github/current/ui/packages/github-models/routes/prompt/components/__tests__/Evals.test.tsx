import {render as htmlRender} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import {AzureModelClient} from '../../../../utils/azure-model-client'
import type {PromptEvalsManager} from '../../prompt-evals-manager'
import {PromptEvalsManagerContext} from '../../prompt-evals-manager'
import type {PromptEvalsState} from '../../prompt-evals-state'
import {PromptEvalsStateProvider} from '../../contexts/PromptEvalsStateContext'
import {Evals} from '../Evals'
import {mockPromptEvalsState} from './mocks'
import {mockModel} from '../../../playground/__tests__/mocks'
import {mockModelState} from '../../../playground/components/__tests__/mocks'

describe('Evals', () => {
  test('renders', () => {
    const playgroundUrl = 'azure-ai-playground-url.com'
    const mockModelClient = new AzureModelClient(playgroundUrl)
    const model = Object.assign({}, mockModel, {publisher: 'Open AI'})
    const modelState = mockModelState({catalogData: model})

    render(<Evals modelClient={mockModelClient} />, {model: modelState})

    expect(screen.getAllByRole('link', {name: 'Give feedback'}).length).toBeGreaterThanOrEqual(1)
    expect(screen.getByRole('button', {name: 'Switch model'})).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Show model info'})).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Chat'})).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Playground'})).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Use this model'})).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Run ( control enter )'})).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Prompt'})).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Evaluate'})).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Import rows'})).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Add row'})).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Add test criteria'})).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Actions'})).toBeInTheDocument()
    expect(screen.getByRole('img', {name: 'Open AI logo'})).toBeInTheDocument()
    expect(screen.getByRole('list', {name: 'View mode'})).toBeInTheDocument()
    expect(screen.getByRole('columnheader', {name: 'input'})).toBeInTheDocument()
    expect(screen.getByRole('columnheader', {name: 'expected'})).toBeInTheDocument()
    expect(screen.getByRole('columnheader', {name: 'Output'})).toBeInTheDocument()
    expect(screen.getByRole('columnheader', {name: 'Actions'})).toBeInTheDocument()
  })
})

function render(component: JSX.Element, stateOverrides: Partial<PromptEvalsState> = {}) {
  const state = mockPromptEvalsState(stateOverrides)
  const manager = {} as PromptEvalsManager
  return htmlRender(
    <PromptEvalsStateProvider state={state}>
      <PromptEvalsManagerContext.Provider value={manager}>{component}</PromptEvalsManagerContext.Provider>
    </PromptEvalsStateProvider>,
  )
}
