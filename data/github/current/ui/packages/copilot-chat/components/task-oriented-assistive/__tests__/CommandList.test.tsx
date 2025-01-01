import {render, screen} from '@testing-library/react'

import {CommandList} from '../CommandList'
import type {Command} from '../commands'

const commands: Array<Command & {selected: boolean}> = [
  {
    type: 'task',
    context: 'pull-request',
    name: 'Command 1',
    prompt: 'The prompt for command 1',
    iconName: 'GitPullRequestIcon',
    selected: false,
  },
  {
    type: 'task',
    context: 'repository',
    name: 'Command 2',
    prompt: 'The prompt for command 2',
    iconName: 'RepoIcon',
    selected: true,
  },
  {
    type: 'task',
    context: 'global',
    name: 'Command 3',
    prompt: 'The prompt for command 3',
    iconName: 'GlobeIcon',
    selected: false,
  },
]

describe('CommandList', () => {
  it('renders the heading text', () => {
    render(<CommandList headingText="Test Heading" commands={commands} onSelect={() => {}} />)
    expect(screen.getByText('Test Heading')).toBeInTheDocument()
  })

  it('renders all commands', () => {
    render(<CommandList headingText="Test Heading" commands={commands} onSelect={() => {}} />)
    for (const command of commands) {
      expect(screen.getByText(command.name)).toBeInTheDocument()
    }
  })

  it('calls onSelect when a command is clicked', () => {
    const onSelect = jest.fn()
    render(<CommandList headingText="Test Heading" commands={commands} onSelect={onSelect} />)

    screen.getByText('Command 1')?.click()
    expect(onSelect).toHaveBeenCalledWith(commands[0])
  })

  it('displays "Ask Copilot" for selected command', () => {
    render(<CommandList headingText="Test Heading" commands={commands} onSelect={() => {}} />)

    const selected = screen.getAllByRole('listitem').find(item => item.textContent?.match(/Command 2/))
    expect(selected).toHaveTextContent('Ask Copilot')
  })
})
