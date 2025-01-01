import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {reactFetchJSON} from '@github-ui/verified-fetch'
import {CopilotSweAgentReposPicker} from '../CopilotSweAgentReposPicker'
import {getCopilotSweAgentReposPickerProps} from '../test-utils/mock-data'

const mockReactFetchJSON = reactFetchJSON as jest.Mock
// eslint-disable-next-line no-restricted-syntax
jest.mock('@github-ui/verified-fetch', () => ({
  reactFetchJSON: jest.fn(),
}))

test('renders the repos picker with three modes', async () => {
  const props = getCopilotSweAgentReposPickerProps()
  const {user} = render(<CopilotSweAgentReposPicker {...props} />)
  expect(screen.getByText('Repository access')).toBeInTheDocument()

  await user.click(screen.getByRole('button', {name: 'Repository access No repositories'}))

  expect(screen.getByRole('menuitemradio', {name: 'No repositories'})).toBeInTheDocument()
  expect(screen.getByRole('menuitemradio', {name: 'All repositories'})).toBeInTheDocument()
  expect(screen.getByRole('menuitemradio', {name: 'Only selected repositories'})).toBeInTheDocument()
})

test('shows banner when onModeChange fails', async () => {
  mockReactFetchJSON.mockRejectedValue(() => {
    return Promise.reject(new Error('fail'))
  })

  const props = getCopilotSweAgentReposPickerProps()
  const {user} = render(<CopilotSweAgentReposPicker {...props} />)

  // Simulate mode change
  await user.click(screen.getByRole('button', {name: 'Repository access No repositories'}))
  await user.click(screen.getByRole('menuitemradio', {name: 'All repositories'}))

  // Banner should appear
  expect(await screen.findByText('Failed to update selection, please try again later.')).toBeInTheDocument()
})
