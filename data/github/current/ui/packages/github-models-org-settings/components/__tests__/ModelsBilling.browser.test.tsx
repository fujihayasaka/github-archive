import {describe, it, expect, afterEach} from '@github-ui/tests'
import {userEvent} from '@github-ui/tests/browser'
import {vi} from 'vitest'
import {screen, within, render as htmlRender} from '@testing-library/react'
import {ModelsBilling} from '../ModelsBilling'
import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'
import {withBaseProvidersWrapper} from '@github-ui/react-core/test-utils'

vi.mock('@github-ui/react-core/use-feature-flag')
const mockUseFeatureFlag = vi.mocked(useFeatureFlag)

const mockVerifiedFetchJSON = vi.fn().mockName('verifiedFetchJSON')

vi.mock('@github-ui/verified-fetch', () => {
  return {
    verifiedFetchJSON: (...args: unknown[]) => mockVerifiedFetchJSON(...args),
  }
})

describe('ModelsBilling', () => {
  afterEach(() => {
    vi.resetAllMocks()
  })

  it('renders when Models billing UI is enabled for the org and Models billing is enabled', async () => {
    mockUseFeatureFlag.mockImplementation(flag => flag === 'github_models_billing_ui')

    render(<ModelsBilling billingEnabled orgDisplayLogin="my-org" canEnableModelsBilling />)

    expect(screen.getByRole('heading', {level: 2, name: 'Billing'})).toBeInTheDocument()
    expect(screen.getByRole('heading', {level: 3, name: 'Additional Models usage'})).toBeInTheDocument()
    const toggleButton = screen.getByRole('button', {name: 'Models billing status:Enabled'})
    expect(toggleButton).toBeInTheDocument()
    expect(screen.queryByRole('menu', {name: 'Models billing status:Enabled'})).not.toBeInTheDocument()
    expect(screen.getByRole('link', {name: 'View billing details'})).toBeInTheDocument()
    expect(screen.getByRole('link', {name: 'Models pricing'})).toBeInTheDocument()
    expect(screen.getByRole('link', {name: 'Set a budget'})).toBeInTheDocument()

    await userEvent.click(toggleButton)

    const menu = screen.getByRole('menu', {name: 'Models billing status:Enabled'})
    expect(menu).toBeInTheDocument()
    expect(within(menu).getByRole('menuitemradio', {name: 'Enabled'})).toHaveAttribute('aria-checked', 'true')
    expect(within(menu).getByRole('menuitemradio', {name: 'Disabled'})).toHaveAttribute('aria-checked', 'false')
    expect(
      screen.queryByText('There was a problem enabling/disabling billing for Models. Please try again later.'),
    ).not.toBeInTheDocument()
  })

  it('renders when Models billing UI is enabled for the org and Models billing is disabled', async () => {
    mockUseFeatureFlag.mockImplementation(flag => flag === 'github_models_billing_ui')

    render(<ModelsBilling billingEnabled={false} orgDisplayLogin="my-org" canEnableModelsBilling />)

    expect(screen.getByRole('heading', {level: 2, name: 'Billing'})).toBeInTheDocument()
    expect(screen.getByRole('heading', {level: 3, name: 'Additional Models usage'})).toBeInTheDocument()
    const toggleButton = screen.getByRole('button', {name: 'Models billing status:Disabled'})
    expect(toggleButton).toBeInTheDocument()
    expect(screen.queryByRole('menu', {name: 'Models billing status:Disabled'})).not.toBeInTheDocument()
    expect(screen.getByRole('link', {name: 'View billing details'})).toBeInTheDocument()
    expect(screen.getByRole('link', {name: 'Models pricing'})).toBeInTheDocument()

    await userEvent.click(toggleButton)

    const menu = screen.getByRole('menu', {name: 'Models billing status:Disabled'})
    expect(menu).toBeInTheDocument()
    expect(within(menu).getByRole('menuitemradio', {name: 'Disabled'})).toHaveAttribute('aria-checked', 'true')
    expect(within(menu).getByRole('menuitemradio', {name: 'Enabled'})).toHaveAttribute('aria-checked', 'false')
    expect(
      screen.queryByText('There was a problem enabling/disabling billing for Models. Please try again later.'),
    ).not.toBeInTheDocument()
  })

  it('renders error message when setting the policy fails', async () => {
    mockUseFeatureFlag.mockImplementation(flag => flag === 'github_models_billing_ui')

    const {container} = render(<ModelsBilling billingEnabled orgDisplayLogin="my-org" canEnableModelsBilling />)

    const toggleButton = screen.getByRole('button', {name: 'Models billing status:Enabled'})
    await userEvent.click(toggleButton)

    mockVerifiedFetchJSON.mockResolvedValue({ok: false, json: () => ({})})
    await userEvent.click(screen.getByRole('menuitemradio', {name: 'Enabled'}))

    expect(
      within(container).getByText('There was a problem enabling/disabling billing for Models. Please try again later.'),
    ).toBeInTheDocument()
  })

  it('renders Disabled when the setting is not togglable', () => {
    mockUseFeatureFlag.mockImplementation(flag => flag === 'github_models_billing_ui')

    render(<ModelsBilling billingEnabled orgDisplayLogin="my-org" canEnableModelsBilling={false} />)

    expect(screen.getByText('Disabled')).toBeInTheDocument()
  })
})

function render(component: JSX.Element) {
  return htmlRender(component, {wrapper: withBaseProvidersWrapper()})
}
