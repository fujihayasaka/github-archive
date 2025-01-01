import {GrowthBanner} from '@github-ui/growth-banner'
import {verifiedFetch} from '@github-ui/verified-fetch'
import {CopilotIcon} from '@primer/octicons-react'
import {useState} from 'react'

export interface CopilotSurveyProps {
  bannerTitle: string
  bannerText: string
  ctaText: string
  ctaUrl: string
  bannerSlug: string
  surveyOpenCallbackPath: string
  surveyDismissCallbackPath: string
}

export function CopilotSurvey({
  bannerTitle,
  bannerText,
  ctaText,
  ctaUrl,
  bannerSlug,
  surveyOpenCallbackPath,
  surveyDismissCallbackPath,
}: CopilotSurveyProps) {
  const [showBanner, setShowBanner] = useState(true)
  if (!showBanner) return null

  const handleDismiss = async () => {
    setShowBanner(false)

    await verifiedFetch(surveyDismissCallbackPath, {
      method: 'POST',
      body: JSON.stringify({slug: bannerSlug}),
      headers: {
        'Content-Type': 'application/json',
      },
    })
  }

  const handleOpen = async () => {
    await verifiedFetch(surveyOpenCallbackPath, {
      method: 'POST',
      body: JSON.stringify({slug: bannerSlug}),
      headers: {
        'Content-Type': 'application/json',
      },
    })
    setShowBanner(false)
    // eslint-disable-next-line react-compiler/react-compiler
    window.location.href = ctaUrl
  }

  return (
    <GrowthBanner
      variant="information"
      title={bannerTitle}
      icon={CopilotIcon}
      closeButtonClick={handleDismiss}
      primaryButtonProps={{
        onClick: handleOpen,
        children: ctaText,
      }}
    >
      {bannerText}
    </GrowthBanner>
  )
}
