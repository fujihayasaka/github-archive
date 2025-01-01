import {render as htmlRender, type TestRenderOptions} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import {CurrentRepositoryProvider} from '@github-ui/current-repository'
import {createRepository} from '@github-ui/current-repository/test-helpers'
import {PromptCompareManagerContext, type PromptCompareManager} from '../../prompt-compare-manager'
import type {EvalsRow, PromptAppPayload, RowPromptResult, EvaluationResult, Message} from '../../types'
import {mockPromptCompareState, mockPromptConfig, mockTokenUsage} from '../../../../test-utils/mock-data'
import {DatasetTable} from '../DatasetTable'
import type {PromptCompareState, CompareState} from '../../prompt-compare-state'
import {PromptCompareStateProvider} from '../../contexts/PromptCompareStateContext'

const onAdd = jest.fn().mockName('onAdd')
const onEdit = jest.fn().mockName('onEdit')

describe('DatasetTable', () => {
  beforeEach(() => {
    jest.clearAllMocks()
  })

  it('renders empty state with default input column', () => {
    const prompts = [mockPromptConfig({messages: [{role: 'user', message: 'Hello', timestamp: new Date()}]})]
    const inputs: EvalsRow[] = []
    const compare: CompareState = {
      isRunning: false,
      rows: [],
      skippedRowIds: new Set(),
      result: {},
      evaluators: [],
    }

    render(
      <DatasetTable
        prompts={prompts}
        columnMaxWidth="200px"
        inputs={inputs}
        isRunning={false}
        compare={compare}
        onAdd={onAdd}
        onEdit={onEdit}
      />,
    )

    // Should render the dataset table with heading
    expect(screen.getByText('Dataset')).toBeInTheDocument()

    // Should have consolidated Input column
    expect(screen.getByRole('columnheader', {name: 'Input'})).toBeInTheDocument()

    // Should have output column for the prompt
    expect(screen.getByRole('columnheader', {name: 'Output 1'})).toBeInTheDocument()

    // Should show add input text for empty row
    expect(screen.getByText('Add input text')).toBeInTheDocument()
  })

  it('renders with multiple prompt variables', () => {
    const prompts = [
      mockPromptConfig({
        messages: [
          {
            role: 'user',
            message: 'Tell me about {{subject}} in the context of {{context}} using this input: {{input}}',
            timestamp: new Date(),
          },
        ],
      }),
    ]
    const inputs: EvalsRow[] = [{id: '1', subject: 'cats', context: 'pets', input: 'meowing'}]
    const compare: CompareState = {
      isRunning: false,
      rows: inputs,
      skippedRowIds: new Set(),
      result: {},
      evaluators: [],
    }

    render(
      <DatasetTable
        prompts={prompts}
        columnMaxWidth="200px"
        inputs={inputs}
        isRunning={false}
        compare={compare}
        onAdd={onAdd}
        onEdit={onEdit}
      />,
    )

    // Should have consolidated Input column with all variables displayed within it
    expect(screen.getByRole('columnheader', {name: 'Input'})).toBeInTheDocument()
    expect(screen.getByRole('columnheader', {name: 'Output 1'})).toBeInTheDocument()

    // Should render the data values within the consolidated Input column
    expect(screen.getByText('cats')).toBeInTheDocument()
    expect(screen.getByText('pets')).toBeInTheDocument()
    expect(screen.getByText('meowing')).toBeInTheDocument()
  })

  it('renders with multiple prompts', () => {
    const prompts = [
      mockPromptConfig({messages: [{role: 'user', message: 'Hello {{input}}', timestamp: new Date()}]}),
      mockPromptConfig({messages: [{role: 'user', message: 'Hi {{input}}', timestamp: new Date()}]}),
    ]
    const inputs: EvalsRow[] = [{id: '1', input: 'world'}]
    const compare: CompareState = {
      isRunning: false,
      rows: inputs,
      skippedRowIds: new Set(),
      result: {},
      evaluators: [],
    }

    render(
      <DatasetTable
        prompts={prompts}
        columnMaxWidth="200px"
        inputs={inputs}
        isRunning={false}
        compare={compare}
        onAdd={onAdd}
        onEdit={onEdit}
      />,
    )

    // Should have output columns for each prompt
    expect(screen.getByRole('columnheader', {name: 'Output 1'})).toBeInTheDocument()
    expect(screen.getByRole('columnheader', {name: 'Output 2'})).toBeInTheDocument()
  })

  it('renders skipped rows correctly', () => {
    const prompts = [mockPromptConfig({messages: [{role: 'user', message: 'Hello {{input}}', timestamp: new Date()}]})]
    const inputs: EvalsRow[] = [
      {id: '1', input: 'world'},
      {id: '2', input: 'test'},
    ]
    const compare: CompareState = {
      isRunning: false,
      rows: inputs,
      skippedRowIds: new Set(['2']), // Second row is skipped
      result: {},
      evaluators: [],
    }

    const promptCompareState = mockPromptCompareState({
      prompts,
      compare,
    })

    render(
      <DatasetTable
        prompts={prompts}
        columnMaxWidth="200px"
        inputs={inputs}
        isRunning={false}
        compare={compare}
        onAdd={onAdd}
        onEdit={onEdit}
      />,
      {},
      promptCompareState,
    )

    // Both rows should be rendered
    expect(screen.getByText('world')).toBeInTheDocument()
    expect(screen.getByText('test')).toBeInTheDocument()
  })

  it('renders with results', () => {
    const prompts = [mockPromptConfig({messages: [{role: 'user', message: 'Hello {{input}}', timestamp: new Date()}]})]
    const inputs: EvalsRow[] = [{id: '1', input: 'world'}]

    const message: Message = {
      role: 'assistant',
      message: 'Hello world, how are you?',
      timestamp: new Date(),
    }
    const evalResult: EvaluationResult = {pass: true, score: 0.9}
    const tokenUsage = mockTokenUsage({totalInputTokens: 10, totalOutputTokens: 15})
    const result: RowPromptResult = {
      completions: [message],
      evals: [evalResult],
      tokenUsage,
    }

    const compare: CompareState = {
      isRunning: false,
      rows: inputs,
      skippedRowIds: new Set(),
      result: {0: [result]}, // Result for first row (index 0)
      evaluators: [],
    }

    render(
      <DatasetTable
        prompts={prompts}
        columnMaxWidth="200px"
        inputs={inputs}
        result={{0: [result]}}
        isRunning={false}
        compare={compare}
        onAdd={onAdd}
        onEdit={onEdit}
      />,
    )

    // Should render the completion message
    expect(screen.getByText('Hello world, how are you?')).toBeInTheDocument()

    // Should render token usage
    expect(screen.getByTestId('playground-token-usage')).toBeInTheDocument()
  })

  it('renders loading state when running', () => {
    const prompts = [mockPromptConfig({messages: [{role: 'user', message: 'Hello {{input}}', timestamp: new Date()}]})]
    const inputs: EvalsRow[] = [{id: '1', input: 'world'}]
    const compare: CompareState = {
      isRunning: true,
      rows: inputs,
      skippedRowIds: new Set(),
      result: {},
      evaluators: [],
    }

    render(
      <DatasetTable
        prompts={prompts}
        columnMaxWidth="200px"
        inputs={inputs}
        isRunning
        compare={compare}
        onAdd={onAdd}
        onEdit={onEdit}
      />,
    )

    // Should show loading state for the first unskipped row
    expect(screen.getByText('Responding')).toBeInTheDocument()
    expect(screen.getByTestId('loading-dots')).toBeInTheDocument()
  })

  it('calls onAdd when add button is clicked', async () => {
    const prompts = [mockPromptConfig({messages: [{role: 'user', message: 'Hello {{input}}', timestamp: new Date()}]})]
    const inputs: EvalsRow[] = []
    const compare: CompareState = {
      isRunning: false,
      rows: [],
      skippedRowIds: new Set(),
      result: {},
      evaluators: [],
    }

    const {user} = render(
      <DatasetTable
        prompts={prompts}
        columnMaxWidth="200px"
        inputs={inputs}
        isRunning={false}
        compare={compare}
        onAdd={onAdd}
        onEdit={onEdit}
      />,
    )

    const addButton = screen.getByRole('button', {name: 'Add row'})
    await user.click(addButton)

    expect(onAdd).toHaveBeenCalledTimes(1)
  })

  it('calls onEdit when edit button is clicked', async () => {
    const prompts = [mockPromptConfig({messages: [{role: 'user', message: 'Hello {{input}}', timestamp: new Date()}]})]
    const inputs: EvalsRow[] = [{id: '1', input: 'world'}]
    const compare: CompareState = {
      isRunning: false,
      rows: inputs,
      skippedRowIds: new Set(),
      result: {},
      evaluators: [],
    }

    const {user} = render(
      <DatasetTable
        prompts={prompts}
        columnMaxWidth="200px"
        inputs={inputs}
        isRunning={false}
        compare={compare}
        onAdd={onAdd}
        onEdit={onEdit}
      />,
    )

    const editButton = screen.getByRole('button', {name: 'Edit row 1'})
    await user.click(editButton)

    expect(onEdit).toHaveBeenCalledTimes(1)
    expect(onEdit).toHaveBeenCalledWith(inputs[0])
  })

  it('disables buttons when running', () => {
    const prompts = [mockPromptConfig({messages: [{role: 'user', message: 'Hello {{input}}', timestamp: new Date()}]})]
    const inputs: EvalsRow[] = [{id: '1', input: 'world'}]
    const compare: CompareState = {
      isRunning: true,
      rows: inputs,
      skippedRowIds: new Set(),
      result: {},
      evaluators: [],
    }

    render(
      <DatasetTable
        prompts={prompts}
        columnMaxWidth="200px"
        inputs={inputs}
        isRunning
        compare={compare}
        onAdd={onAdd}
        onEdit={onEdit}
      />,
    )

    // Buttons should be disabled when running (they have specific aria-labels when disabled)
    const editButton = screen.getByRole('button', {name: 'Editing disabled for row 1. Run is in progress'})
    const skipButton = screen.getByRole('button', {name: 'Skipping disabled for row 1. Run is in progress'})

    expect(editButton).toBeDisabled()
    expect(skipButton).toBeDisabled()
  })

  it('handles prompts with no variables by using input fallback', () => {
    const prompts = [mockPromptConfig({messages: [{role: 'user', message: 'Hello world', timestamp: new Date()}]})]
    const inputs: EvalsRow[] = [{id: '1', input: 'test'}]
    const compare: CompareState = {
      isRunning: false,
      rows: inputs,
      skippedRowIds: new Set(),
      result: {},
      evaluators: [],
    }

    render(
      <DatasetTable
        prompts={prompts}
        columnMaxWidth="200px"
        inputs={inputs}
        isRunning={false}
        compare={compare}
        onAdd={onAdd}
        onEdit={onEdit}
      />,
    )

    // Should have consolidated Input column when no variables are found
    expect(screen.getByRole('columnheader', {name: 'Input'})).toBeInTheDocument()
    expect(screen.getByText('test')).toBeInTheDocument()
  })

  it('handles empty prompts array by using input fallback', () => {
    const prompts: any[] = []
    const inputs: EvalsRow[] = [{id: '1', input: 'test'}]
    const compare: CompareState = {
      isRunning: false,
      rows: inputs,
      skippedRowIds: new Set(),
      result: {},
      evaluators: [],
    }

    render(
      <DatasetTable
        prompts={prompts}
        columnMaxWidth="200px"
        inputs={inputs}
        isRunning={false}
        compare={compare}
        onAdd={onAdd}
        onEdit={onEdit}
      />,
    )

    // Should have consolidated Input column when prompts array is empty
    expect(screen.getByRole('columnheader', {name: 'Input'})).toBeInTheDocument()
    expect(screen.getByText('test')).toBeInTheDocument()
  })
})

function render(component: JSX.Element, opts: TestRenderOptions = {}, promptCompareState?: PromptCompareState) {
  const manager = {} as PromptCompareManager
  let repository
  if (opts.appPayload) {
    const {payload} = opts.appPayload as PromptAppPayload
    repository = payload.repository
  }
  repository = repository || createRepository()

  return htmlRender(
    <CurrentRepositoryProvider repository={repository}>
      <PromptCompareStateProvider state={promptCompareState ?? mockPromptCompareState()}>
        <PromptCompareManagerContext.Provider value={manager}>{component}</PromptCompareManagerContext.Provider>
      </PromptCompareStateProvider>
    </CurrentRepositoryProvider>,
    opts,
  )
}
