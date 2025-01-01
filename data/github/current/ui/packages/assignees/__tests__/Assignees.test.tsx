import {render, screen} from '@testing-library/react'
import {Assignees} from '../Assignees'
import {mockClientEnv} from '@github-ui/client-env/mock'
import type {AssigneePickerAssignee$data} from '@github-ui/item-picker/AssigneePicker.graphql'

describe('Assignees', () => {
  const createAssignee = (login: string, name?: string): AssigneePickerAssignee$data => ({
    login,
    name: name || login,
    id: `${login}-id`,
    avatarUrl: `https://github.com/${login}.png`,
    profileResourcePath: `/${login}`,
    __typename: 'User',
    ' $fragmentType': 'AssigneePickerAssignee',
  })

  test('renders a regular user assignee with correct attributes', async () => {
    const assignee = createAssignee('monalisa', 'Mona Lisa')
    render(<Assignees assignees={[assignee]} />)

    expect(screen.getByText('monalisa')).toBeInTheDocument()

    const listItem = screen.getByRole('link')
    expect(listItem).toHaveAttribute('href', '/monalisa')
    expect(listItem).toHaveAttribute('target', '_blank')
    expect(listItem).toHaveAttribute('data-hovercard-url', '/users/monalisa/hovercard')
    expect(listItem).toHaveAttribute('data-hovercard-type', 'user')
  })

  test('renders Copilot assignee with correct display name and attributes', async () => {
    mockClientEnv({
      featureFlags: ['use_copilot_avatar'],
    })
    const assignee = {
      ...createAssignee('copilot-swe-agent'),
      profileResourcePath: '/apps/copilot-swe-agent',
      isCopilot: true,
    }
    render(<Assignees assignees={[assignee]} />)

    expect(screen.getByTestId('copilot-avatar')).toBeInTheDocument()
    expect(screen.getByText('Copilot')).toBeInTheDocument()

    const listItem = screen.getByRole('link')
    expect(listItem).toHaveAttribute('href', '/apps/copilot-swe-agent')
    expect(listItem).toHaveAttribute('target', '_blank')
    expect(listItem).toHaveAttribute('data-hovercard-url', '/copilot/hovercard?bot=copilot-swe-agent')
    expect(listItem).toHaveAttribute('data-hovercard-type', 'copilot')
  })

  test('sorts assignees alphabetically by login', async () => {
    const assignees = [createAssignee('zebra'), createAssignee('apple'), createAssignee('banana')]

    render(<Assignees assignees={assignees} />)

    const items = screen.getAllByRole('listitem')
    expect(items).toHaveLength(3)
    expect(items[0]).toHaveTextContent('apple')
    expect(items[1]).toHaveTextContent('banana')
    expect(items[2]).toHaveTextContent('zebra')
  })

  test('renders with a custom testId when provided', async () => {
    const assignee = createAssignee('monalisa')
    render(<Assignees assignees={[assignee]} testId="custom-test-id" />)

    expect(screen.getByTestId('custom-test-id')).toHaveTextContent('monalisa')
  })
})
