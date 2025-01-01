import {useState} from 'react'
import {CardBanner} from './CardBanner/CardBanner'
import {VideoPreview} from './VideoPreview/VideoPreview'
import {updateSetting} from '../../helpers/settings-helper'
import {DashboardDismissalSettings} from '../../constants/dashboard-settings'
import {useClickAnalytics} from '@github-ui/use-analytics'

interface BeginnersPlaylistProps {
  dismissed: boolean
}

export default function BeginnersPlaylist({dismissed}: BeginnersPlaylistProps) {
  const [isDismissed, setIsDismissed] = useState<boolean>(dismissed)

  const {sendClickAnalyticsEvent} = useClickAnalytics()

  const handleDismiss = () => {
    setIsDismissed(true)
    updateSetting(DashboardDismissalSettings.Playlist, true)

    sendClickAnalyticsEvent({
      category: 'zero_user_dashboard',
      action: 'click.playlist.dismiss',
    })
  }

  const youtubeLink = 'https://www.youtube.com/watch?v=r8jQ9hVA2qs&list=PL0lo9MOBetEFcp4SCWinBdpml9B2U25-f'

  return isDismissed ? null : (
    <section aria-label="GitHub for beginners on YouTube" data-testid="beginners-playlist-section">
      <CardBanner
        label="Playlist"
        title="GitHub for beginners on YouTube"
        description={`Designed to help you master the basics of GitHub, whether you're new to coding or looking to enhance your version control skills.`}
        buttonText="Start playlist"
        buttonHref={youtubeLink}
        onDismiss={handleDismiss}
        pattern
        content={
          <VideoPreview
            imageSrc="images/modules/dashboard/onboarding/beginners-video-thumbnail.webp"
            href={youtubeLink}
          />
        }
      />
    </section>
  )
}
