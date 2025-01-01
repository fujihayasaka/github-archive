import {InputCell} from '../InputCell'
import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import type {CompareRow, EvalsRow, EvaluationResult, Message, RowPromptResult} from '../../types'

describe('InputCell', () => {
  it('renders empty', () => {
    const row: CompareRow = {id: 1, data: null}

    render(<InputCell row={row} />)

    expect(screen.getByText('Add input text')).toBeInTheDocument()
    expect(screen.queryByTestId('warning-icon')).not.toBeInTheDocument()
  })

  it('renders cell with data', async () => {
    const message: Message = {role: 'user', message: 'Write me a poem about {{input}}', timestamp: new Date()}
    const evalResult: EvaluationResult = {pass: false, score: 0}
    const result: RowPromptResult = {completions: [message], evals: [evalResult]}
    const data: EvalsRow = {input: 'cats', id: '123'}
    const row: CompareRow = {id: 1, data, result: [result]}

    render(<InputCell row={row} />)

    expect(screen.getByText('cats')).toBeInTheDocument()
  })

  it('renders children', () => {
    const row: CompareRow = {id: 1, data: null}

    render(
      <InputCell row={row}>
        <span>hello world</span>
      </InputCell>,
    )

    expect(screen.getByText('Add input text')).toBeInTheDocument()
    expect(screen.getByText('hello world')).toBeInTheDocument()
  })
})
