import {GrowthBanner} from '@github-ui/growth-banner'
import {verifiedFetch} from '@github-ui/verified-fetch'
import {CopilotIcon} from '@primer/octicons-react'
import {useState} from 'react'

export interface CopilotSurveyProps {
  surveyLink: string
  surveyOpenCallbackPath: string
  surveyDismissCallbackPath: string
}

export function CopilotSurvey({surveyLink, surveyOpenCallbackPath, surveyDismissCallbackPath}: CopilotSurveyProps) {
  const [showBanner, setShowBanner] = useState(true)
  if (!showBanner) return null

  const handleDismiss = async () => {
    setShowBanner(false)
    await verifiedFetch(surveyDismissCallbackPath, {method: 'POST'})
  }

  const handleOpen = async () => {
    await verifiedFetch(surveyOpenCallbackPath, {method: 'POST'})
    setShowBanner(false)
    // eslint-disable-next-line react-compiler/react-compiler
    window.location.href = surveyLink
  }

  return (
    <GrowthBanner
      variant="information"
      title="Help us improve GitHub Copilot"
      icon={CopilotIcon}
      closeButtonClick={handleDismiss}
      primaryButtonProps={{
        onClick: handleOpen,
        children: 'Sign up',
      }}
    >
      {"We'd love to hear your thoughts on Copilot! If selected, you’ll receive a $40 gift card."}
    </GrowthBanner>
  )
}
