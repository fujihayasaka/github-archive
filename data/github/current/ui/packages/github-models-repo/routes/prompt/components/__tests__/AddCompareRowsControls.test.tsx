import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import {mockResizeObserver} from '../../../../test-utils/mock-data'
import {AddCompareRowsControls} from '../AddCompareRowsControls'

const onAddRow = jest.fn().mockName('onAddRow')
const onImportRows = jest.fn().mockName('onImportRows')

describe('AddCompareRowsControls', () => {
  beforeEach(() => {
    // Necessary to avoid a 'TypeError: observer.observe is not a function' error when all tests are run.
    mockResizeObserver()
  })

  afterEach(() => {
    jest.resetAllMocks()
  })

  it('renders the Add inputs button when rows can be added', async () => {
    const {user} = render(<AddCompareRowsControls totalRows={0} onAddRow={onAddRow} onImportRows={onImportRows} />)

    const button = screen.getByRole('button', {name: 'Add input'})
    expect(button).toBeInTheDocument()

    await user.click(button)

    expect(onImportRows).not.toHaveBeenCalled()
    expect(onAddRow).toHaveBeenCalledTimes(1)
  })

  it('renders the disabled Add inputs button when at row limit', async () => {
    const {user} = render(<AddCompareRowsControls totalRows={100} onAddRow={onAddRow} onImportRows={onImportRows} />)

    const button = screen.getByRole('button', {name: 'Add input'})
    expect(button).toBeInTheDocument()
    expect(button).toHaveAttribute('disabled')

    await user.click(button)

    expect(onAddRow).not.toHaveBeenCalled()
    expect(onImportRows).not.toHaveBeenCalled()
  })

  it('calls given onImportRows when import option is selected', async () => {
    const {user} = render(<AddCompareRowsControls totalRows={0} onAddRow={onAddRow} onImportRows={onImportRows} />)

    await user.click(screen.getByRole('button', {name: 'Import data'}))

    expect(onImportRows).toHaveBeenCalledTimes(1)
    expect(onAddRow).not.toHaveBeenCalled()
  })
})
