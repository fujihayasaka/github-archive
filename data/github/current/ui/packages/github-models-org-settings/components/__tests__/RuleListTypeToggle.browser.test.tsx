import {describe, it, expect, afterEach} from '@github-ui/tests'
import {userEvent} from '@github-ui/tests/browser'
import {vi} from 'vitest'
import {screen, within, render as htmlRender} from '@testing-library/react'
import {withBaseProvidersWrapper} from '@github-ui/react-core/test-utils'
import {mockAccessPolicyShowPayload, mockOrganizationAccessPolicy} from '../../test-utils/mocks'
import type {AccessPolicyShowPayload} from '../../types'
import {OrganizationAccessPolicyProvider} from '../../contexts/OrganizationAccessPolicyContext'
import {RuleListTypeToggle} from '../RuleListTypeToggle'

const mockVerifiedFetchJSON = vi.fn().mockName('verifiedFetchJSON')

vi.mock('@github-ui/verified-fetch', () => {
  return {
    verifiedFetchJSON: (...args: unknown[]) => mockVerifiedFetchJSON(...args),
    reactFetchJSON: (...args: unknown[]) => mockVerifiedFetchJSON(...args),
  }
})

describe('RuleListTypeToggle', () => {
  afterEach(() => {
    vi.resetAllMocks()
  })

  it('renders when rules list is an allow list', async () => {
    const orgDisplayLogin = 'someOrg'
    const policy = mockOrganizationAccessPolicy({isModelsEnabled: true, isAllowlist: true})

    render(<RuleListTypeToggle />, {orgDisplayLogin, policy})

    const menuToggle = screen.getByRole('button', {name: 'Enabled list'})
    expect(menuToggle).toBeInTheDocument()

    await userEvent.click(menuToggle)

    const menu = screen.getByRole('menu', {name: 'Enabled list'})
    expect(menu).toBeInTheDocument()
    expect(within(menu).getByRole('menuitemradio', {name: 'Enabled list'})).toHaveAttribute('aria-checked', 'true')
    const disableItem = within(menu).getByRole('menuitemradio', {name: 'Disabled list'})
    expect(disableItem).toHaveAttribute('aria-checked', 'false')

    mockVerifiedFetchJSON.mockResolvedValue({
      ok: true,
      json: () => mockOrganizationAccessPolicy({isAllowlist: false}),
    })
    await userEvent.click(disableItem)

    expect(mockVerifiedFetchJSON).toHaveBeenCalledTimes(1)
    expect(mockVerifiedFetchJSON).toHaveBeenCalledWith(
      `/organizations/${orgDisplayLogin}/settings/models/access-policy`,
      {method: 'POST', body: {}},
    )
  })

  it('renders when rules list is a block list', async () => {
    const orgDisplayLogin = 'someOrg'
    const policy = mockOrganizationAccessPolicy({isModelsEnabled: true, isAllowlist: false})

    render(<RuleListTypeToggle />, {orgDisplayLogin, policy})

    const menuToggle = screen.getByRole('button', {name: 'Disabled list'})
    expect(menuToggle).toBeInTheDocument()

    await userEvent.click(menuToggle)

    const menu = screen.getByRole('menu', {name: 'Disabled list'})
    expect(menu).toBeInTheDocument()
    const enableItem = within(menu).getByRole('menuitemradio', {name: 'Enabled list'})
    expect(enableItem).toHaveAttribute('aria-checked', 'false')
    expect(within(menu).getByRole('menuitemradio', {name: 'Disabled list'})).toHaveAttribute('aria-checked', 'true')

    mockVerifiedFetchJSON.mockResolvedValue({
      ok: true,
      json: () => mockOrganizationAccessPolicy({isAllowlist: true}),
    })
    await userEvent.click(enableItem)

    expect(mockVerifiedFetchJSON).toHaveBeenCalledTimes(1)
    expect(mockVerifiedFetchJSON).toHaveBeenCalledWith(
      `/organizations/${orgDisplayLogin}/settings/models/access-policy`,
      {method: 'DELETE', body: {}},
    )
  })

  it('does not render when Models is disabled for the org', () => {
    const policy = mockOrganizationAccessPolicy({isModelsEnabled: false})

    render(<RuleListTypeToggle />, {policy})

    expect(screen.queryByRole('button', {name: 'Enabled list'})).not.toBeInTheDocument()
    expect(screen.queryByRole('button', {name: 'Disabled list'})).not.toBeInTheDocument()
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
