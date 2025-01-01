import {renderWithClient} from '@github-ui/pull-request-page-data-tooling/render-with-query-client'
import {fireEvent, screen} from '@testing-library/react'
import {ConversationHeader} from '../ConversationHeader'

describe('ConversationHeader', () => {
  beforeEach(() => {
    localStorage.clear()
  })

  test('calls `onNavigateToDiffComment` onClick', async () => {
    const mockOnNavigateToDiffComment = jest.fn(() => {})

    const {user} = renderWithClient(
      <ConversationHeader
        isCollapsed={false}
        isOutdated={false}
        isResolved={false}
        line={42}
        onNavigateToDiffComment={mockOnNavigateToDiffComment}
        onToggleCollapsed={jest.fn()}
        path="src/components/Example.tsx"
        threadId="12345"
      />,
    )

    const button = screen.getByLabelText('Jump to the comment in the diff')
    await user.click(button)

    expect(mockOnNavigateToDiffComment).toHaveBeenCalled()
  })

  test('toggles the review comment to collapsed state and updates localStorage', () => {
    const mockOnToggleCollapsed = jest.fn()

    renderWithClient(
      <ConversationHeader
        isCollapsed={false}
        isOutdated={false}
        isResolved={false}
        path="src/components/Example.tsx"
        onToggleCollapsed={mockOnToggleCollapsed}
        onNavigateToDiffComment={jest.fn()}
        threadId="12345"
      />,
    )

    const button = screen.getByRole('button', {name: /close review comment/i})
    expect(button).toBeInTheDocument()

    // eslint-disable-next-line testing-library/prefer-user-event
    fireEvent.click(button)

    expect(localStorage.getItem(`reviewThreadIsCollapsed_12345`)).toBe('true')
    const updatedButton = screen.getByRole('button', {name: /open review comment/i})
    expect(updatedButton).toBeInTheDocument()
  })

  test('toggles the review comment to expanded state and updates localStorage', () => {
    const mockOnToggleCollapsed = jest.fn()

    renderWithClient(
      <ConversationHeader
        isCollapsed
        isOutdated={false}
        isResolved={false}
        path="src/components/Example.tsx"
        onToggleCollapsed={mockOnToggleCollapsed}
        onNavigateToDiffComment={jest.fn()}
        threadId="12345"
      />,
    )

    const button = screen.getByRole('button', {name: /open review comment/i})
    expect(button).toBeInTheDocument()

    // eslint-disable-next-line testing-library/prefer-user-event
    fireEvent.click(button)

    expect(localStorage.getItem(`reviewThreadIsCollapsed_12345`)).toBe('false')
    const updatedButton = screen.getByRole('button', {name: /close review comment/i})
    expect(updatedButton).toBeInTheDocument()
  })
})
