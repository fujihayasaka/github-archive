import {controller} from '@github/catalyst'
import {sendEvent} from '@github-ui/hydro-analytics'
import {verifiedFetch} from '@github-ui/verified-fetch'

@controller
export class CopilotDashboardNoQuotaElement extends HTMLElement {
  handleDismissClick() {
    const formData = new FormData()
    // setting the value to the resetDate will hide the element until the next reset
    formData.set('copilot_dashboard_quota_notification_dismissed', this.resetDate())
    verifiedFetch('/github-copilot/preferences', {
      method: 'PUT',
      body: formData,
      headers: {Accept: 'application/json'},
    })

    sendEvent('dotcom_chat.activate', {
      target: 'DASHBOARD_ENTRYPOINT_NO_QUOTA_DISMISS',
      mode: 'immersive',
    })

    this.remove()
  }

  private resetDate = () => this.getAttribute('data-reset-date') || ''
}
