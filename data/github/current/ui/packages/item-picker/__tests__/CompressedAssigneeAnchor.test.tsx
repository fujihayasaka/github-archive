import {render, screen} from '@testing-library/react'
import {LABELS} from '../constants/labels'
import {CompressedAssigneeAnchor, type AssigneeObject} from '../components/CompressedAssigneeAnchor'

describe('CompressedAssigneeAnchor', () => {
  const mockAssignees = [
    {
      login: 'user1',
      avatarUrl: 'https://example.com/avatar1.png',
      isCopilot: false,
    },
    {
      login: 'user2',
      avatarUrl: 'https://example.com/avatar2.png',
      isCopilot: false,
    },
    {
      login: 'copilot',
      avatarUrl: 'https://example.com/copilot.png',
      isCopilot: true,
    },
  ] as AssigneeObject[]

  it('renders with no assignees', () => {
    render(<CompressedAssigneeAnchor assignees={[]} displayHotkey={false} />)

    expect(screen.getByText(LABELS.noAssignees)).toBeInTheDocument()
    expect(screen.queryByTestId('github-avatar')).not.toBeInTheDocument()
  })

  it('renders with single assignee', () => {
    render(<CompressedAssigneeAnchor assignees={[mockAssignees[0]!]} displayHotkey={false} />)

    expect(screen.getByText(mockAssignees[0]!.login)).toBeInTheDocument()
    expect(screen.getByTestId('github-avatar')).toHaveAttribute('alt', `@${mockAssignees[0]!.login}`)
  })

  it('renders with multiple assignees', () => {
    render(<CompressedAssigneeAnchor assignees={mockAssignees.slice(0, 2)} displayHotkey={false} />)

    expect(screen.getByText(LABELS.assignees)).toBeInTheDocument()
    expect(screen.getAllByTestId('github-avatar').length).toBe(2)
  })

  it('truncates assignees when more than MAX_DISPLAYED_ASSIGNEES', () => {
    render(<CompressedAssigneeAnchor assignees={mockAssignees} displayHotkey={false} MAX_DISPLAYED_ASSIGNEES={1} />)

    expect(screen.getByText(LABELS.assignees)).toBeInTheDocument()
    expect(screen.getAllByTestId('github-avatar').length).toBe(1)
    expect(screen.getByText('user1, 2+')).toBeInTheDocument()
  })

  it('displays Copilot icon for copilot assignees', () => {
    const copilotOnly = [mockAssignees[2]!]
    render(<CompressedAssigneeAnchor assignees={copilotOnly} displayHotkey={false} />)

    // CopilotIcon should be rendered instead of GitHubAvatar
    expect(screen.queryByTestId('github-avatar')).not.toBeInTheDocument()
    // Testing for the presence of CopilotIcon is harder in a unit test, so we check the text output
    expect(screen.getByText('Copilot')).toBeInTheDocument()
  })
})
