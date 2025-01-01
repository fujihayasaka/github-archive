import {screen, within} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import IndexDetailsDialog from '../IndexDetailsDialog'
import {mockResizeObserver} from '../../GettingStartedDialog/__tests__/mocks'
import type {FileUpload} from '../FileList'

const onClose = jest.fn().mockName('onClose')
const onDelete = jest.fn().mockName('onDelete')

describe('IndexDetailsDialog', () => {
  beforeEach(() => {
    // Necessary to avoid a 'TypeError: observer.observe is not a function' error when all the
    // IndexDetailsDialog tests are run.
    mockResizeObserver()
  })

  afterEach(() => {
    jest.resetAllMocks()
  })

  test('renders file information and can be closed', async () => {
    const file1: FileUpload['file'] = {name: 'file1.txt', size: 1000000}
    const file2: FileUpload['file'] = {name: 'file2.txt', size: 200000}
    const files = [file1, file2]

    const {user} = render(<IndexDetailsDialog onClose={onClose} onDelete={onDelete} files={files} />)

    const dialog = screen.getByRole('dialog', {name: 'Index details'})
    expect(dialog).toBeInTheDocument()
    const fileList = within(dialog).getByRole('list', {name: 'File list'})
    expect(fileList).toBeInTheDocument()
    const listItems = within(fileList).getAllByRole('listitem')
    expect(listItems).toHaveLength(2)
    expect(listItems[0]).toHaveTextContent('file1.txt1.00 MB')
    expect(listItems[1]).toHaveTextContent('file2.txt0.20 MB')
    expect(within(dialog).getByTestId('file-bytes-used')).toHaveTextContent(/ 1\.2\/50 MB limit used/)
    const closeButton = within(dialog).getByRole('button', {name: 'Cancel'})
    expect(closeButton).toBeInTheDocument()

    await user.click(closeButton)

    expect(onClose).toHaveBeenCalledTimes(1)
  })

  test('renders when warning is not visible', async () => {
    const files: Array<FileUpload['file']> = [{name: 'file1.txt', size: 100}]

    const {user} = render(
      <IndexDetailsDialog showWarning={false} onClose={onClose} onDelete={onDelete} files={files} />,
    )

    const dialog = screen.getByRole('dialog', {name: 'Index details'})
    expect(dialog).toBeInTheDocument()
    expect(within(dialog).getByRole('list', {name: 'File list'})).toBeInTheDocument()
    expect(within(dialog).getByRole('button', {name: 'Cancel'})).toBeInTheDocument()
    const deleteButton = within(dialog).getByRole('button', {name: 'Delete index'})
    expect(deleteButton).toBeInTheDocument()
    expect(onClose).not.toHaveBeenCalled()
    expect(within(dialog).queryByRole('heading', {level: 2, name: 'Warning'})).not.toBeInTheDocument()

    await user.click(deleteButton)

    expect(onDelete).not.toHaveBeenCalled()
    expect(within(dialog).getByRole('heading', {level: 2, name: 'Warning'})).toBeInTheDocument()
  })

  test('renders when warning is visible', async () => {
    const files: Array<FileUpload['file']> = [{name: 'file1.txt', size: 100}]

    const {user} = render(<IndexDetailsDialog showWarning onClose={onClose} onDelete={onDelete} files={files} />)

    const dialog = screen.getByRole('dialog', {name: 'Index details'})
    expect(dialog).toBeInTheDocument()
    expect(within(dialog).getByRole('list', {name: 'File list'})).toBeInTheDocument()
    expect(within(dialog).getByRole('button', {name: 'Cancel'})).toBeInTheDocument()
    const deleteButton = within(dialog).getByRole('button', {name: 'Delete index'})
    expect(deleteButton).toBeInTheDocument()
    expect(onClose).not.toHaveBeenCalled()
    expect(within(dialog).getByRole('heading', {level: 2, name: 'Warning'})).toBeInTheDocument()

    await user.click(deleteButton)

    expect(onDelete).toHaveBeenCalledTimes(1)
  })

  test('does not show file list when there are no files', () => {
    render(<IndexDetailsDialog onClose={onClose} onDelete={onDelete} files={[]} />)

    const dialog = screen.getByRole('dialog', {name: 'Index details'})
    expect(dialog).toBeInTheDocument()
    expect(within(dialog).queryByTestId('file-list')).not.toBeInTheDocument()
    expect(within(dialog).getByTestId('file-bytes-used')).toHaveTextContent(/ 0\.0\/50 MB limit used/)
  })
})
