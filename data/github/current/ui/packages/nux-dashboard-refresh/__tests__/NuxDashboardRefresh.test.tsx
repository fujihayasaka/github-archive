import {expectAnalyticsEvents} from '@github-ui/analytics-test-utils'
import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {NuxDashboardRefresh} from '../NuxDashboardRefresh'
import {getNuxDashboardRefreshProps, getNuxDashboardRefreshPropsWithCompletedChecklist} from '../test-utils/mock-data'

describe('NuxDashboardRefresh with default props', () => {
  const props = getNuxDashboardRefreshProps()

  test('Renders the NuxDashboardRefresh', () => {
    render(<NuxDashboardRefresh {...props} />)

    expect(screen.getByTestId('beginners-playlist-section')).toBeInTheDocument()
    expect(screen.getByTestId('getting-started-checklist-section')).toBeInTheDocument()
    expect(screen.getByTestId('docs-section')).toBeInTheDocument()
    expect(screen.getByTestId('recommendations-section')).toBeInTheDocument()
  })

  test('Handles dismissal for playlist', async () => {
    const {user} = render(<NuxDashboardRefresh {...props} />)

    const playlistSection = screen.getByTestId('beginners-playlist-section')
    const playlistDismiss = screen.getByTestId('Playlist-dismiss')

    expect(playlistSection).toBeVisible()

    await user.click(playlistDismiss)

    expect(playlistSection).not.toBeInTheDocument()

    expectAnalyticsEvents({
      type: 'analytics.click',
      data: {
        category: 'zero_user_dashboard',
        action: 'click.playlist.dismiss',
      },
    })
  })

  test('Handles dismissal for getting started checklist', async () => {
    const {user} = render(<NuxDashboardRefresh {...props} />)

    const gettingStartedSection = screen.getByTestId('getting-started-checklist-section')
    const gettingStartedOptions = screen.getByTestId('checklist-options')

    expect(gettingStartedSection).toBeVisible()

    await user.click(gettingStartedOptions)

    const gettingStartedDismiss = screen.getByTestId('checklist-remove-option')

    expect(gettingStartedDismiss).toBeVisible()

    await user.click(gettingStartedDismiss)

    expect(gettingStartedSection).not.toBeInTheDocument()

    expectAnalyticsEvents({
      type: 'analytics.click',
      data: {
        category: 'zero_user_dashboard',
        action: 'click.getting_started.dismiss',
      },
    })
  })

  test('Handles dismissal for docs', async () => {
    const {user} = render(<NuxDashboardRefresh {...props} />)

    const docsSection = screen.getByTestId('docs-section')
    const docsOptions = screen.getByTestId('docs-options')

    expect(docsSection).toBeVisible()

    await user.click(docsOptions)

    const docsDismiss = screen.getByTestId('docs-remove-option')

    expect(docsDismiss).toBeVisible()

    await user.click(docsDismiss)

    expect(docsSection).not.toBeInTheDocument()

    expectAnalyticsEvents({
      type: 'analytics.click',
      data: {
        category: 'zero_user_dashboard',
        action: 'click.docs.dismiss',
      },
    })
  })

  test('Handles dismissal of recommendations section when all items are dismissed', async () => {
    const {user} = render(<NuxDashboardRefresh {...props} />)

    const recommendationsSection = screen.getByTestId('recommendations-section')
    const vsCodeDownloadBanner = screen.getByTestId('download-banner-download_visual_studio_with_copilot')
    const vsCodeDismiss = screen.getByTestId('download-banner-download_visual_studio_with_copilot-dismiss')
    const desktopDownloadBanner = screen.getByTestId('download-banner-download_github_for_desktop')
    const desktopDismiss = screen.getByTestId('download-banner-download_github_for_desktop-dismiss')

    expect(recommendationsSection).toBeVisible()
    expect(vsCodeDownloadBanner).toBeVisible()
    expect(desktopDownloadBanner).toBeVisible()

    await user.click(vsCodeDismiss)

    expect(vsCodeDownloadBanner).not.toBeInTheDocument()

    await user.click(desktopDismiss)

    expect(desktopDownloadBanner).not.toBeInTheDocument()

    expect(recommendationsSection).not.toBeInTheDocument()

    expectAnalyticsEvents(
      {
        type: 'analytics.click',
        data: {
          category: 'zero_user_dashboard',
          action: 'click.recommendations.download_banner.download_visual_studio_with_copilot.dismiss',
        },
      },
      {
        type: 'analytics.click',
        data: {
          category: 'zero_user_dashboard',
          action: 'click.recommendations.download_banner.download_github_for_desktop.dismiss',
        },
      },
    )
  })

  test('Handles dismissal of recommendations section when not all items are dismissed', async () => {
    const {user} = render(<NuxDashboardRefresh {...props} />)

    const recommendationsSection = screen.getByTestId('recommendations-section')
    const recommendationsOptions = screen.getByTestId('recommendations-options')
    const vsCodeDownloadBanner = screen.getByTestId('download-banner-download_visual_studio_with_copilot')
    const vsCodeDismiss = screen.getByTestId('download-banner-download_visual_studio_with_copilot-dismiss')
    const desktopDownloadBanner = screen.getByTestId('download-banner-download_github_for_desktop')

    expect(recommendationsSection).toBeVisible()
    expect(vsCodeDownloadBanner).toBeVisible()
    expect(desktopDownloadBanner).toBeVisible()

    await user.click(vsCodeDismiss)

    expect(recommendationsSection).toBeVisible()
    expect(vsCodeDownloadBanner).not.toBeInTheDocument()
    expect(desktopDownloadBanner).toBeVisible()

    await user.click(recommendationsOptions)

    const recommendationsDismiss = screen.getByTestId('recommendations-remove-option')

    expect(recommendationsDismiss).toBeVisible()

    await user.click(recommendationsDismiss)

    expect(recommendationsSection).not.toBeInTheDocument()
    expect(vsCodeDownloadBanner).not.toBeInTheDocument()
    expect(desktopDownloadBanner).not.toBeInTheDocument()

    expectAnalyticsEvents(
      {
        type: 'analytics.click',
        data: {
          category: 'zero_user_dashboard',
          action: 'click.recommendations.download_banner.download_visual_studio_with_copilot.dismiss',
        },
      },
      {
        type: 'analytics.click',
        data: {
          category: 'zero_user_dashboard',
          action: 'click.recommendations.dismiss',
        },
      },
    )
  })

  test('Handles clicking through the new user getting started checklist', async () => {
    const {user} = render(<NuxDashboardRefresh {...props} />)

    expect(screen.getByTestId('stepper-cta-0')).toBeVisible()

    await user.click(screen.getByTestId('stepper-button-1'))

    expect(screen.getByTestId('stepper-cta-1')).toBeVisible()

    await user.click(screen.getByTestId('stepper-button-2'))

    expect(screen.getByTestId('stepper-cta-2')).toBeVisible()
  })
})

describe('NuxDashboardRefresh with completed checklist', () => {
  const props = getNuxDashboardRefreshPropsWithCompletedChecklist()

  test('Displays completed state when checklist is completed', async () => {
    render(<NuxDashboardRefresh {...props} />)

    expect(screen.getByTestId('getting-started-checklist-section')).toBeInTheDocument()
    expect(screen.getByTestId('getting-started-checklist-complete')).toBeInTheDocument()
    expect(screen.queryByTestId('getting-started-checklist')).not.toBeInTheDocument()
  })
})

describe('NuxDashboardRefresh button/link analytics', () => {
  const props = getNuxDashboardRefreshProps()

  test('Sends analytics events for playlist', async () => {
    const {user} = render(<NuxDashboardRefresh {...props} />)

    await user.click(screen.getByTestId('start-playlist'))

    await user.click(screen.getByTestId('play-video'))

    expectAnalyticsEvents(
      {
        type: 'analytics.click',
        data: {
          category: 'zero_user_dashboard',
          action: 'click.playlist.start_playlist',
        },
      },
      {
        type: 'analytics.click',
        data: {
          category: 'zero_user_dashboard',
          action: 'click.playlist.play_video',
        },
      },
    )
  })

  test('Sends analytics events for getting started checklist', async () => {
    const {user} = render(<NuxDashboardRefresh {...props} />)

    await user.click(screen.getByTestId('stepper-cta-0'))

    await user.click(screen.getByTestId('stepper-button-1'))
    await user.click(screen.getByTestId('stepper-cta-1'))

    await user.click(screen.getByTestId('stepper-button-2'))
    await user.click(screen.getByTestId('stepper-cta-2'))

    expectAnalyticsEvents(
      {
        type: 'analytics.click',
        data: {
          category: 'zero_user_dashboard',
          action: 'click.getting_started.complete_profile',
        },
      },
      {
        type: 'analytics.click',
        data: {
          category: 'zero_user_dashboard',
          action: 'click.getting_started.try_copilot',
        },
      },
      {
        type: 'analytics.click',
        data: {
          category: 'zero_user_dashboard',
          action: 'click.getting_started.create_repo',
        },
      },
    )
  })

  test('Sends analytics events for docs', async () => {
    const {user} = render(<NuxDashboardRefresh {...props} />)

    await user.click(screen.getByTestId('resource-card-github_documentation'))
    await user.click(screen.getByTestId('resource-card-about_github_and_git'))
    await user.click(screen.getByTestId('resource-card-how_to_create_your_first_repository'))
    await user.click(screen.getByTestId('resource-card-creating_a_pull_request'))
    await user.click(screen.getByTestId('resource-card-what_is_github_copilot'))
    await user.click(screen.getByTestId('resource-card-github_flow'))
    await user.click(screen.getByTestId('resource-card-hello_world_exercise'))
    await user.click(screen.getByTestId('resource-card-copilot_chat_cookbook'))

    expectAnalyticsEvents(
      {
        type: 'analytics.click',
        data: {
          category: 'zero_user_dashboard',
          action: 'click.docs.resource_card.github_documentation',
        },
      },
      {
        type: 'analytics.click',
        data: {
          category: 'zero_user_dashboard',
          action: 'click.docs.resource_card.about_github_and_git',
        },
      },
      {
        type: 'analytics.click',
        data: {
          category: 'zero_user_dashboard',
          action: 'click.docs.resource_card.how_to_create_your_first_repository',
        },
      },
      {
        type: 'analytics.click',
        data: {
          category: 'zero_user_dashboard',
          action: 'click.docs.resource_card.creating_a_pull_request',
        },
      },
      {
        type: 'analytics.click',
        data: {
          category: 'zero_user_dashboard',
          action: 'click.docs.resource_card.what_is_github_copilot',
        },
      },
      {
        type: 'analytics.click',
        data: {
          category: 'zero_user_dashboard',
          action: 'click.docs.resource_card.github_flow',
        },
      },
      {
        type: 'analytics.click',
        data: {
          category: 'zero_user_dashboard',
          action: 'click.docs.resource_card.hello_world_exercise',
        },
      },
      {
        type: 'analytics.click',
        data: {
          category: 'zero_user_dashboard',
          action: 'click.docs.resource_card.copilot_chat_cookbook',
        },
      },
    )
  })

  test('Sends analytics events for recommendations', async () => {
    const {user} = render(<NuxDashboardRefresh {...props} />)

    await user.click(screen.getByTestId('download-banner-download_visual_studio_with_copilot-download'))
    await user.click(screen.getByTestId('download-banner-download_github_for_desktop-download'))

    expectAnalyticsEvents(
      {
        type: 'analytics.click',
        data: {
          category: 'zero_user_dashboard',
          action: 'click.recommendations.download_banner.download_visual_studio_with_copilot.download',
        },
      },
      {
        type: 'analytics.click',
        data: {
          category: 'zero_user_dashboard',
          action: 'click.recommendations.download_banner.download_github_for_desktop.download',
        },
      },
    )
  })
})
