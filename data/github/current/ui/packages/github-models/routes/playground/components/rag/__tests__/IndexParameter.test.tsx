import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import IndexParameter from '../IndexParameter'
import {useRAGContext} from '../../../contexts/RAGContext'
import type {Index} from '../../../../../types'

jest.mock('../../../contexts/RAGContext')
const mockUseRAGContext = jest.mocked(useRAGContext)

describe('IndexParameter', () => {
  const mockOnChange = jest.fn()
  const mockSetIndex = jest.fn()

  const renderComponent = (index: Index | null = null, isFetchingIndex = false, value = false) => {
    mockUseRAGContext.mockReturnValue({
      index,
      setIndex: mockSetIndex,
      isFetchingIndex,
      pollUntilCompleted: jest.fn(),
    })

    return render(<IndexParameter value={value} onChange={mockOnChange} />)
  }

  afterEach(() => {
    jest.clearAllMocks()
  })

  it('renders the component with no index', () => {
    renderComponent()
    expect(screen.getByText('Upload files to create index')).toBeInTheDocument()
    expect(screen.queryByText('Test Index')).not.toBeInTheDocument()
    expect(screen.getByLabelText('Use index for model context')).toBeDisabled()
  })

  it('has disabled checkbox when index status is not Success', () => {
    const index = {name: 'Test Index', status: 'TransientFailure', files: []} as Index
    renderComponent(index)
    expect(screen.getByLabelText('Use index for model context')).toBeDisabled()
  })

  it('renders the component with an index', () => {
    const index = {name: 'Test Index', status: 'Success', files: []} as Index
    renderComponent(index)
    expect(screen.getByText('Grounding data')).toBeInTheDocument()
    expect(screen.getByText('Use index for model context')).toBeInTheDocument()
    expect(screen.getByText('Test Index')).toBeInTheDocument()
  })

  it('renders component with Spinner if fetching index', () => {
    renderComponent(null, true)
    const uploadFilesButton = screen.getByTestId('upload-files-to-create-index')
    expect(screen.getByText('Loading')).toBeInTheDocument()
    expect(uploadFilesButton).toBeDisabled()
  })

  it('renders checkbox as checked when value is true', () => {
    const index = {name: 'Test Index', status: 'Success', files: []} as Index
    renderComponent(index, false, true)
    expect(screen.getByRole('checkbox')).toBeChecked()
  })

  it('calls onChange when checkbox is clicked', async () => {
    const index = {name: 'Test Index', status: 'Success', files: []} as Index
    const {user} = renderComponent(index, false, true)
    await user.click(screen.getByRole('checkbox'))
    expect(mockOnChange).toHaveBeenCalledWith(false)
  })
})
