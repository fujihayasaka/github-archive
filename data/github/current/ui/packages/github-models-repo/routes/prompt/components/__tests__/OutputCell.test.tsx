import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import {mockTokenUsage} from '../../../../test-utils/mock-data'
import type {CompareRow, EvalsRow, EvaluationResult, Message, RowPromptResult} from '../../types'
import type {CompareState} from '../../prompt-compare-state'
import {OutputCell} from '../OutputCell'

describe('OutputCell', () => {
  it('renders a loading state for the first row that was not skipped', () => {
    const row: CompareRow = {id: 0, data: {id: '0'}}
    const compareState: CompareState = {
      isRunning: true,
      rows: [],
      skippedRowIds: new Set<string>(),
      result: {},
      evaluators: [],
    }

    render(<OutputCell isRunning row={row} compare={compareState} index={1} dataRows={[row]} firstUnskippedRowId="0" />)

    expect(screen.getByText('Responding')).toBeInTheDocument()
    expect(screen.getByTestId('loading-dots')).toBeInTheDocument()
    expect(screen.queryByTestId('playground-token-usage')).not.toBeInTheDocument()
  })

  it('renders a loading state for a later row', () => {
    const row: CompareRow = {id: 1, data: {id: '1'}}
    const compareState: CompareState = {
      isRunning: true,
      rows: [],
      skippedRowIds: new Set<string>(),
      result: {},
      evaluators: [],
    }

    render(<OutputCell isRunning row={row} compare={compareState} index={1} dataRows={[row]} />)

    expect(screen.queryByText('Responding')).not.toBeInTheDocument()
    expect(screen.getByTestId('loading-dots')).toBeInTheDocument()
    expect(screen.queryByTestId('playground-token-usage')).not.toBeInTheDocument()
  })

  it('renders completions and token usage', () => {
    const message: Message = {role: 'user', message: 'Write me a poem about {{input}}', timestamp: new Date()}
    const evalResult: EvaluationResult = {pass: false, score: 0}
    const tokenUsage = mockTokenUsage()
    const result: RowPromptResult = {completions: [message], evals: [evalResult], tokenUsage}
    const data: EvalsRow = {input: 'cats', id: '1'}
    const row: CompareRow = {id: 1, data, result: [result]}
    const compareState: CompareState = {
      isRunning: false,
      rows: [data],
      skippedRowIds: new Set<string>(),
      result: {[row.id]: [result]},
      evaluators: [],
    }

    render(<OutputCell isRunning={false} row={row} compare={compareState} index={0} dataRows={[row]} />)

    expect(screen.getByText(message.message)).toBeInTheDocument()
    expect(screen.queryByText('Responding')).not.toBeInTheDocument()
    expect(screen.queryByTestId('loading-dots')).not.toBeInTheDocument()
    expect(screen.getByTestId('playground-token-usage')).toBeInTheDocument()
  })

  it('renders nothing for a skipped row without a result', () => {
    const data: EvalsRow = {input: 'cats', id: '1'}
    const row: CompareRow = {id: 1, data}
    const compareState: CompareState = {
      isRunning: false,
      rows: [data],
      skippedRowIds: new Set<string>(['1']),
      result: {},
      evaluators: [],
    }

    render(<OutputCell isRunning={false} row={row} compare={compareState} index={0} dataRows={[row]} />)

    expect(screen.queryByText('Responding')).not.toBeInTheDocument()
    expect(screen.queryByTestId('loading-dots')).not.toBeInTheDocument()
    expect(screen.queryByTestId('playground-token-usage')).not.toBeInTheDocument()
  })

  it('renders nothing when loading a skipped row without a result', () => {
    const data: EvalsRow = {input: 'cats', id: '1'}
    const row: CompareRow = {id: 1, data}
    const compareState: CompareState = {
      isRunning: true,
      rows: [data],
      skippedRowIds: new Set<string>(['1']),
      result: {},
      evaluators: [],
    }

    render(<OutputCell isRunning skipped row={row} compare={compareState} index={0} dataRows={[row]} />)

    expect(screen.queryByText('Responding')).not.toBeInTheDocument()
    expect(screen.queryByTestId('loading-dots')).not.toBeInTheDocument()
    expect(screen.queryByTestId('playground-token-usage')).not.toBeInTheDocument()
  })
})
