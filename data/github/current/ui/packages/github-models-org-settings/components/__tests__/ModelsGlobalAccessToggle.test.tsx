import {screen, within} from '@testing-library/react'
import {render as htmlRender, withBaseProvidersWrapper} from '@github-ui/react-core/test-utils'
import {ModelsGlobalAccessToggle} from '../ModelsGlobalAccessToggle'
import {
  mockAccessPolicyShowPayload,
  mockModel,
  mockOrganizationAccessPolicy,
  mockResizeObserver,
} from '../../test-utils/mocks'
import type {AccessPolicyShowPayload} from '../../types'
import {OrganizationAccessPolicyProvider} from '../../contexts/OrganizationAccessPolicyContext'

const mockVerifiedFetchJSON = jest.fn().mockName('verifiedFetchJSON')

jest.mock('@github-ui/verified-fetch', () => {
  return {
    verifiedFetchJSON: (...args: unknown[]) => mockVerifiedFetchJSON(...args),
  }
})

describe('ModelsGlobalAccessToggle', () => {
  beforeEach(() => {
    // Necessary to avoid a 'TypeError: observer.observe is not a function' error when all tests are run:
    mockResizeObserver()
  })

  afterEach(() => {
    jest.resetAllMocks()
  })

  test('renders when Models is enabled for the org', async () => {
    const policy = mockOrganizationAccessPolicy({isModelsEnabled: true})

    const {user} = render(<ModelsGlobalAccessToggle />, {policy})

    expect(screen.getByRole('heading', {level: 3, name: 'Models in your organization'})).toBeInTheDocument()
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

  test('renders when Models is restricted for the org via a global block rule', async () => {
    const orgDisplayLogin = 'myOrg'
    const policy = mockOrganizationAccessPolicy({isModelsEnabled: true, isAllowlist: true})

    const {user} = render(<ModelsGlobalAccessToggle />, {policy, orgDisplayLogin})

    expect(screen.getByRole('heading', {level: 3, name: 'Models in your organization'})).toBeInTheDocument()
    const toggleButton = screen.getByRole('button', {name: 'Models status: Enabled'})
    expect(toggleButton).toBeInTheDocument()
    expect(screen.queryByRole('menu', {name: 'Models status: Enabled'})).not.toBeInTheDocument()
    expect(screen.getByRole('link', {name: 'Learn more about Models.'})).toBeInTheDocument()

    await user.click(toggleButton)

    const menu = screen.getByRole('menu', {name: 'Models status: Enabled'})
    expect(menu).toBeInTheDocument()
    expect(within(menu).getByRole('menuitemradio', {name: 'Enabled'})).toHaveAttribute('aria-checked', 'true')
    const disableMenuItem = within(menu).getByRole('menuitemradio', {name: 'Disabled'})
    expect(disableMenuItem).toHaveAttribute('aria-checked', 'false')
    expect(
      screen.queryByText('There was a problem saving your policy. Please try again later.'),
    ).not.toBeInTheDocument()

    mockVerifiedFetchJSON.mockResolvedValue({
      ok: true,
      json: () => mockOrganizationAccessPolicy({isModelsEnabled: false, isAllowlist: true}),
    })
    await user.click(disableMenuItem)

    expect(mockVerifiedFetchJSON).toHaveBeenCalledTimes(1)
    expect(mockVerifiedFetchJSON).toHaveBeenCalledWith(
      `/organizations/${orgDisplayLogin}/settings/models/access-policy`,
      {method: 'DELETE', body: {disable: '1'}},
    )
  })

  test('renders when Models is restricted for the org via a targeted block rule', () => {
    const models = [mockModel({key: 'foo/123'}), mockModel({key: 'bar/456'})]
    const policy = mockOrganizationAccessPolicy({
      isModelsEnabled: true,
      isAllowlist: false,
      allowedModelKeys: ['bar/456'],
    })

    render(<ModelsGlobalAccessToggle />, {models, policy})

    expect(screen.getByRole('heading', {level: 3, name: 'Models in your organization'})).toBeInTheDocument()
    const toggleButton = screen.getByRole('button', {name: 'Models status: Enabled'})
    expect(toggleButton).toBeInTheDocument()
    expect(screen.queryByRole('menu', {name: 'Models status: Enabled'})).not.toBeInTheDocument()
    expect(screen.getByRole('link', {name: 'Learn more about Models.'})).toBeInTheDocument()
  })

  test('renders when Models is disabled for the org', async () => {
    const orgDisplayLogin = 'myOrg'
    const policy = mockOrganizationAccessPolicy({isModelsEnabled: false})

    const {user} = render(<ModelsGlobalAccessToggle />, {orgDisplayLogin, policy})

    expect(screen.getByRole('heading', {level: 3, name: 'Models in your organization'})).toBeInTheDocument()
    const toggleButton = screen.getByRole('button', {name: 'Models status: Disabled'})
    expect(toggleButton).toBeInTheDocument()
    expect(screen.queryByRole('menu', {name: 'Models status: Disabled'})).not.toBeInTheDocument()
    expect(screen.getByRole('link', {name: 'Learn more about Models.'})).toBeInTheDocument()

    await user.click(toggleButton)

    const menu = screen.getByRole('menu', {name: 'Models status: Disabled'})
    expect(menu).toBeInTheDocument()
    const enableMenuItem = within(menu).getByRole('menuitemradio', {name: 'Enabled'})
    expect(enableMenuItem).toHaveAttribute('aria-checked', 'false')
    expect(within(menu).getByRole('menuitemradio', {name: 'Disabled'})).toHaveAttribute('aria-checked', 'true')
    expect(
      screen.queryByText('There was a problem saving your policy. Please try again later.'),
    ).not.toBeInTheDocument()

    mockVerifiedFetchJSON.mockResolvedValue({
      ok: true,
      json: () => mockOrganizationAccessPolicy({isModelsEnabled: true, isAllowlist: false}),
    })
    await user.click(enableMenuItem)

    expect(mockVerifiedFetchJSON).toHaveBeenCalledTimes(1)
    expect(mockVerifiedFetchJSON).toHaveBeenCalledWith(
      `/organizations/${orgDisplayLogin}/settings/models/access-policy`,
      {method: 'POST', body: {enable: '1'}},
    )
  })

  test('renders error message when setting the policy fails', async () => {
    const policy = mockOrganizationAccessPolicy({isModelsEnabled: true})

    const {container, user} = render(<ModelsGlobalAccessToggle />, {policy})

    await user.click(screen.getByRole('button', {name: 'Models status: Enabled'}))

    mockVerifiedFetchJSON.mockResolvedValue({ok: false, json: () => ({})})
    await user.click(screen.getByRole('menuitemradio', {name: 'Disabled'}))

    expect(
      within(container).getByText('There was a problem saving your policy. Please try again later.'),
    ).toBeInTheDocument()
  })
})

function render(component: JSX.Element, routePayloadOverrides?: Partial<AccessPolicyShowPayload>) {
  const routePayload = mockAccessPolicyShowPayload(routePayloadOverrides)
  return htmlRender(<OrganizationAccessPolicyProvider>{component}</OrganizationAccessPolicyProvider>, {
    wrapper: withBaseProvidersWrapper(),
    routePayload,
  })
}
