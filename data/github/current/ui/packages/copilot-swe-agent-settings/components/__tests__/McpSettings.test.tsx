import {fireEvent, render, screen} from '@testing-library/react'
import {McpSettings} from '../McpSettings'

describe('McpSettings', () => {
  test('shows an error message when args for a server is not an array of strings', async () => {
    const initialValue = JSON.stringify({mcpServers: {foo: {command: 'echo', args: 'test', tools: ['*']}}})
    render(<McpSettings endpoint="/test-org/repo/settings/copilot" initialValue={initialValue} />)
    // eslint-disable-next-line testing-library/prefer-user-event
    fireEvent.click(screen.getByRole('button', {name: 'Save'}))
    expect(
      await screen.findByText(/Schema validation failed: .*\/mcpServers\/foo\/args must be array of strings/),
    ).toBeInTheDocument()
  })

  test('shows an error message when tools are not specified for a server', async () => {
    const initialValue = JSON.stringify({mcpServers: {foo: {command: 'echo', args: ['test']}}})
    render(<McpSettings endpoint="/test-org/repo/settings/copilot" initialValue={initialValue} />)

    // eslint-disable-next-line testing-library/prefer-user-event
    fireEvent.click(screen.getByRole('button', {name: 'Save'}))

    expect(
      await screen.findByText(/Schema validation failed: \/mcpServers\/foo must have required property 'tools'/),
    ).toBeInTheDocument()
  })
})
