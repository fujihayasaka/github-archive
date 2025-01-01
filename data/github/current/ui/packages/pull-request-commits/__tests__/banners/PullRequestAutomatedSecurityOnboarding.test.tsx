import {screen} from '@testing-library/react'
import {renderWithClient} from '@github-ui/pull-request-page-data-tooling/render-with-query-client'

import {PullRequestAutomatedSecurityOnboarding} from '../../components/banners/PullRequestAutomatedSecurityOnboarding'
import {getCommitsRoutePayload} from '../../test-utils/mock-data'

describe('PullRequestAutomatedSecurityOnboarding', () => {
  test('renders without errors', () => {
    const {bannersData} = getCommitsRoutePayload()
    bannersData.banners.dependabotAutomatedSecurityUpdates.render = true

    renderWithClient(
      <PullRequestAutomatedSecurityOnboarding
        onBoardingProps={bannersData.banners.dependabotAutomatedSecurityUpdates.onboardingBannerProps}
      />,
    )

    expect(screen.getByText(/Your first automated security update/)).toBeInTheDocument()
    expect(screen.getByText(/security updates keep your projects secure and up-to-date./)).toBeInTheDocument()
    expect(screen.getByText(/Got it!/)).toBeInTheDocument()
    expect(screen.getByText(/Learn more/)).toBeInTheDocument()
  })

  test('renders opt out if the user has permissions', () => {
    const {bannersData} = getCommitsRoutePayload()
    bannersData.banners.dependabotAutomatedSecurityUpdates.render = true
    bannersData.banners.dependabotAutomatedSecurityUpdates.onboardingBannerProps.showOptOut = true

    renderWithClient(
      <PullRequestAutomatedSecurityOnboarding
        onBoardingProps={bannersData.banners.dependabotAutomatedSecurityUpdates.onboardingBannerProps}
      />,
    )

    expect(screen.getByText(/Your first automated security update/)).toBeInTheDocument()
    expect(screen.getByText(/You can opt out at any time in/)).toBeInTheDocument()
    expect(screen.getByText(/Got it!/)).toBeInTheDocument()
    expect(screen.getByText(/Learn more/)).toBeInTheDocument()
  })

  test('closes the popover when acknowledged', async () => {
    const {bannersData} = getCommitsRoutePayload()
    bannersData.banners.dependabotAutomatedSecurityUpdates.render = true

    const {user} = renderWithClient(
      <PullRequestAutomatedSecurityOnboarding
        onBoardingProps={bannersData.banners.dependabotAutomatedSecurityUpdates.onboardingBannerProps}
      />,
    )
    const acknowledgeButton = screen.getByText(/Got it!/)

    expect(acknowledgeButton).toBeInTheDocument()

    await user.click(acknowledgeButton)

    expect(screen.queryByText(/Your first automated security update/)).not.toBeVisible()
  })
})
