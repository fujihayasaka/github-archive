import {screen} from '@testing-library/react'
import {render, setupUserEvent} from '@github-ui/react-core/test-utils'
import {expectAnalyticsEvents} from '@github-ui/analytics-test-utils'
import CreateIndexDialog from '../CreateIndexDialog'
import {useRAGContext} from '../../../contexts/RAGContext'
import {createUploadSession} from '../../../../../utils/rag-index-manager'

jest.mock('../../../../../utils/rag-index-manager')
jest.mock('../../../contexts/RAGContext')
const mockUseRAGContext = jest.mocked(useRAGContext)
const mockCreateUploadSession = jest.mocked(createUploadSession)

describe('CreateIndexDialog', () => {
  const mockOnClose = jest.fn().mockName('setIndex')
  const mockSetIndex = jest.fn()
  const mockPollUntilCompleted = jest.fn()

  const renderComponent = () => {
    return render(<CreateIndexDialog onClose={mockOnClose} />)
  }

  beforeEach(() => {
    jest.clearAllMocks()
    mockUseRAGContext.mockReturnValue({
      setIndex: mockSetIndex,
      pollUntilCompleted: mockPollUntilCompleted,
      index: null,
      isFetchingIndex: false,
    })
    mockCreateUploadSession.mockReturnValue(new Promise(resolve => resolve('uploadSessionId')))
  })

  it('renders correctly', () => {
    renderComponent()
    expect(screen.getByText('Create index')).toBeInTheDocument()
    expect(
      screen.getByText(
        'Select the files you would like to upload. Models in the playground will use these files as grounding context to generate an answer.',
      ),
    ).toBeInTheDocument()
  })

  it('adds files to the upload list', async () => {
    renderComponent()
    const fileInput = screen.getByLabelText('choose files')
    const files = [new File(['file content'], 'file.txt', {type: 'text/plain'})]

    const userEvent = setupUserEvent()
    await userEvent.upload(fileInput, files)

    const fileListItem = await screen.findByText('file.txt')
    expect(fileListItem).toBeInTheDocument()
  })

  it('removes file from the upload list', async () => {
    renderComponent()
    const fileInput = screen.getByLabelText('choose files')
    const files = [new File(['file content'], 'file.txt', {type: 'text/plain'})]

    const userEvent = setupUserEvent()
    await userEvent.upload(fileInput, files)

    const fileListItem = await screen.findByText('file.txt')
    expect(fileListItem).toBeInTheDocument()

    const deleteButton = screen.getByRole('button', {name: 'Remove file'})
    await userEvent.click(deleteButton)

    expect(fileListItem).not.toBeInTheDocument()
  })

  it('updates the total max space size when files are added and deleted', async () => {
    renderComponent()
    const fileInput = screen.getByLabelText('choose files')
    const file = new File(['file content'], 'file.txt', {type: 'text/plain'})
    Object.defineProperty(file, 'size', {value: 1024 * 1024 + 1})
    const files = [file]

    const userEvent = setupUserEvent()
    await userEvent.upload(fileInput, files)
    expect(screen.getByText('(1 file, 1.0/50 MB limit used)')).toBeInTheDocument()

    const file2 = new File(['file content'], 'file2.txt', {type: 'text/plain'})
    Object.defineProperty(file2, 'size', {value: 1024 * 1024 + 1})
    await userEvent.upload(fileInput, [file2])
    expect(screen.getByText('(2 files, 2.1/50 MB limit used)')).toBeInTheDocument()

    const deleteButton = screen.getAllByLabelText('Remove file')
    await userEvent.click(deleteButton[0] as HTMLButtonElement)
    expect(screen.getByText('(1 file, 1.0/50 MB limit used)')).toBeInTheDocument()
  })

  it('creates an index on save', async () => {
    renderComponent()
    const fileInput = screen.getByLabelText('choose files')
    const file = new File(['file content'], 'file.txt', {type: 'text/plain'})
    Object.defineProperty(file, 'size', {value: 1024 * 1024 + 1})
    const files = [file]

    const userEvent = setupUserEvent()
    await userEvent.upload(fileInput, files)

    const uploadButton = screen.getByRole('button', {name: 'Upload and create index'})
    await userEvent.click(uploadButton)

    expect(mockSetIndex).toHaveBeenCalledWith({
      name: 'default-vector-index',
      status: 'InProgress',
      files: [{name: 'file.txt', size: 1024 * 1024 + 1}],
    })
    expect(mockPollUntilCompleted).toHaveBeenCalled()
    expect(mockOnClose).toHaveBeenCalled()
    expectAnalyticsEvents({
      type: 'analytics.click',
      data: {
        category: 'github_models_playground',
        action: 'rag_create_index',
        fileCount: '1',
        fileSize: JSON.stringify(1024 * 1024 + 1),
        fileTypes: 'txt',
      },
    })
  })

  it('disables the upload button when no files are selected', () => {
    renderComponent()
    const uploadButton = screen.getByRole('button', {name: 'Upload and create index'})
    expect(uploadButton).toBeDisabled()
  })

  it('the upload button is in loading state while uploading', async () => {
    renderComponent()

    const fileInput = screen.getByLabelText('choose files')
    const files = [new File(['file content'], 'file.txt', {type: 'text/plain'})]

    const userEvent = setupUserEvent()
    await userEvent.upload(fileInput, files)

    const uploadButton = screen.getByRole('button', {name: 'Upload and create index'})
    await userEvent.click(uploadButton)

    expect(uploadButton).toHaveAttribute('aria-describedby', expect.stringMatching(/.*-loading-announcement$/))
  })
})
