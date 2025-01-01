// filepath: /workspaces/github/ui/packages/timeline-items/components/__tests__/AssignmentEventAssignee.test.tsx
import {graphql} from 'relay-runtime'
import {renderRelay} from '@github-ui/relay-test-utils'
import {screen} from '@testing-library/react'
import type {AssignmentEventAssigneeTestQuery} from './__generated__/AssignmentEventAssigneeTestQuery.graphql'
import {AssignmentEventAssignee} from '../AssignmentEventAssignee'

describe('AssignmentEventAssignee', () => {
  test('Renders regular bot assignment correctly', () => {
    setup({
      __typename: 'Bot',
      login: 'dependabot',
      resourcePath: '/dependabot',
      isCopilot: false,
    })

    // Should display the bot's login
    expect(screen.getByText('dependabot')).toBeInTheDocument()
    // Regular bots should have no hovercard attributes
    expect(screen.getByRole('link', {name: 'dependabot'})).not.toHaveAttribute('data-hovercard-url')
    expect(screen.getByRole('link', {name: 'dependabot'})).not.toHaveAttribute('data-hovercard-type')
    // Link should point to the correct path
    expect(screen.getByRole('link', {name: 'dependabot'})).toHaveAttribute('href', '/dependabot')
  })

  test('Renders Copilot assignment correctly', () => {
    setup({
      __typename: 'Bot',
      login: 'github-copilot',
      resourcePath: '/github-copilot',
      isCopilot: true,
    })

    // Should display "Copilot" instead of the actual login
    expect(screen.getByText('Copilot')).toBeInTheDocument()
    expect(screen.queryByText('github-copilot')).not.toBeInTheDocument()
    // Verify correct hovercard attributes are applied
    expect(screen.getByRole('link', {name: 'Copilot'})).toHaveAttribute(
      'data-hovercard-url',
      '/copilot/hovercard?bot=github-copilot',
    )
    expect(screen.getByRole('link', {name: 'Copilot'})).toHaveAttribute('data-hovercard-type', 'copilot')
    // Link should point to the correct path
    expect(screen.getByRole('link', {name: 'Copilot'})).toHaveAttribute('href', '/github-copilot')
  })

  test('Renders user assignment correctly', () => {
    setup({
      __typename: 'User',
      login: 'monalisa',
      resourcePath: '/monalisa',
    })

    // Should display the user's login
    expect(screen.getByText('monalisa')).toBeInTheDocument()
    // Verify correct hovercard attributes are applied
    expect(screen.getByRole('link', {name: 'monalisa'})).toHaveAttribute(
      'data-hovercard-url',
      '/users/monalisa/hovercard',
    )
    expect(screen.getByRole('link', {name: 'monalisa'})).toHaveAttribute('data-hovercard-type', 'user')
    // Link should point to the correct path
    expect(screen.getByRole('link', {name: 'monalisa'})).toHaveAttribute('href', '/monalisa')
  })

  test('Renders organization assignment correctly', () => {
    setup({
      __typename: 'Organization',
      login: 'github',
      resourcePath: '/github',
    })

    // Should display the organization's login
    expect(screen.getByText('github')).toBeInTheDocument()
    // Verify correct hovercard attributes are applied
    expect(screen.getByRole('link', {name: 'github'})).toHaveAttribute('data-hovercard-url', '/users/github/hovercard')
    expect(screen.getByRole('link', {name: 'github'})).toHaveAttribute('data-hovercard-type', 'user')
    // Link should point to the correct path
    expect(screen.getByRole('link', {name: 'github'})).toHaveAttribute('href', '/github')
  })

  test('Renders mannequin assignment correctly', () => {
    setup({
      __typename: 'Mannequin',
      login: 'ghost-user',
      resourcePath: '/ghost-user',
    })

    // Should display the mannequin's login (or mock value in test environment)
    expect(screen.getByText('ghost-user')).toBeInTheDocument()
    // Mannequins should have no hovercard attributes
    expect(screen.getByRole('link', {name: 'ghost-user'})).not.toHaveAttribute('data-hovercard-url')
    expect(screen.getByRole('link', {name: 'ghost-user'})).not.toHaveAttribute('data-hovercard-type')
    // Link should point to the correct path
    expect(screen.getByRole('link', {name: 'ghost-user'})).toHaveAttribute('href', '/ghost-user')
  })

  test('Renders with undefined assignee', () => {
    setup(null)

    // Should fallback to ghost values - use getByText instead of role
    expect(screen.getByText('ghost')).toBeInTheDocument()
    // Check that it's an anchor element
    const element = screen.getByText('ghost')
    expect(element.tagName).toBe('A')
  })

  test('Renders with unknown typename', () => {
    setup({
      __typename: '%other',
      login: 'unknown-type',
    })

    // Should render nothing for unknown types
    expect(screen.queryByText('unknown-type')).not.toBeInTheDocument()
    // Should render an empty fragment
    expect(document.body.textContent).toBe('ghost')
  })

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  function setup(assigneeData: any = {}) {
    renderRelay<{query: AssignmentEventAssigneeTestQuery}>(
      ({queryData}) => <AssignmentEventAssignee assigneeRef={queryData.query.node} />,
      {
        relay: {
          queries: {
            query: {
              type: 'fragment',
              query: graphql`
                query AssignmentEventAssigneeTestQuery @relay_test_operation {
                  node(id: "node-id") {
                    ...AssignmentEventAssignee
                  }
                }
              `,
              variables: {},
            },
          },
          mockResolvers: {
            Node() {
              return assigneeData
            },
          },
        },
      },
    )
  }
})
