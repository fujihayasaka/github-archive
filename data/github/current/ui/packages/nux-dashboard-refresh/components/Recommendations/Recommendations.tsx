import {ActionList, ActionMenu, Heading, IconButton, Stack} from '@primer/react'
import {KebabHorizontalIcon} from '@primer/octicons-react'
import {DownloadBanner, type DownloadBannerProps} from './DownloadBanner/DownloadBanner'
import {useEffect, useState} from 'react'
import {updateSetting} from '../../helpers/settings-helper'
import {DashboardDismissalSettings} from '../../constants/dashboard-settings'
import {useClickAnalytics} from '@github-ui/use-analytics'
import type {RecommendationDismissals} from '../../types/recommendations-types'

interface RecommendationsProps {
  dismissed: boolean
  recommendationDismissals: RecommendationDismissals
}

export const Recommendations = ({dismissed, recommendationDismissals}: RecommendationsProps) => {
  const [dismissedRecommendations, setDismissedRecommendations] = useState<RecommendationDismissals>({
    ...recommendationDismissals,
  })

  const downloadBanners: DownloadBannerProps[] = [
    {
      recommendationKey: 'vscodeDismissed',
      image: 'images/modules/dashboard/onboarding/vscode2025.svg',
      title: 'Download Visual Studio with Copilot',
      description:
        'Chat with Copilot to build your first website, troubleshoot your code, or guide you through your GitHub journey.',
      downloadLink: 'https://code.visualstudio.com/download',
      openInNewTab: true,
      dismissed: recommendationDismissals.vscodeDismissed,
      dismissalSetting: DashboardDismissalSettings.VSCode,
      setDismissedRecommendations,
    },
    {
      recommendationKey: 'desktopDismissed',
      image: 'images/modules/dashboard/onboarding/github-desktop.svg',
      title: 'Download GitHub for Desktop',
      description:
        'GitHub Desktop simplifies Git workflows and brings core GitHub features to your desktop, helping developers of all levels focus on building and collaborating effectively.',
      downloadLink: 'https://desktop.github.com/',
      dismissed: recommendationDismissals.desktopDismissed,
      dismissalSetting: DashboardDismissalSettings.Desktop,
      setDismissedRecommendations,
    },
  ]

  const [isDismissed, setIsDismissed] = useState<boolean>(dismissed)

  const {sendClickAnalyticsEvent} = useClickAnalytics()

  const handleDismiss = () => {
    setIsDismissed(true)
    updateSetting(DashboardDismissalSettings.Recommendations, true)

    sendClickAnalyticsEvent({
      category: 'zero_user_dashboard',
      action: 'click.recommendations.dismiss',
    })
  }

  // When all recommendations are dismissed, set the section as dismissed
  // and update the setting to reflect this state to avoid showing it again
  useEffect(() => {
    if (!isDismissed && Object.values(dismissedRecommendations).every(Boolean)) {
      setIsDismissed(true)
      updateSetting(DashboardDismissalSettings.Recommendations, true)
    }
  }, [dismissedRecommendations, isDismissed])

  return isDismissed ? null : (
    <section aria-labelledby="recommendations-heading" data-testid="recommendations-section">
      <Stack direction="vertical" gap="normal" className="mb-3">
        <Stack direction="horizontal" gap="condensed" justify="space-between" align="center">
          <Heading id="recommendations-heading" as="h2" className="h5">
            {'Recommendations'}
          </Heading>
          <ActionMenu>
            <ActionMenu.Anchor>
              <IconButton
                icon={KebabHorizontalIcon}
                aria-label="Remove section"
                variant="invisible"
                data-testid="recommendations-options"
              />
            </ActionMenu.Anchor>
            <ActionMenu.Overlay align="end">
              <ActionList>
                <ActionList.LinkItem onClick={handleDismiss} data-testid="recommendations-remove-option">
                  Remove from dashboard
                </ActionList.LinkItem>
              </ActionList>
            </ActionMenu.Overlay>
          </ActionMenu>
        </Stack>
        {downloadBanners.map(banner => (
          <DownloadBanner
            key={banner.title}
            recommendationKey={banner.recommendationKey}
            image={banner.image}
            title={banner.title}
            description={banner.description}
            downloadLink={banner.downloadLink}
            openInNewTab={banner.openInNewTab}
            dismissed={banner.dismissed}
            dismissalSetting={banner.dismissalSetting}
            setDismissedRecommendations={banner.setDismissedRecommendations}
          />
        ))}
      </Stack>
    </section>
  )
}

export default Recommendations
