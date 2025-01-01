import {useState, type Dispatch, type SetStateAction} from 'react'
import {Heading, Button, IconButton} from '@primer/react'
import {XIcon} from '@primer/octicons-react'
import styles from './DownloadBanner.module.css'
import {updateSetting} from '../../../helpers/settings-helper'
import {useClickAnalytics} from '@github-ui/use-analytics'
import type {RecommendationKey, RecommendationDismissals} from '../../../types/recommendations-types'

export interface DownloadBannerProps {
  recommendationKey: RecommendationKey
  image: string
  title: string
  description: string
  downloadLink: string
  openInNewTab?: boolean
  dismissed: boolean
  dismissalSetting: string
  setDismissedRecommendations: Dispatch<SetStateAction<RecommendationDismissals>>
}

export function DownloadBanner({
  recommendationKey,
  image,
  title,
  description,
  downloadLink,
  openInNewTab = false,
  dismissed,
  dismissalSetting,
  setDismissedRecommendations,
}: DownloadBannerProps) {
  const [isDismissed, setIsDismissed] = useState<boolean>(dismissed)

  // Turns title into a lowercase string with underscores and removes non-word characters
  const sanitizedTitle = title
    .toLowerCase()
    .replace(/\s+/g, '_')
    .replace(/[^\w_]/g, '')

  const {sendClickAnalyticsEvent} = useClickAnalytics()

  const handleDismiss = () => {
    setIsDismissed(true)
    setDismissedRecommendations(prev => ({
      ...prev,
      [recommendationKey]: true,
    }))

    updateSetting(dismissalSetting, true)

    sendClickAnalyticsEvent({
      category: 'zero_user_dashboard',
      action: `click.recommendations.download_banner.${sanitizedTitle}.dismiss`,
    })
  }

  return isDismissed ? null : (
    <div
      className="border rounded-2 p-3 d-flex flex-column flex-md-row gap-3 position-relative"
      data-testid={`download-banner-${sanitizedTitle}`}
    >
      <img src={image} alt={title} className={styles.icon} />
      <div>
        <Heading as="h3" className="text-bold f5 mb-1">
          {title}
        </Heading>
        <p className="fgColor-muted">{description}</p>
        <Button
          as="a"
          href={downloadLink}
          target={openInNewTab ? '_blank' : undefined}
          rel={openInNewTab ? 'noopener noreferrer' : undefined}
          aria-label={title}
          onClick={() => {
            sendClickAnalyticsEvent({
              category: 'zero_user_dashboard',
              action: `click.recommendations.download_banner.${sanitizedTitle}.download`,
            })
          }}
          data-testid={`download-banner-${sanitizedTitle}-download`}
        >
          Download
        </Button>
      </div>
      <IconButton
        aria-label="Dismiss"
        data-testid={`download-banner-${sanitizedTitle}-dismiss`}
        size="small"
        variant="invisible"
        icon={XIcon}
        className={styles.dismissButton}
        onClick={handleDismiss}
      />
    </div>
  )
}
