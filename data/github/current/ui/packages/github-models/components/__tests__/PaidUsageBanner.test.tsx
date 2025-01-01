import {mockUser} from '../../routes/playground/components/__tests__/mocks'
import {render} from '@github-ui/react-core/test-utils'
import {PaidUsageBanner} from '../PaidUsageBanner'
import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'
import {screen} from '@testing-library/react'
import {verifiedFetch} from '@github-ui/verified-fetch'
import {createRepository} from '@github-ui/current-repository/test-helpers'

const currentUser = Object.assign({}, mockUser, {analyticsTrackingId: '8675309'})

jest.mock('@github-ui/react-core/use-feature-flag')
const mockUseFeatureFlag = jest.mocked(useFeatureFlag)

const mockNavigateFn = jest.fn()
jest.mock('@github-ui/use-navigate', () => {
  return {
    useNavigate: () => mockNavigateFn,
  }
})

// eslint-disable-next-line no-restricted-syntax
jest.mock('@github-ui/verified-fetch')
const mockVerifiedFetch = jest.mocked(verifiedFetch)

const resp = Promise.resolve({ok: true} as Response)
mockVerifiedFetch.mockReturnValue(resp)

const mockRepository = createRepository()

describe('PaidUsageBanner', () => {
  afterEach(() => {
    jest.clearAllMocks()
  })

  test('renders when billing UI is enabled and user has not dismissed notice', () => {
    mockUseFeatureFlag.mockReturnValue(true)
    const appPayload = {current_user: currentUser}
    render(<PaidUsageBanner dismissed={false} repository={mockRepository} />, {appPayload})

    const bannerTitle = screen.getByRole('heading', {name: 'Enable paid models usage'})
    expect(bannerTitle).toBeInTheDocument()
    expect(bannerTitle.tagName).toBe('H2')
  })

  test('does not render when billing UI is disabled', () => {
    mockUseFeatureFlag.mockReturnValue(false)
    const appPayload = {
      current_user: currentUser,
      paidUsageBannerDismissed: false,
    }
    render(<PaidUsageBanner dismissed={false} repository={mockRepository} />, {
      appPayload,
    })

    const bannerTitle = screen.queryByRole('heading', {name: 'Enable paid models usage'})
    expect(bannerTitle).not.toBeInTheDocument()
  })

  test('does not render when user has dismissed notice', () => {
    mockUseFeatureFlag.mockReturnValue(true)
    const appPayload = {current_user: currentUser}
    render(<PaidUsageBanner dismissed repository={mockRepository} />, {appPayload})

    const bannerTitle = screen.queryByRole('heading', {name: 'Enable paid models usage'})
    expect(bannerTitle).not.toBeInTheDocument()
  })

  test('does not render when user is not logged in', () => {
    mockUseFeatureFlag.mockReturnValue(true)
    const appPayload = {current_user: null}

    render(<PaidUsageBanner dismissed={false} repository={mockRepository} />, {appPayload})

    const bannerTitle = screen.queryByRole('heading', {name: 'Enable paid models usage'})
    expect(bannerTitle).not.toBeInTheDocument()
  })

  test('if repo is owned by org, and user clicks on enable paid models usage, it should navigate to org settings', async () => {
    mockRepository.isOrgOwned = true
    mockUseFeatureFlag.mockReturnValue(true)
    const appPayload = {current_user: currentUser}
    const {user} = render(<PaidUsageBanner dismissed={false} repository={mockRepository} />, {
      appPayload,
    })

    const enableButton = screen.getAllByRole('button', {name: 'Enable paid usage'})[0] as HTMLButtonElement
    expect(enableButton).toBeInTheDocument()
    await user.click(enableButton)

    expect(mockNavigateFn).toHaveBeenCalledWith(
      `/organizations/${mockRepository.ownerLogin}/settings/models/access-policy`,
    )
  })

  test('if repo is owned by a user, and user clicks on enable paid models usage, it should navigate to user settings', async () => {
    mockRepository.isOrgOwned = false
    mockUseFeatureFlag.mockReturnValue(true)
    const appPayload = {current_user: currentUser}
    const {user} = render(<PaidUsageBanner dismissed={false} repository={mockRepository} />, {
      appPayload,
    })

    const enableButton = screen.getAllByRole('button', {name: 'Enable paid usage'})[0] as HTMLButtonElement
    expect(enableButton).toBeInTheDocument()
    await user.click(enableButton)

    expect(mockNavigateFn).toHaveBeenCalledWith('/settings/models')
  })

  test('if repo is owned by an enterprise, and user clicks on enable paid models usage, it should navigate to enterprise settings', async () => {
    mockRepository.isOrgOwned = true
    mockUseFeatureFlag.mockReturnValue(true)

    const appPayload = {current_user: currentUser}
    const {user} = render(
      <PaidUsageBanner dismissed={false} repository={mockRepository} businessSlug="my-enterprise" />,
      {appPayload},
    )

    const enableButton = screen.getAllByRole('button', {name: 'Enable paid usage'})[0] as HTMLButtonElement
    expect(enableButton).toBeInTheDocument()
    await user.click(enableButton)

    expect(mockNavigateFn).toHaveBeenCalledWith('/enterprises/my-enterprise/settings/models')
  })

  test('if user clicks on dismiss button, it should call verifiedFetch with correct path', async () => {
    mockUseFeatureFlag.mockReturnValue(true)
    const appPayload = {current_user: currentUser}
    const {user} = render(<PaidUsageBanner dismissed={false} repository={mockRepository} />, {
      appPayload,
    })

    const bannerTitle = screen.getByRole('heading', {name: 'Enable paid models usage'})
    expect(bannerTitle).toBeInTheDocument()

    const dismissButton = screen.getByRole('button', {name: 'Dismiss banner'})
    expect(dismissButton).toBeInTheDocument()
    await user.click(dismissButton)

    expect(mockVerifiedFetch).toHaveBeenCalledWith(
      `/users/${currentUser.login}/dismiss_repository_notice?notice_name=github_models_paid_usage_banner_repo&repository_id=${mockRepository.id}`,
      {
        method: 'DELETE',
      },
    )

    expect(screen.queryByRole('heading', {name: 'Enable paid models usage'})).not.toBeInTheDocument()
  })
})
