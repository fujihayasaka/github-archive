import safeStorage from '@github-ui/safe-storage'
import type {SummaryFeedbackSentiment} from './types'

const safeLocalStorage = safeStorage('localStorage')

interface SummaryCacheOptions {
  /**
   * A unique identifier for the content being summarized, such as a URL or database table name + primary key.
   */
  contentIdentifier: string
}

export default class SummaryCache {
  static readonly keyPrefix = 'copilot-summary'

  private _summaryKey: string
  private _summaryMDKey: string
  private _summaryFeedbackSentimentKey: string
  private _summaryTimestampKey: string

  constructor({contentIdentifier}: SummaryCacheOptions) {
    this._summaryKey = `${SummaryCache.keyPrefix}${contentIdentifier}`
    this._summaryMDKey = `${SummaryCache.keyPrefix}-MD${contentIdentifier}`
    this._summaryFeedbackSentimentKey = `${SummaryCache.keyPrefix}-feedback${contentIdentifier}`
    this._summaryTimestampKey = `${SummaryCache.keyPrefix}-timestamp${contentIdentifier}`
  }

  getSummary(): string | null {
    return safeLocalStorage.getItem(this._summaryKey)
  }

  getSummaryMarkdown(): string | null {
    return safeLocalStorage.getItem(this._summaryMDKey)
  }

  getSummaryFeedbackSentiment(): SummaryFeedbackSentiment | null {
    const value = safeLocalStorage.getItem(this._summaryFeedbackSentimentKey)
    if (value) return value as SummaryFeedbackSentiment
    return null
  }

  getSummaryTimestamp(): number {
    const value = safeLocalStorage.getItem(this._summaryTimestampKey)
    if (!value) return 0

    const timestamp = +value
    return isNaN(timestamp) ? 0 : timestamp
  }

  setSummary({
    summary,
    summaryMarkdown,
    summaryTimestamp,
  }: {
    summary: string
    summaryMarkdown: string
    summaryTimestamp: number
  }) {
    safeLocalStorage.setItem(this._summaryKey, summary)
    safeLocalStorage.setItem(this._summaryMDKey, summaryMarkdown)
    safeLocalStorage.setItem(this._summaryTimestampKey, summaryTimestamp.toString())
  }

  setSummaryFeedbackSentiment(sentiment: SummaryFeedbackSentiment) {
    safeLocalStorage.setItem(this._summaryFeedbackSentimentKey, sentiment)
  }

  clear() {
    safeLocalStorage.removeItem(this._summaryKey)
    safeLocalStorage.removeItem(this._summaryFeedbackSentimentKey)
    safeLocalStorage.removeItem(this._summaryTimestampKey)
  }
}
