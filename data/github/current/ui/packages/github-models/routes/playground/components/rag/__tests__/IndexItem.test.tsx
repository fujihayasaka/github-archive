import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import IndexItem from '../IndexItem'
import type {Index} from '../../../../../types'
import {expectAnalyticsEvents} from '@github-ui/analytics-test-utils'

const handleClick = jest.fn().mockName('handleClick')
const handleDelete = jest.fn().mockName('handleDelete')

const mockIndex: Index = {
  name: 'Test Index',
  files: [
    {name: 'file1.txt', size: 1000000},
    {name: 'file2.txt', size: 200000},
  ],
  status: 'Success',
}

describe('IndexItem', () => {
  const setDate = '2025-02-03T12:00:00Z'
  beforeAll(() => {
    jest.useFakeTimers().setSystemTime(new Date(setDate))
  })

  afterAll(() => {
    jest.useRealTimers()
  })

  it('renders the index name and file count', () => {
    render(<IndexItem index={mockIndex} onClick={handleClick} onDelete={handleDelete} />)
    expect(screen.getByText('Test Index')).toBeInTheDocument()
    expect(screen.getByText('2 files added on 2-3-2025')).toBeInTheDocument()
  })

  it('renders the correct status icon for Success status', () => {
    render(<IndexItem index={mockIndex} onClick={handleClick} onDelete={handleDelete} />)
    expect(screen.getByRole('img', {name: 'Success'})).toBeInTheDocument()
    expect(screen.queryByRole('img', {name: 'Failure'})).not.toBeInTheDocument()
    expect(screen.queryByText('Loading')).not.toBeInTheDocument()
  })

  it('renders the correct status icon for InProgress status', () => {
    const inProgressIndex: Index = {...mockIndex, status: 'InProgress'}

    render(<IndexItem index={inProgressIndex} onClick={handleClick} onDelete={handleDelete} />)
    expect(screen.getByText('Loading')).toBeInTheDocument()
    expect(screen.queryByRole('img', {name: 'Success'})).not.toBeInTheDocument()
    expect(screen.queryByRole('img', {name: 'Failure'})).not.toBeInTheDocument()
  })

  it('renders the correct status icon for TransientFailure status', () => {
    const failureIndex: Index = {...mockIndex, status: 'TransientFailure'}

    render(<IndexItem index={failureIndex} onClick={handleClick} onDelete={handleDelete} />)
    expect(screen.getByRole('img', {name: 'Failure'})).toBeInTheDocument()
    expect(screen.queryByRole('img', {name: 'Success'})).not.toBeInTheDocument()
    expect(screen.queryByText('Loading')).not.toBeInTheDocument()
  })

  it('renders the correct status icon for Reset status', () => {
    const failureIndex: Index = {...mockIndex, status: 'Reset'}

    render(<IndexItem index={failureIndex} onClick={handleClick} onDelete={handleDelete} />)
    expect(screen.getByRole('img', {name: 'Failure'})).toBeInTheDocument()
    expect(screen.queryByRole('img', {name: 'Success'})).not.toBeInTheDocument()
    expect(screen.queryByText('Loading')).not.toBeInTheDocument()
  })

  it('calls onClick when the button is clicked', async () => {
    const {user} = render(<IndexItem index={mockIndex} onClick={handleClick} onDelete={handleDelete} />)
    await user.click(screen.getByTestId('rag-index-button'))
    expect(handleClick).toHaveBeenCalledTimes(1)
  })

  it('calls onDelete when the delete button is clicked', async () => {
    const {user} = render(<IndexItem index={mockIndex} onClick={handleClick} onDelete={handleDelete} />)
    const deleteIndexButton = screen.getByTestId('delete-index')

    await user.click(deleteIndexButton)
    expect(handleDelete).toHaveBeenCalledTimes(1)
    expectAnalyticsEvents({
      type: 'analytics.click',
      data: {
        category: 'github_models_playground',
        action: 'rag_delete_index',
      },
    })
  })
})
