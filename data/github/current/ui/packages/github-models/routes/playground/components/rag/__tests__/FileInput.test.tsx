import {fireEvent, screen} from '@testing-library/react'
import type {FileInputProps} from '../FileInput'
import FileInput, {allowedFileTypes} from '../FileInput'
import {setupUserEvent, render} from '@github-ui/react-core/test-utils'

describe('FileInput', () => {
  const mockOnFilesSelected = jest.fn()

  const renderComponent = (props: Partial<FileInputProps> = {}) => {
    return render(<FileInput onFilesSelected={mockOnFilesSelected} {...props} />)
  }

  afterEach(() => {
    jest.clearAllMocks()
  })

  it('renders correctly with default props', () => {
    renderComponent()
    expect(screen.getByText(/Drag and drop files here/i)).toBeInTheDocument()
    expect(screen.getByLabelText('choose files')).toBeInTheDocument()
  })

  it('renders correctly with condensed prop', () => {
    renderComponent({condensed: true})
    expect(screen.getByText(/Drag and drop files here/i)).toBeInTheDocument()
    expect(screen.getByLabelText('choose files')).toBeInTheDocument()
  })

  it('calls onFilesSelected when files are selected via input', async () => {
    renderComponent()
    const fileInput = screen.getByLabelText('choose files')
    const files = [new File(['file content'], 'file.txt', {type: 'text/plain'})]
    const userEvent = setupUserEvent()
    await userEvent.upload(fileInput, files)

    expect(mockOnFilesSelected).toHaveBeenCalledWith(expect.any(FileList))
    expect(mockOnFilesSelected.mock.calls[0][0][0]).toEqual(files[0])
  })

  it('calls onFilesSelected when files are dropped', () => {
    renderComponent()
    const dropZone = screen.getByText(/Drag and drop files here/i)
    const files = [new File(['file content'], 'file.txt', {type: 'text/plain'})]

    fireEvent.drop(dropZone, {
      dataTransfer: {files},
    })

    expect(mockOnFilesSelected).toHaveBeenCalledWith(files)
    expect(mockOnFilesSelected.mock.calls[0][0][0]).toEqual(files[0])
  })

  it('accepts only allowed file types', () => {
    renderComponent()
    const fileInput = screen.getByLabelText('choose files')

    expect(fileInput).toHaveAttribute('accept', allowedFileTypes.join(','))
  })
})
