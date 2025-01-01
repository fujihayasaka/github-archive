import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import {ComparePromptActions} from '../ComparePromptActions'
import {mockPromptConfig} from '../../../../test-utils/mock-data'

const handleEdit = jest.fn().mockName('handleEdit')
const handleRemove = jest.fn().mockName('handleRemove')

describe('ComparePromptActions', () => {
  afterEach(() => {
    jest.clearAllMocks()
  })

  it('renders edit and remove buttons when not in review view, prompt is not the first, and canEdit is true', () => {
    render(
      <ComparePromptActions
        prompt={mockPromptConfig()}
        promptIndex={1}
        reviewView={false}
        handleEdit={handleEdit}
        handleRemove={handleRemove}
        canEdit
      />,
    )

    const editButton = screen.getByRole('button', {name: 'Edit prompt'})
    const removeButton = screen.getByRole('button', {name: 'Remove prompt'})

    expect(editButton).toBeInTheDocument()
    expect(removeButton).toBeInTheDocument()
  })

  it('renders no buttons when in review view and prompt is the first and canEdit is false', () => {
    render(
      <ComparePromptActions
        prompt={mockPromptConfig()}
        promptIndex={0}
        reviewView
        handleEdit={handleEdit}
        handleRemove={handleRemove}
        canEdit={false}
      />,
    )

    const editButton = screen.queryByRole('button', {name: 'Edit prompt'})
    const removeButton = screen.queryByRole('button', {name: 'Remove prompt'})

    expect(editButton).not.toBeInTheDocument()
    expect(removeButton).not.toBeInTheDocument()
  })

  it('renders only edit button when in review view, prompt is not the first, and canEdit is true', () => {
    render(
      <ComparePromptActions
        prompt={mockPromptConfig()}
        promptIndex={1}
        reviewView
        handleEdit={handleEdit}
        handleRemove={handleRemove}
        canEdit
      />,
    )

    const editButton = screen.getByRole('button', {name: 'Edit prompt'})
    const removeButton = screen.queryByRole('button', {name: 'Remove prompt'})

    expect(editButton).toBeInTheDocument()
    expect(removeButton).not.toBeInTheDocument()
  })

  it('renders both buttons when in review view, prompt is not the first or second, and canEdit is true', () => {
    render(
      <ComparePromptActions
        prompt={mockPromptConfig()}
        promptIndex={2}
        reviewView
        handleEdit={handleEdit}
        handleRemove={handleRemove}
        canEdit
      />,
    )

    const editButton = screen.getByRole('button', {name: 'Edit prompt'})
    const removeButton = screen.getByRole('button', {name: 'Remove prompt'})

    expect(editButton).toBeInTheDocument()
    expect(removeButton).toBeInTheDocument()
  })

  it('renders only edit button when not in review view, prompt is the first, and canEdit is true', () => {
    render(
      <ComparePromptActions
        prompt={mockPromptConfig()}
        promptIndex={0}
        reviewView={false}
        handleEdit={handleEdit}
        handleRemove={handleRemove}
        canEdit
      />,
    )

    const editButton = screen.getByRole('button', {name: 'Edit prompt'})
    const removeButton = screen.queryByRole('button', {name: 'Remove prompt'})

    expect(editButton).toBeInTheDocument()
    expect(removeButton).not.toBeInTheDocument()
  })

  it('calls handleEdit when edit button is clicked', async () => {
    const promptConfig = mockPromptConfig()
    const {user} = render(
      <ComparePromptActions
        prompt={promptConfig}
        promptIndex={1}
        reviewView={false}
        handleEdit={handleEdit}
        handleRemove={handleRemove}
        canEdit
      />,
    )

    const editButton = screen.getByRole('button', {name: 'Edit prompt'})
    await user.click(editButton)
    expect(handleEdit).toHaveBeenCalledWith(promptConfig, 1)
  })

  it('calls handleRemove when remove button is clicked', async () => {
    const {user} = render(
      <ComparePromptActions
        prompt={mockPromptConfig()}
        promptIndex={1}
        reviewView={false}
        handleEdit={handleEdit}
        handleRemove={handleRemove}
      />,
    )

    const removeButton = screen.getByRole('button', {name: 'Remove prompt'})
    expect(removeButton).toBeInTheDocument()
    await user.click(removeButton)
    expect(handleRemove).toHaveBeenCalledWith(1)
  })
})
