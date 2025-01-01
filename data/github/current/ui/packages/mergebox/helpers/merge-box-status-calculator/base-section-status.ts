import type {JSONAPIPullRequestPayload, PullRequestMergeRequirementsPayload} from '../../page-data/payloads/merge-box'
import type {StatusChecksPageData} from '../../page-data/payloads/status-checks'
import type {MergeBoxSectionStatus} from './types'

/**
 * Base section status class that all other section status classes extend.
 *
 * Defines the minimum properties and methods that all section status classes must have.
 * Accepts a generic type T so that we can define the section-specific status types for each subclass.
 */
export class BaseSectionStatus<T> {
  pullRequest: JSONAPIPullRequestPayload
  mergeRequirements: PullRequestMergeRequirementsPayload | null
  statusChecks: StatusChecksPageData | undefined

  constructor(
    pullRequest: JSONAPIPullRequestPayload,
    mergeRequirements: PullRequestMergeRequirementsPayload | null,
    statusChecks: StatusChecksPageData | undefined,
  ) {
    this.pullRequest = pullRequest
    this.mergeRequirements = mergeRequirements
    this.statusChecks = statusChecks
  }

  /**
   * Whether the section should render
   */
  get shouldRender(): boolean {
    return false
  }

  /**
   * Whether the status calculator should consider the status
   */
  get shouldConsiderStatus(): boolean {
    return this.shouldRender
  }

  /**
   * The section-specific status.
   * Not all sections use this, but those that do have specific statuses that map to different presentational logic in the component.
   */
  get sectionStatus(): T {
    return 'UNKNOWN' as T
  }

  /**
   * Maps the section-specific status to a status the merge box understands.
   * This will be used by the calculator to determine the more nuanced state of the merge box.
   */
  get mergeBoxStatus(): MergeBoxSectionStatus {
    return 'UNKNOWN'
  }
}
