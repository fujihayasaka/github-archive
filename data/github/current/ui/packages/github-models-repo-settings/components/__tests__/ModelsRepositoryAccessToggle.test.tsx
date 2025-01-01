import {screen, within} from '@testing-library/react'
import {render as htmlRender} from '@github-ui/react-core/test-utils'
import {mockAccessPolicyShowPayload, mockResizeObserver} from '../../test-utils/mocks'
import type {RepositoryAccessPolicyShowPayload} from '../../types'
import {AccessPolicyProvider} from '../../contexts/AccessPolicyContext'
import {ModelsAccessToggle} from '../ModelsAccessToggle'

const mockVerifiedFetchJSON = jest.fn().mockName('verifiedFetchJSON')

// eslint-disable-next-line no-restricted-syntax
jest.mock('@github-ui/verified-fetch', () => {
  return {
    verifiedFetchJSON: (...args: unknown[]) => mockVerifiedFetchJSON(...args),
  }
})

describe('ModelsRepositoryAccessToggle', () => {
  beforeEach(() => {
    // Necessary to avoid a 'TypeError: observer.observe is not a function' error when all tests are run:
    mockResizeObserver()
  })

  afterEach(() => {
    jest.resetAllMocks()
  })

  test('renders when Models is enabled for the org and repo', async () => {
    const {user} = render(<ModelsAccessToggle />, {
      isAccessConfigurable: true,
      repositoryAccessPolicy: {isRepoModelsEnabled: true},
    })

    expect(screen.getByRole('heading', {level: 3, name: 'Models in this repository'})).toBeInTheDocument()
    const toggleButton = screen.getByRole('button', {name: 'Models status: Enabled'})
    expect(toggleButton).toBeInTheDocument()
    expect(screen.queryByRole('menu', {name: 'Models status: Enabled'})).not.toBeInTheDocument()
    expect(screen.getByRole('link', {name: 'Learn more about Models.'})).toBeInTheDocument()

    await user.click(toggleButton)

    const menu = screen.getByRole('menu', {name: 'Models status: Enabled'})
    expect(menu).toBeInTheDocument()
    expect(within(menu).getByRole('menuitemradio', {name: 'Enabled'})).toHaveAttribute('aria-checked', 'true')
    expect(within(menu).getByRole('menuitemradio', {name: 'Disabled'})).toHaveAttribute('aria-checked', 'false')
    expect(
      screen.queryByText('There was a problem saving your policy. Please try again later.'),
    ).not.toBeInTheDocument()
  })

  test('renders when Models is disabled for the org', async () => {
    render(<ModelsAccessToggle />, {
      isAccessConfigurable: false,
      repositoryAccessPolicy: {isRepoModelsEnabled: true},
    })

    expect(screen.getByRole('heading', {level: 3, name: 'Models in this repository'})).toBeInTheDocument()

    expect(
      screen.getByText('This setting has been disabled by organization policy administrators.'),
    ).toBeInTheDocument()
    expect(
      screen.queryByText('There was a problem saving your policy. Please try again later.'),
    ).not.toBeInTheDocument()
  })

  test('renders when Models is enabled for the org and disabled for repo', async () => {
    render(<ModelsAccessToggle />, {
      isAccessConfigurable: true,
      repositoryAccessPolicy: {isRepoModelsEnabled: false},
    })

    expect(screen.getByRole('heading', {level: 3, name: 'Models in this repository'})).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Models status: Disabled'})).toBeInTheDocument()
    expect(screen.getByRole('link', {name: 'Learn more about Models.'})).toBeInTheDocument()
    expect(
      screen.queryByText('There was a problem saving your policy. Please try again later.'),
    ).not.toBeInTheDocument()
  })

  test('renders organization helper text when the repository is org-owned', () => {
    render(<ModelsAccessToggle />, {
      isAccessConfigurable: true,
      repositoryOwnerType: 'organization',
      repositoryAccessPolicy: {isRepoModelsEnabled: false},
    })

    expect(screen.getByRole('heading', {level: 3, name: 'Models in this repository'})).toBeInTheDocument()
    expect(
      screen.getByText(/for additional configuration options, go to models in organization settings/i),
    ).toBeInTheDocument()
  })

  test('does not render organization helper text when the repository is user-owned', async () => {
    render(<ModelsAccessToggle />, {
      isAccessConfigurable: true,
      repositoryOwnerType: 'user',
      repositoryAccessPolicy: {isRepoModelsEnabled: false},
    })

    expect(screen.getByRole('heading', {level: 3, name: 'Models in this repository'})).toBeInTheDocument()
    expect(
      screen.queryByText(/for additional configuration options, go to models in organization settings/i),
    ).not.toBeInTheDocument()
  })

  test('renders error message when setting the policy fails', async () => {
    const {container, user} = render(<ModelsAccessToggle />, {
      isAccessConfigurable: true,
      repositoryAccessPolicy: {isRepoModelsEnabled: true},
    })

    await user.click(screen.getByRole('button', {name: 'Models status: Enabled'}))

    mockVerifiedFetchJSON.mockResolvedValue({ok: false, json: () => ({})})
    await user.click(screen.getByRole('menuitemradio', {name: 'Disabled'}))

    expect(
      within(container).getByText('There was a problem saving your policy. Please try again later.'),
    ).toBeInTheDocument()
  })
})

function render(component: JSX.Element, routePayloadOverrides?: Partial<RepositoryAccessPolicyShowPayload>) {
  const routePayload = mockAccessPolicyShowPayload(routePayloadOverrides)
  return htmlRender(<AccessPolicyProvider>{component}</AccessPolicyProvider>, {
    routePayload,
  })
}
