import safeStorage from '@github-ui/safe-storage'

export class DashboardLocalStorage {
  private DASHBOARD_COPILOT_ISSUE_SUMMARY_PROMPT_KEY = 'DASHBOARD_COPILOT_ISSUE_SUMMARY_PROMPT_KEY'
  private DASHBOARD_COPILOT_ISSUE_SUMMARY_TEMPERATURE_KEY = 'DASHBOARD_COPILOT_ISSUE_SUMMARY_TEMPERATURE_KEY'
  DEFAULT_TEMPERATURE = 0.5

  private localStorage = safeStorage('localStorage', {
    throwQuotaErrorsOnSet: false,
    ttl: 1000 * 60 * 60 * 24,
  })

  getIssueSummaryPrompt(): string | null {
    return this.localStorage.getItem(this.DASHBOARD_COPILOT_ISSUE_SUMMARY_PROMPT_KEY)
  }

  setIssueSummaryPrompt(prompt: string | null) {
    if (prompt != null) {
      this.localStorage.setItem(this.DASHBOARD_COPILOT_ISSUE_SUMMARY_PROMPT_KEY, prompt)
    }
  }

  getIssueSummaryTemperature(): number | null {
    const value = this.localStorage.getItem(this.DASHBOARD_COPILOT_ISSUE_SUMMARY_TEMPERATURE_KEY)
    return value ? parseFloat(value) : null
  }

  setIssueSummaryTemperature(temperature: number | null) {
    if (temperature != null) {
      this.localStorage.setItem(this.DASHBOARD_COPILOT_ISSUE_SUMMARY_TEMPERATURE_KEY, temperature.toString())
    }
  }
}

export const dashboardLocalStorage = new DashboardLocalStorage()
