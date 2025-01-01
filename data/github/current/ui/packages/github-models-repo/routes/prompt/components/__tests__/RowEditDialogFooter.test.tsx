import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import type {EvalsRow} from '../../types'
import {RowEditDialogFooter} from '../RowEditDialogFooter'

const setShowRowDialog = jest.fn().mockName('setShowRowDialog')

describe('RowEditDialogFooter', () => {
  afterEach(() => {
    jest.resetAllMocks()
  })

  it('renders in edit mode', async () => {
    const row: EvalsRow = {input: 'cats', id: '123'}

    const {user} = render(<RowEditDialogFooter editMode setShowRowDialog={setShowRowDialog} row={row} />)

    expect(screen.getByRole('button', {name: 'Save'})).toBeInTheDocument()
    const cancelButton = screen.getByRole('button', {name: 'Cancel'})
    expect(cancelButton).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Delete row'})).toBeInTheDocument()
    expect(screen.queryByRole('button', {name: 'Add'})).not.toBeInTheDocument()
    expect(setShowRowDialog).not.toHaveBeenCalled()

    await user.click(cancelButton)

    expect(setShowRowDialog).toHaveBeenCalledTimes(1)
    expect(setShowRowDialog).toHaveBeenCalledWith(false)
  })

  it('renders in create mode', () => {
    const row: EvalsRow = {input: '', id: '123'}

    render(<RowEditDialogFooter editMode={false} setShowRowDialog={setShowRowDialog} row={row} />)

    expect(screen.getByRole('button', {name: 'Add'})).toBeInTheDocument()
    const cancelButton = screen.getByRole('button', {name: 'Cancel'})
    expect(cancelButton).toBeInTheDocument()
    expect(screen.queryByRole('button', {name: 'Delete row'})).not.toBeInTheDocument()
    expect(screen.queryByRole('button', {name: 'Save'})).not.toBeInTheDocument()
    expect(setShowRowDialog).not.toHaveBeenCalled()
  })
})
