import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'

import {FilteredContentModal} from '../FilteredContentModal'

describe('FilteredContentModal', () => {
  it('renders the modal with content when no categories are provided', () => {
    const onClose = jest.fn()
    const content = 'Your content has been filtered.\nWith multiple lines.'

    render(<FilteredContentModal content={content} onClose={onClose} />)

    // Verify content is displayed and respects newlines
    expect(screen.getByText(/Your content has been filtered\./)).toBeInTheDocument()
    expect(screen.getByText(/With multiple lines\./)).toBeInTheDocument()
  })

  it('calls onClose when the modal is closed', async () => {
    const onClose = jest.fn()
    const content = 'This is a filtered content explanation.'

    const {user} = render(<FilteredContentModal content={content} onClose={onClose} />)

    // Close the modal
    const closeButton = screen.getByRole('button', {name: /close/i})
    await user.click(closeButton)

    // Verify onClose is called
    expect(onClose).toHaveBeenCalledTimes(1)
  })

  it('renders filtered categories when provided', () => {
    const onClose = jest.fn()
    const filteredCategories = [
      {category: 'harmful_content', severity: 'high'},
      {category: 'hate_speech', severity: 'medium'},
    ]

    render(<FilteredContentModal content={null} filteredCategories={filteredCategories} onClose={onClose} />)

    // Verify each category is displayed
    expect(screen.getByText('harmful_content')).toBeInTheDocument()
    expect(screen.getByText('hate_speech')).toBeInTheDocument()
  })

  it('prioritizes filtered categories over content when both are provided', () => {
    const onClose = jest.fn()
    const content = 'This content should not be displayed.'
    const filteredCategories = [{category: 'harmful_content', severity: 'high'}]

    render(<FilteredContentModal content={content} filteredCategories={filteredCategories} onClose={onClose} />)

    // Verify the filtered categories are displayed
    expect(screen.getByText('harmful_content')).toBeInTheDocument()

    // Verify the content is not displayed
    expect(screen.queryByText('This content should not be displayed.')).not.toBeInTheDocument()
  })
})
