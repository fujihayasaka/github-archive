import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import SweAgent from '../SweAgent'
import {reactFetchJSON} from '@github-ui/verified-fetch'

jest.mock('@github-ui/feature-flags', () => ({
  isFeatureEnabled: jest.fn(),
}))

const mockReactFetchJSON = reactFetchJSON as jest.Mock
// eslint-disable-next-line no-restricted-syntax
jest.mock('@github-ui/verified-fetch', () => ({
  reactFetchJSON: jest.fn(),
}))

const useCopilotSettingsMutationCommit = jest.fn(({onComplete}) => {
  onComplete({success: true})
})

jest.mock('../../hooks/use-fetchers', () => {
  const actual = jest.requireActual('../../hooks/use-fetchers')

  return {
    ...actual,
    useCreateMutator: jest.fn().mockImplementation(() => () => [useCopilotSettingsMutationCommit, false]),
  }
})

test('renders the index page', () => {
  render(<SweAgent />, {routePayload: {project_display_name: 'Copilot coding agent'}, appPayload: makeFeatureFlags()})

  expect(
    screen.getAllByRole('heading', {level: 2}).find(h => h.textContent?.includes('Copilot coding agent')),
  ).toBeTruthy()
})

test('renders repos picker with three selection modes', async () => {
  const {user} = render(<SweAgent />, {
    routePayload: {
      project_display_name: 'Copilot coding agent',
      selection: [],
      org_login: 'github',
      mode: 'no_repos',
    },
    appPayload: makeFeatureFlags(),
  })

  expect(screen.getByText('Repository access')).toBeInTheDocument()

  await user.click(screen.getByRole('button', {name: 'Repository access No repositories'}))

  expect(screen.getByRole('menuitemradio', {name: 'No repositories'})).toBeInTheDocument()
  expect(screen.getByRole('menuitemradio', {name: 'All repositories'})).toBeInTheDocument()
  expect(screen.getByRole('menuitemradio', {name: 'Only selected repositories'})).toBeInTheDocument()
})

test('renders access banner', async () => {
  render(<SweAgent />, {
    routePayload: {
      project_display_name: 'Copilot coding agent',
      access_warning_banner_content: 'uh oh!',
    },
    appPayload: makeFeatureFlags(),
  })

  expect(screen.getByText('uh oh!')).toBeInTheDocument()
})

test('shows banner when onModeChange fails', async () => {
  mockReactFetchJSON.mockRejectedValue(() => {
    return Promise.reject(new Error('fail'))
  })

  const {user} = render(<SweAgent />, {
    routePayload: {
      project_display_name: 'Copilot coding agent',
      selection: [],
      org_login: 'github',
      mode: 'no_repos',
      selections_changed_callback_path: '/selection',
      mode_changed_callback_path: '/fail',
    },
    appPayload: makeFeatureFlags(),
  })

  // Simulate mode change
  await user.click(screen.getByRole('button', {name: 'Repository access No repositories'}))
  await user.click(screen.getByRole('menuitemradio', {name: 'All repositories'}))

  // Banner should appear
  expect(await screen.findByText('Failed to update selection, please try again later.')).toBeInTheDocument()
})

// --

function makeFeatureFlags(flags: Record<string, boolean> = {}) {
  return {
    enabled_features: {
      ...flags,
    },
  }
}
