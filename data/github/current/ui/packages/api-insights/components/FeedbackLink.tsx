import {Link} from '@primer/react'
import {useClickAnalytics} from '@github-ui/use-analytics'

export interface FeedbackLinkProps {
  url: string
}

export function FeedbackLink({url}: FeedbackLinkProps) {
  const {sendClickAnalyticsEvent} = useClickAnalytics()
  return (
    <Link
      aria-label="Send feedback"
      href={url}
      onClick={() => {
        sendClickAnalyticsEvent({
          category: 'api_insights',
          action: 'click_feedback_link',
          label: 'ref_cta:give_feedback_about_this_page',
        })
      }}
    >
      Send feedback
    </Link>
  )
}
