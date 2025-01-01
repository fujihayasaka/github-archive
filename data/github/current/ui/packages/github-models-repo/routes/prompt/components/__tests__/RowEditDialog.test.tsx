import {render as htmlRender} from '@github-ui/react-core/test-utils'
import {screen, within} from '@testing-library/react'
import {mockResizeObserver} from '../../../../test-utils/mock-data'
import {PromptCompareManagerContext, type PromptCompareManager} from '../../prompt-compare-manager'
import type {EvalsRow} from '../../types'
import {RowEditDialog} from '../RowEditDialog'

const setShowRowDialog = jest.fn().mockName('setShowRowDialog')
const evalsAddRow = jest.fn().mockName('evalsAddRow')
const evalsUpdateRow = jest.fn().mockName('evalsUpdateRow')
const evalsRemoveRow = jest.fn().mockName('evalsRemoveRow')

describe('RowEditDialog', () => {
  beforeEach(() => {
    // Necessary to avoid a 'TypeError: observer.observe is not a function' error when all tests are run.
    mockResizeObserver()
  })

  afterEach(() => {
    jest.resetAllMocks()
  })

  it('renders for an existing row', async () => {
    const row: EvalsRow = {input: 'cats', id: '123'}

    const {user} = render(<RowEditDialog setShowRowDialog={setShowRowDialog} row={row} />)

    const dialog = screen.getByRole('dialog', {name: 'Edit Row'})
    expect(dialog).toBeInTheDocument()
    expect(within(dialog).getByRole('textbox', {name: 'input'})).toHaveValue('cats')
    expect(within(dialog).getByRole('textbox', {name: 'expected'})).toHaveValue('')
    expect(within(dialog).getByRole('button', {name: 'Save'})).toBeInTheDocument()
    expect(within(dialog).getByRole('button', {name: 'Cancel'})).toBeInTheDocument()
    const closeButton = within(dialog).getByRole('button', {name: 'Close'})
    expect(closeButton).toBeInTheDocument()
    expect(within(dialog).getByRole('button', {name: 'Delete row'})).toBeInTheDocument()
    expect(within(dialog).queryByRole('button', {name: 'Add'})).not.toBeInTheDocument()
    expect(setShowRowDialog).not.toHaveBeenCalled()

    await user.click(closeButton)

    expect(setShowRowDialog).toHaveBeenCalledTimes(1)
    expect(setShowRowDialog).toHaveBeenCalledWith(false)
    expect(evalsAddRow).not.toHaveBeenCalled()
    expect(evalsUpdateRow).not.toHaveBeenCalled()
    expect(evalsRemoveRow).not.toHaveBeenCalled()
  })

  it('renders for a new row', async () => {
    const {user} = render(<RowEditDialog setShowRowDialog={setShowRowDialog} />)

    const dialog = screen.getByRole('dialog', {name: 'Add Row'})
    expect(dialog).toBeInTheDocument()
    expect(within(dialog).getByRole('textbox', {name: 'input'})).toHaveValue('')
    expect(within(dialog).getByRole('textbox', {name: 'expected'})).toHaveValue('')
    expect(within(dialog).getByRole('button', {name: 'Add'})).toBeInTheDocument()
    const cancelButton = within(dialog).getByRole('button', {name: 'Cancel'})
    expect(cancelButton).toBeInTheDocument()
    expect(within(dialog).getByRole('button', {name: 'Close'})).toBeInTheDocument()
    expect(within(dialog).queryByRole('button', {name: 'Delete row'})).not.toBeInTheDocument()
    expect(within(dialog).queryByRole('button', {name: 'Save'})).not.toBeInTheDocument()
    expect(setShowRowDialog).not.toHaveBeenCalled()

    await user.click(cancelButton)

    expect(setShowRowDialog).toHaveBeenCalledTimes(1)
    expect(setShowRowDialog).toHaveBeenCalledWith(false)
    expect(evalsAddRow).not.toHaveBeenCalled()
    expect(evalsUpdateRow).not.toHaveBeenCalled()
    expect(evalsRemoveRow).not.toHaveBeenCalled()
  })

  it('allows creating a new row', async () => {
    const {user} = render(<RowEditDialog setShowRowDialog={setShowRowDialog} />)

    const dialog = screen.getByRole('dialog', {name: 'Add Row'})
    expect(dialog).toBeInTheDocument()
    const addButton = within(dialog).getByRole('button', {name: 'Add'})
    expect(addButton).toBeInTheDocument()
    expect(addButton).toBeEnabled()

    await user.type(within(dialog).getByRole('textbox', {name: 'input'}), 'hello world')
    await user.click(addButton)

    expect(evalsUpdateRow).not.toHaveBeenCalled()
    expect(evalsAddRow).toHaveBeenCalledTimes(1)
    expect(evalsAddRow).toHaveBeenCalledWith({input: 'hello world'})
    expect(setShowRowDialog).toHaveBeenCalledTimes(1)
    expect(setShowRowDialog).toHaveBeenCalledWith(false)
    expect(evalsRemoveRow).not.toHaveBeenCalled()
  })

  it('allows editing an existing row', async () => {
    const row: EvalsRow = {input: 'Lewis Carroll', id: '123'}

    const {user} = render(<RowEditDialog setShowRowDialog={setShowRowDialog} row={row} />)

    const dialog = screen.getByRole('dialog', {name: 'Edit Row'})
    expect(dialog).toBeInTheDocument()
    const saveButton = within(dialog).getByRole('button', {name: 'Save'})
    expect(saveButton).toBeInTheDocument()
    expect(saveButton).toBeEnabled()

    await user.type(within(dialog).getByRole('textbox', {name: 'input'}), ' Jabberwocky')
    await user.click(saveButton)

    expect(evalsAddRow).not.toHaveBeenCalled()
    expect(evalsUpdateRow).toHaveBeenCalledTimes(1)
    expect(evalsUpdateRow).toHaveBeenCalledWith({input: 'Lewis Carroll Jabberwocky', id: '123'})
    expect(setShowRowDialog).toHaveBeenCalledTimes(1)
    expect(setShowRowDialog).toHaveBeenCalledWith(false)
    expect(evalsRemoveRow).not.toHaveBeenCalled()
  })

  it('allows deleting a row', async () => {
    const row: EvalsRow = {input: 'Lewis Carroll', id: '123'}

    const {user} = render(<RowEditDialog setShowRowDialog={setShowRowDialog} row={row} />)

    const dialog = screen.getByRole('dialog', {name: 'Edit Row'})
    expect(dialog).toBeInTheDocument()
    const deleteButton = within(dialog).getByRole('button', {name: 'Delete row'})
    expect(deleteButton).toBeInTheDocument()
    expect(deleteButton).toBeEnabled()

    await user.click(deleteButton)

    expect(evalsRemoveRow).toHaveBeenCalledTimes(1)
    expect(evalsRemoveRow).toHaveBeenCalledWith('123')
    expect(setShowRowDialog).toHaveBeenCalledTimes(1)
    expect(setShowRowDialog).toHaveBeenCalledWith(false)
    expect(evalsAddRow).not.toHaveBeenCalled()
    expect(evalsUpdateRow).not.toHaveBeenCalled()
  })
})

function render(component: JSX.Element) {
  const manager = {} as PromptCompareManager
  manager.evalsAddRow = evalsAddRow
  manager.evalsUpdateRow = evalsUpdateRow
  manager.evalsRemoveRow = evalsRemoveRow

  return htmlRender(
    <PromptCompareManagerContext.Provider value={manager}>{component}</PromptCompareManagerContext.Provider>,
  )
}
