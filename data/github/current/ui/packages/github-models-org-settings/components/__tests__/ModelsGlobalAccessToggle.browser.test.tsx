import {describe, it, expect, afterEach} from '@github-ui/tests'
import {userEvent} from '@github-ui/tests/browser'
import {vi} from 'vitest'
import {screen, within, render as htmlRender} from '@testing-library/react'
import {withBaseProvidersWrapper} from '@github-ui/react-core/test-utils'
import {ModelsGlobalAccessToggle} from '../ModelsGlobalAccessToggle'
import {mockAccessPolicyShowPayload, mockModel, mockOrganizationAccessPolicy} from '../../test-utils/mocks'
import type {AccessPolicyShowPayload} from '../../types'
import {OrganizationAccessPolicyProvider} from '../../contexts/OrganizationAccessPolicyContext'

const mockVerifiedFetchJSON = vi.fn().mockName('verifiedFetchJSON')

vi.mock('@github-ui/verified-fetch', () => {
  return {
    verifiedFetchJSON: (...args: unknown[]) => mockVerifiedFetchJSON(...args),
    reactFetchJSON: (...args: unknown[]) => mockVerifiedFetchJSON(...args),
  }
})

describe('ModelsGlobalAccessToggle', () => {
  afterEach(() => {
    vi.resetAllMocks()
  })

  it('renders when Models is enabled for the org and configurable', async () => {
    const policy = mockOrganizationAccessPolicy({isModelsEnabled: true, isAccessConfigurable: true})

    render(<ModelsGlobalAccessToggle />, {policy})

    expect(screen.getByRole('heading', {level: 3, name: 'Models in your organization'})).toBeInTheDocument()
    const toggleButton = screen.getByRole('button', {name: 'Models status:Enabled'})
    expect(toggleButton).toBeInTheDocument()
    expect(screen.queryByRole('menu', {name: 'Models status:Enabled'})).not.toBeInTheDocument()
    expect(screen.getByRole('link', {name: 'Learn more about Models.'})).toBeInTheDocument()

    await userEvent.click(toggleButton)

    const menu = screen.getByRole('menu', {name: 'Models status:Enabled'})
    expect(menu).toBeInTheDocument()
    expect(within(menu).getByRole('menuitemradio', {name: 'Enabled'})).toHaveAttribute('aria-checked', 'true')
    expect(within(menu).getByRole('menuitemradio', {name: 'Disabled'})).toHaveAttribute('aria-checked', 'false')
    expect(
      screen.queryByText('There was a problem saving your policy. Please try again later.'),
    ).not.toBeInTheDocument()
  })

  it('renders when Models is restricted for the org via a global block rule', async () => {
    const orgDisplayLogin = 'myOrg'
    const policy = mockOrganizationAccessPolicy({isModelsEnabled: true, isAllowlist: true, isAccessConfigurable: true})

    render(<ModelsGlobalAccessToggle />, {policy, orgDisplayLogin})

    expect(screen.getByRole('heading', {level: 3, name: 'Models in your organization'})).toBeInTheDocument()
    const toggleButton = screen.getByRole('button', {name: 'Models status:Enabled'})
    expect(toggleButton).toBeInTheDocument()
    expect(screen.queryByRole('menu', {name: 'Models status:Enabled'})).not.toBeInTheDocument()
    expect(screen.getByRole('link', {name: 'Learn more about Models.'})).toBeInTheDocument()

    await userEvent.click(toggleButton)

    const menu = screen.getByRole('menu', {name: 'Models status:Enabled'})
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
    await userEvent.click(disableMenuItem)

    expect(mockVerifiedFetchJSON).toHaveBeenCalledTimes(1)
    expect(mockVerifiedFetchJSON).toHaveBeenCalledWith(
      `/organizations/${orgDisplayLogin}/settings/models/access-policy`,
      {method: 'DELETE', body: {disable: '1'}},
    )
  })

  it('renders when Models is restricted for the org via a targeted block rule', () => {
    const models = [mockModel({key: 'foo/123'}), mockModel({key: 'bar/456'})]
    const policy = mockOrganizationAccessPolicy({
      isModelsEnabled: true,
      isAccessConfigurable: true,
      isAllowlist: false,
      allowedModelKeys: ['bar/456'],
    })

    render(<ModelsGlobalAccessToggle />, {models, policy})

    expect(screen.getByRole('heading', {level: 3, name: 'Models in your organization'})).toBeInTheDocument()
    const toggleButton = screen.getByRole('button', {name: 'Models status:Enabled'})
    expect(toggleButton).toBeInTheDocument()
    expect(screen.queryByRole('menu', {name: 'Models status:Enabled'})).not.toBeInTheDocument()
    expect(screen.getByRole('link', {name: 'Learn more about Models.'})).toBeInTheDocument()
  })

  it('renders when Models is disabled for the org', async () => {
    const orgDisplayLogin = 'myOrg'
    const policy = mockOrganizationAccessPolicy({isModelsEnabled: false, isAccessConfigurable: true})

    render(<ModelsGlobalAccessToggle />, {orgDisplayLogin, policy})

    expect(screen.getByRole('heading', {level: 3, name: 'Models in your organization'})).toBeInTheDocument()
    const toggleButton = screen.getByRole('button', {name: 'Models status:Disabled'})
    expect(toggleButton).toBeInTheDocument()
    expect(screen.queryByRole('menu', {name: 'Models status:Disabled'})).not.toBeInTheDocument()
    expect(screen.getByRole('link', {name: 'Learn more about Models.'})).toBeInTheDocument()

    await userEvent.click(toggleButton)

    const menu = screen.getByRole('menu', {name: 'Models status:Disabled'})
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
    await userEvent.click(enableMenuItem)

    expect(mockVerifiedFetchJSON).toHaveBeenCalledTimes(1)
    expect(mockVerifiedFetchJSON).toHaveBeenCalledWith(
      `/organizations/${orgDisplayLogin}/settings/models/access-policy`,
      {method: 'POST', body: {enable: '1'}},
    )
  })

  it('renders error message when setting the policy fails', async () => {
    const policy = mockOrganizationAccessPolicy({isModelsEnabled: true, isAccessConfigurable: true})

    const {container} = render(<ModelsGlobalAccessToggle />, {policy})

    await userEvent.click(screen.getByRole('button', {name: 'Models status:Enabled'}))

    mockVerifiedFetchJSON.mockResolvedValue({ok: false, json: () => ({})})
    await userEvent.click(screen.getByRole('menuitemradio', {name: 'Disabled'}))

    expect(
      within(container).getByText('There was a problem saving your policy. Please try again later.'),
    ).toBeInTheDocument()
  })

  it('renders a message when Models is enabled but not configurable', () => {
    const policy = mockOrganizationAccessPolicy({isModelsEnabled: true, isAccessConfigurable: false})

    render(<ModelsGlobalAccessToggle />, {policy})

    expect(screen.queryByRole('button', {name: /Models status:/})).not.toBeInTheDocument()
    expect(
      screen.getByText('This setting has been disabled by your enterprise policy administrators.'),
    ).toBeInTheDocument()
  })

  it('renders a message when Models is disabled and not configurable', () => {
    const policy = mockOrganizationAccessPolicy({isModelsEnabled: false, isAccessConfigurable: false})

    render(<ModelsGlobalAccessToggle />, {policy})

    expect(screen.queryByRole('button', {name: /Models status:/})).not.toBeInTheDocument()
    expect(
      screen.getByText('This setting has been disabled by your enterprise policy administrators.'),
    ).toBeInTheDocument()
  })
})

function render(component: JSX.Element, routePayloadOverrides?: Partial<AccessPolicyShowPayload>) {
  const routePayload = mockAccessPolicyShowPayload(routePayloadOverrides)
  return htmlRender(
    <OrganizationAccessPolicyProvider orgDisplayLogin={routePayload.orgDisplayLogin} policy={routePayload.policy}>
      {component}
    </OrganizationAccessPolicyProvider>,
    {wrapper: withBaseProvidersWrapper()},
  )
}
