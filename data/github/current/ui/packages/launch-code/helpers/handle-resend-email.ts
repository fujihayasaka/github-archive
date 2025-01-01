import type {AnalyticsEvent} from '@github-ui/use-analytics'
import {verifiedFetch} from '@github-ui/verified-fetch'

interface ResendEmailParams {
  resendVerificationPath: string
  sendAnalyticsEvent: (eventType: string, target: string, payload?: {[key: string]: unknown} | AnalyticsEvent) => void
  setEmailResent: (value: boolean) => void
}

export const handleResendEmail = async ({
  resendVerificationPath,
  sendAnalyticsEvent,
  setEmailResent,
}: ResendEmailParams): Promise<void> => {
  setEmailResent(false)
  const resendEmailButton = 'RESEND_EMAIL_BUTTON'
  try {
    const result = await verifiedFetch(resendVerificationPath, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
      },
    })
    if (result.status === 200) {
      setEmailResent(true)
      sendAnalyticsEvent('launch-code.resend_email_success', resendEmailButton)
    } else {
      // We do not show errors on the UI of the current Rails version, so we'll log the errors for now.
      sendAnalyticsEvent('launch-code.resend_email_failure', resendEmailButton, {result})
    }
  } catch (error) {
    sendAnalyticsEvent('launch-code.resend_email_error', resendEmailButton, {error})
  }
}
