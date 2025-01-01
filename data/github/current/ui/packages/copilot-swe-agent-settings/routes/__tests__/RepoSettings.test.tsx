import {render} from '@github-ui/react-core/test-utils'
import {fireEvent, screen} from '@testing-library/react'
import {RepoSettings} from '../RepoSettings'

// Mock route payload
const mockPayload = {
  endpoint: 'test/url/copilot/settings',
  mcpConfiguration: '{"mcpServers": {"localtool": {"command": "echo","args": ["test"], "tools": ["tool1"]}}}',
  access_warning_banner_content: 'uh oh!',
}

// Mock route payload hook
jest.mock('@github-ui/react-core/use-route-payload', () => ({
  useRoutePayload: () => mockPayload,
}))

// Define mock mutation handler so it can be updated per test
const mockUseCopilotSweAgentSettingsMutation = jest.fn()

// Mock mutation hook
jest.mock('../../hooks/use-fetchers', () => ({
  useCopilotSweAgentSettingsMutation: () => [mockUseCopilotSweAgentSettingsMutation],
}))

describe('RepoSettings', () => {
  test('renders ProjectPadawanSettings content', async () => {
    render(<RepoSettings />)

    const heading = await screen.findByRole('heading', {level: 2, name: 'Copilot coding agent'})
    expect(heading).toBeInTheDocument()
    expect(screen.getByText(/With Copilot coding agent, developers can delegate tasks/)).toBeInTheDocument()
  })

  test('renders McpSettingsInput with correct props', async () => {
    render(<RepoSettings />)
    const editor = await screen.findByTestId('codemirror-editor')
    expect(editor).toBeInTheDocument()
    expect(screen.getByText('Copilot coding agent')).toBeInTheDocument()
    expect(screen.getByText(/Model Context Protocol/)).toBeInTheDocument()
    expect(editor.textContent).toContain('"mcpServers"')
  })

  test('shows a successful message when changes have been saved successfully', async () => {
    mockUseCopilotSweAgentSettingsMutation.mockImplementationOnce(({onComplete}) => {
      onComplete({message: 'Saved successfully'}, 200)
    })

    render(<RepoSettings />)
    // eslint-disable-next-line testing-library/prefer-user-event
    fireEvent.click(screen.getByRole('button', {name: 'Save'}))
    expect(await screen.findByText(/saved successfully/i)).toBeInTheDocument()
  })
  test('shows an error message when save fails', async () => {
    mockUseCopilotSweAgentSettingsMutation.mockImplementationOnce(({onError}) => {
      onError(new Error('Something went wrong'))
    })
    render(<RepoSettings />)
    // eslint-disable-next-line testing-library/prefer-user-event
    fireEvent.click(screen.getByRole('button', {name: 'Save'}))
    expect(await screen.findByText('Unexpected error occurred while saving.')).toBeInTheDocument()
  })

  test('renders access banner', async () => {
    render(<RepoSettings />)

    expect(screen.getByText('uh oh!')).toBeInTheDocument()
  })
})
