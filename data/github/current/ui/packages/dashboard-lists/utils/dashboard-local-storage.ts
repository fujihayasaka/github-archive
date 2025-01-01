import safeStorage from '@github-ui/safe-storage'
import {PullRequestQueryQualifier} from '../types'
import {RESULT_COUNTS} from '../components/PullRequestActionMenu'

export class DashboardLocalStorage {
  private NINETY_DAYS_IN_MS = 1000 * 60 * 60 * 24 * 90
  private DASHBOARD_COPILOT_ISSUE_SUMMARY_PROMPT_KEY = 'DASHBOARD_COPILOT_ISSUE_SUMMARY_PROMPT_KEY'
  private DASHBOARD_COPILOT_ISSUE_SUMMARY_TEMPERATURE_KEY = 'DASHBOARD_COPILOT_ISSUE_SUMMARY_TEMPERATURE_KEY'
  private DASHBOARD_PULL_REQUEST_QUERY_QUALIFIERS_KEY = 'DASHBOARD_PULL_REQUEST_QUERY_QUALIFIERS_KEY'
  private DASHBOARD_PULL_REQUEST_RESULT_COUNT_KEY = 'DASHBOARD_PULL_REQUEST_RESULT_COUNT_KEY'
  DEFAULT_TEMPERATURE = 0.5

  private localStorage = safeStorage('localStorage', {
    throwQuotaErrorsOnSet: false,
    ttl: this.NINETY_DAYS_IN_MS,
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

  getQueryQualifiers(): PullRequestQueryQualifier[] | null {
    const value = this.localStorage.getItem(this.DASHBOARD_PULL_REQUEST_QUERY_QUALIFIERS_KEY)
    if (!value) {
      return null
    }

    const parsed = JSON.parse(value) as PullRequestQueryQualifier[]
    const filtered = parsed.filter(qualifier => Object.values(PullRequestQueryQualifier).includes(qualifier))
    if (filtered.length === 0) {
      return null
    }

    return filtered
  }

  setQueryQualifiers(queryQualifiers: PullRequestQueryQualifier[]) {
    this.localStorage.setItem(this.DASHBOARD_PULL_REQUEST_QUERY_QUALIFIERS_KEY, JSON.stringify(queryQualifiers))
  }

  getPullRequestResultCount(): number | null {
    const value = this.localStorage.getItem(this.DASHBOARD_PULL_REQUEST_RESULT_COUNT_KEY)
    if (!value) {
      return null
    }

    const count = parseInt(value, 10)
    if (!RESULT_COUNTS.includes(count)) {
      return null
    }

    return count
  }

  setPullRequestResultCount(count: number) {
    this.localStorage.setItem(this.DASHBOARD_PULL_REQUEST_RESULT_COUNT_KEY, count.toString())
  }
}

export const dashboardLocalStorage = new DashboardLocalStorage()
