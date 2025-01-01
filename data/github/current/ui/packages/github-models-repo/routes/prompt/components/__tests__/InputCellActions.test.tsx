import {render as htmlRender} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import {PromptCompareManagerContext, type PromptCompareManager} from '../../prompt-compare-manager'
import type {DatasetTableItem, EvalsRow, EvaluationResult, Message, RowPromptResult} from '../../types'
import {InputCellActions} from '../InputCellActions'

const onAdd = jest.fn().mockName('onAdd')
const onEdit = jest.fn().mockName('onEdit')
const evalsToggleRowSkip = jest.fn().mockName('evalsToggleRowSkip')

describe('InputCellActions', () => {
  afterEach(() => {
    jest.resetAllMocks()
  })

  it('renders for an item without data', async () => {
    const item: DatasetTableItem = {id: 1, data: null}

    const {user} = render(<InputCellActions item={item} onAdd={onAdd} onEdit={onEdit} isRunning={false} />)

    expect(onAdd).not.toHaveBeenCalled()
    const addButton = screen.getByRole('button', {name: 'Add row'})
    expect(addButton).toBeInTheDocument()
    expect(screen.queryByRole('button', {name: 'Edit row 1'})).not.toBeInTheDocument()
    expect(screen.queryByRole('button', {name: 'Skip row 1'})).not.toBeInTheDocument()
    expect(screen.queryByRole('button', {name: 'Unskip row 1'})).not.toBeInTheDocument()

    await user.click(addButton)

    expect(onAdd).toHaveBeenCalledTimes(1)
    expect(onEdit).not.toHaveBeenCalled()
    expect(evalsToggleRowSkip).not.toHaveBeenCalled()
  })

  it('renders for an unskipped item with data', async () => {
    const message: Message = {role: 'user', message: 'Write me a poem about {{input}}', timestamp: new Date()}
    const evalResult: EvaluationResult = {pass: false, score: 0}
    const result: RowPromptResult = {completions: [message], evals: [evalResult]}
    const data: EvalsRow = {input: 'cats', id: '123'}
    const item: DatasetTableItem = {id: 8675309, data, result: [result]}

    const {user} = render(<InputCellActions item={item} onAdd={onAdd} onEdit={onEdit} isRunning={false} />)

    const editButton = screen.getByRole('button', {name: 'Edit row 8675309'})
    expect(editButton).toBeInTheDocument()
    const skipButton = screen.getByRole('button', {name: 'Skip row 8675309'})
    expect(skipButton).toBeInTheDocument()
    expect(screen.queryByRole('button', {name: 'Unskip row 8675309'})).not.toBeInTheDocument()
    expect(screen.queryByRole('button', {name: 'Add row'})).not.toBeInTheDocument()
    expect(onEdit).not.toHaveBeenCalled()

    await user.click(editButton)

    expect(onEdit).toHaveBeenCalledTimes(1)
    expect(evalsToggleRowSkip).not.toHaveBeenCalled()

    await user.click(skipButton)

    expect(evalsToggleRowSkip).toHaveBeenCalledTimes(1)
    expect(evalsToggleRowSkip).toHaveBeenCalledWith('8675309')
    expect(onAdd).not.toHaveBeenCalled()
  })

  it('renders for a skipped item with data', async () => {
    const message: Message = {role: 'user', message: 'Write me a poem about {{input}}', timestamp: new Date()}
    const evalResult: EvaluationResult = {pass: false, score: 0}
    const result: RowPromptResult = {completions: [message], evals: [evalResult]}
    const data: EvalsRow = {input: 'cats', id: '123'}
    const item: DatasetTableItem = {id: 13, data, result: [result]}

    const {user} = render(<InputCellActions item={item} onAdd={onAdd} onEdit={onEdit} skipped isRunning={false} />)

    expect(screen.getByRole('button', {name: 'Edit row 13'})).toBeInTheDocument()
    const unskipButton = screen.getByRole('button', {name: 'Unskip row 13'})
    expect(unskipButton).toBeInTheDocument()
    expect(screen.queryByRole('button', {name: 'Skip row 13'})).not.toBeInTheDocument()
    expect(screen.queryByRole('button', {name: 'Add row'})).not.toBeInTheDocument()
    expect(evalsToggleRowSkip).not.toHaveBeenCalled()

    await user.click(unskipButton)

    expect(evalsToggleRowSkip).toHaveBeenCalledTimes(1)
    expect(evalsToggleRowSkip).toHaveBeenCalledWith('13')
    expect(onEdit).not.toHaveBeenCalled()
    expect(onAdd).not.toHaveBeenCalled()
  })

  it('renders disabled buttons when isRunning is true', async () => {
    const message: Message = {role: 'user', message: 'Write me a poem about {{input}}', timestamp: new Date()}
    const evalResult: EvaluationResult = {pass: false, score: 0}
    const result: RowPromptResult = {completions: [message], evals: [evalResult]}
    const data: EvalsRow = {input: 'cats', id: '123'}
    const item: DatasetTableItem = {id: 8675309, data, result: [result]}

    const {user} = render(<InputCellActions item={item} onAdd={onAdd} onEdit={onEdit} isRunning />)

    const editButton = screen.getByRole('button', {name: 'Editing disabled for row 8675309. Run is in progress'})
    const skipButton = screen.getByRole('button', {name: 'Skipping disabled for row 8675309. Run is in progress'})

    expect(editButton).toBeInTheDocument()
    expect(skipButton).toBeInTheDocument()
    expect(editButton).toHaveAttribute('aria-disabled', 'true')
    expect(skipButton).toHaveAttribute('aria-disabled', 'true')

    await user.click(editButton)
    expect(onEdit).not.toHaveBeenCalled()

    await user.click(skipButton)
    expect(evalsToggleRowSkip).not.toHaveBeenCalled()

    expect(screen.queryByRole('button', {name: 'Unskip row 8675309'})).not.toBeInTheDocument()
    expect(screen.queryByRole('button', {name: 'Add row'})).not.toBeInTheDocument()
  })
})

function render(component: JSX.Element) {
  const manager = {} as PromptCompareManager
  manager.evalsToggleRowSkip = evalsToggleRowSkip

  return htmlRender(
    <PromptCompareManagerContext.Provider value={manager}>{component}</PromptCompareManagerContext.Provider>,
  )
}
