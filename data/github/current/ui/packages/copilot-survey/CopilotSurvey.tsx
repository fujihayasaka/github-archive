import {GrowthBanner} from '@github-ui/growth-banner'
import {useMutation} from '@github-ui/react-query'
import {reactFetchJSON} from '@github-ui/verified-fetch'
import type {Icon} from '@primer/octicons-react'
import {CopilotIcon, ShieldIcon} from '@primer/octicons-react'
import {useState} from 'react'

/**
 * Returns the appropriate icon based on the provided icon parameter.
 * Maps string icon names to their corresponding Icon components.
 * If the icon is not a string or not recognized, returns the icon as is.
 * If no icon is provided, returns CopilotIcon as default.
 */
function getBannerIcon(icon?: Icon | string): Icon {
  // Explicit check for undefined as a guard statement at the top of the function
  if (icon === undefined) {
    return CopilotIcon
  }

  if (typeof icon === 'string') {
    switch (icon) {
      case 'copilot':
        return CopilotIcon
      case 'shield':
        return ShieldIcon
      // Additional icon cases can be added here
      default:
        // If string is not recognized, use CopilotIcon as default
        return CopilotIcon
    }
  }

  // Return the icon as provided (since we already checked for undefined above)
  return icon
}

export interface CopilotSurveyProps {
  bannerTitle: string
  bannerText: string
  ctaText: string
  ctaUrl: string
  bannerSlug: string
  surveyOpenCallbackPath: string
  surveyDismissCallbackPath: string
  icon?: Icon | string
}

export function CopilotSurvey({
  bannerTitle,
  bannerText,
  ctaText,
  ctaUrl,
  bannerSlug,
  surveyOpenCallbackPath,
  surveyDismissCallbackPath,
  icon,
}: CopilotSurveyProps) {
  const [showBanner, setShowBanner] = useState(true)

  const dismissMutation = useMutation({
    mutationFn: async () => {
      // banner is hidden regardless of the response, but may show again on reload if backend encounters an error
      setShowBanner(false)
      const response = await reactFetchJSON(surveyDismissCallbackPath, {
        method: 'POST',
        body: {slug: bannerSlug},
      })

      if (!response.ok) {
        throw new Error('Failed to dismiss survey')
      }

      return response
    },
  })

  const openMutation = useMutation({
    mutationFn: async () => {
      // Don't wait for the request to complete, but keep it alive after page navigation
      // This optimizes for slow connections - user doesn't need to wait for the API call to complete
      reactFetchJSON(surveyOpenCallbackPath, {
        method: 'POST',
        body: {slug: bannerSlug},
        keepalive: true,
        // eslint-disable-next-line github/no-then
      }).catch(() => {
        // Silently catch errors - we're already navigating away
        // and failures are acceptable here as per the original implementation
      })

      // eslint-disable-next-line react-hooks/react-compiler
      window.location.href = ctaUrl
      return {} // Return something to satisfy the mutation signature
    },
  })

  if (!showBanner) return null

  return (
    <GrowthBanner
      variant="information"
      title={bannerTitle}
      icon={getBannerIcon(icon)}
      closeButtonClick={() => dismissMutation.mutate()}
      primaryButtonProps={{
        onClick: () => openMutation.mutate(),
        children: ctaText,
      }}
    >
      {bannerText}
    </GrowthBanner>
  )
}
