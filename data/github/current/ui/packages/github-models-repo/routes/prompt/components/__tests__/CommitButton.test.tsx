import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import {CommitButton} from '../CommitButton'
import {mockPromptConfig} from '../../../../test-utils/mock-data'

const mockSetDialogState = jest.fn().mockName('setDialogState')

describe('CommitButton', () => {
  afterEach(() => {
    jest.clearAllMocks()
  })

  it('renders an active button when user can edit, there are changes, there is a prompt, and the prompt has a file name', async () => {
    const promptConfig = mockPromptConfig()

    const {user} = render(
      <CommitButton canEdit isDirty promptConfig={promptConfig} setDialogState={mockSetDialogState} />,
    )

    const button = screen.getByRole('button', {name: 'Commit changes'})
    expect(button).toBeInTheDocument()
    expect(screen.queryByRole('tooltip')).not.toBeInTheDocument()
    expect(button).not.toHaveAttribute('data-inactive')

    await user.click(button)

    expect(mockSetDialogState).toHaveBeenCalledTimes(1)
    expect(mockSetDialogState).toHaveBeenCalledWith('pending')
  })

  it('renders nothing when user cannot edit', () => {
    const promptConfig = mockPromptConfig()
    render(<CommitButton setDialogState={mockSetDialogState} canEdit={false} isDirty promptConfig={promptConfig} />)
    expect(screen.queryByRole('button', {name: 'Commit changes'})).not.toBeInTheDocument()
  })

  it('renders an inactive button with tooltip when there are no changes', async () => {
    const promptConfig = mockPromptConfig()

    const {user} = render(
      <CommitButton setDialogState={mockSetDialogState} canEdit isDirty={false} promptConfig={promptConfig} />,
    )

    const button = screen.getByRole('button', {name: 'Commit changes'})
    expect(button).toBeInTheDocument()
    expect(button).toHaveAttribute('data-inactive')
    expect(screen.getByRole('tooltip', {hidden: true})).toHaveTextContent('No changes to commit')

    await user.click(button)

    expect(mockSetDialogState).not.toHaveBeenCalled()
  })

  it('renders an inactive button with tooltip when there is no prompt', async () => {
    const {user} = render(<CommitButton promptConfig={undefined} setDialogState={mockSetDialogState} canEdit isDirty />)

    const button = screen.getByRole('button', {name: 'Commit changes'})
    expect(button).toBeInTheDocument()
    expect(button).toHaveAttribute('data-inactive')
    expect(screen.getByRole('tooltip', {hidden: true})).toHaveTextContent('No prompt loaded')

    await user.click(button)

    expect(mockSetDialogState).not.toHaveBeenCalled()
  })

  it('renders an inactive button with tooltip when the prompt has no file name', async () => {
    const promptConfig = mockPromptConfig({path: ''})

    const {user} = render(
      <CommitButton setDialogState={mockSetDialogState} canEdit isDirty promptConfig={promptConfig} />,
    )

    const button = screen.getByRole('button', {name: 'Commit changes'})
    expect(button).toBeInTheDocument()
    expect(button).toHaveAttribute('data-inactive')
    expect(screen.getByRole('tooltip', {hidden: true})).toHaveTextContent('Add file name to commit')

    await user.click(button)

    expect(mockSetDialogState).not.toHaveBeenCalled()
  })

  it('renders an inactive button with tooltip when no setDialogState handler is given', async () => {
    const promptConfig = mockPromptConfig()

    const {user} = render(<CommitButton canEdit isDirty promptConfig={promptConfig} />)

    const button = screen.getByRole('button', {name: 'Commit changes'})
    expect(button).toBeInTheDocument()
    expect(button).toHaveAttribute('data-inactive')
    expect(screen.getByRole('tooltip', {hidden: true})).toHaveTextContent('You cannot commit at this time')

    await user.click(button)

    expect(mockSetDialogState).not.toHaveBeenCalled()
  })
})
