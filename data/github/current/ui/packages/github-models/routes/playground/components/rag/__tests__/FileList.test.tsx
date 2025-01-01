import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import type {FileListProps} from '../FileList'
import FileList from '../FileList'

describe('FileList', () => {
  const testFiles = [
    {file: {name: 'file1.txt', size: 1000000}, isUploadInProgress: false},
    {file: {name: 'file2.txt', size: 2000000}, isUploadInProgress: true},
  ]

  const renderComponent = (props: Partial<FileListProps> = {}) => {
    const defaultProps: FileListProps = {
      files: testFiles,
      disabled: false,
    }
    return render(<FileList {...defaultProps} {...props} />)
  }

  it('renders the file list', () => {
    renderComponent()
    expect(screen.getByLabelText('File list')).toBeInTheDocument()
    expect(screen.getByText('file1.txt')).toBeInTheDocument()
    expect(screen.getByText('file2.txt')).toBeInTheDocument()
  })

  it('displays the correct file size', () => {
    renderComponent()
    expect(screen.getByText('1.00 MB')).toBeInTheDocument()
    expect(screen.getByText('2.00 MB')).toBeInTheDocument()
  })

  it('shows a spinner when upload is in progress', () => {
    const files = [{file: {name: 'file1.txt', size: 1000000}, isUploadInProgress: true}]
    renderComponent({files})
    expect(screen.getByText('Loading')).toBeInTheDocument()
  })

  it('shows a file icon when upload is not in progress', () => {
    const files = [{file: {name: 'file1.txt', size: 1000000}, isUploadInProgress: false}]
    renderComponent({files})
    expect(screen.getByRole('img', {name: 'Uploaded file'})).toBeInTheDocument()
  })

  it('shows both spinner and file icon when one upload is in progress and another is not', () => {
    renderComponent()
    expect(screen.getByText('Loading')).toBeInTheDocument()
    expect(screen.getByRole('img', {name: 'Uploaded file'})).toBeInTheDocument()
  })

  it('does not render trash icon when onFileDeleted not provided', async () => {
    renderComponent()
    expect(screen.queryAllByRole('button', {name: 'Remove file'})).toHaveLength(0)
  })

  it('calls onFileDeleted when delete button is clicked', async () => {
    const onFileDeleted = jest.fn()
    const {user} = renderComponent({onFileDeleted})
    const deleteButtons = screen.getAllByRole('button', {name: 'Remove file'})
    const firstDeleteButton = deleteButtons[0] as HTMLButtonElement
    await user.click(firstDeleteButton)
    expect(onFileDeleted).toHaveBeenCalledWith(0)
  })

  it('correctly deletes index when delete button is clicked', async () => {
    const files = [
      {file: {name: 'file1.txt', size: 1000000}, isUploadInProgress: false},
      {file: {name: 'file2.txt', size: 2000000}, isUploadInProgress: false},
    ]
    const onFileDeleted = jest.fn()
    const {user} = renderComponent({onFileDeleted, files})
    const deleteButtons = screen.getAllByLabelText('Remove file')
    const secondDeleteButton = deleteButtons[1] as HTMLButtonElement
    await user.click(secondDeleteButton)
    expect(onFileDeleted).toHaveBeenCalledWith(1)
  })

  it('manages index when delete button is clicked', async () => {
    const files = [
      {file: {name: 'file1.txt', size: 1000000}, isUploadInProgress: false},
      {file: {name: 'file2.txt', size: 2000000}, isUploadInProgress: false},
      {file: {name: 'file3.txt', size: 3000000}, isUploadInProgress: false},
    ]
    const onFileDeleted = jest.fn()
    const {user} = renderComponent({onFileDeleted, files})
    const deleteButtons = screen.getAllByLabelText('Remove file')
    const secondDeleteButton = deleteButtons[1] as HTMLButtonElement
    const thirdDeleteButton = deleteButtons[2] as HTMLButtonElement
    await user.click(secondDeleteButton)
    expect(onFileDeleted).toHaveBeenCalledWith(1)
    await user.click(thirdDeleteButton)
    expect(onFileDeleted).toHaveBeenCalledWith(2)
  })

  it('disables delete button when upload is in progress or disabled', () => {
    const onFileDeleted = jest.fn()
    renderComponent({onFileDeleted, disabled: true})
    const deleteButtons = screen.getAllByLabelText('Remove file')
    expect(deleteButtons[0]).toBeDisabled()
    expect(deleteButtons[1]).toBeDisabled()
  })
})
