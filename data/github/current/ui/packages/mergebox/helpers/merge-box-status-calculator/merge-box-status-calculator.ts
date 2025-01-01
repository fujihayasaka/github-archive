import type {JSONAPIPullRequestPayload, PullRequestMergeRequirementsPayload} from '../../page-data/payloads/merge-box'
import type {StatusChecksPageData} from '../../page-data/payloads/status-checks'
import {BlockedSectionStatus} from './blocked-section-status'
import {ChecksSectionStatus} from './checks-section-status'
import {ClosedOrMergedStateSectionStatus} from './closed-or-merged-state-section-status'
import {ConflictsSectionStatus} from './conflicts-section-status'
import {DraftStateSectionStatus} from './draft-state-section-status'
import {MergeQueueSectionStatus} from './merge-queue-section-status'
import {ReviewerSectionStatus} from './reviewer-section-status'
import type {MergeBoxRollupStatus} from './types'

type Sections = {
  BlockedSection: BlockedSectionStatus
  ChecksSection: ChecksSectionStatus
  ClosedOrMergedStateMergeBox: ClosedOrMergedStateSectionStatus
  ConflictsSection: ConflictsSectionStatus
  DraftStateSection: DraftStateSectionStatus
  MergeQueueSection: MergeQueueSectionStatus
  ReviewerSection: ReviewerSectionStatus
}

/**
 * Derives the status of the merge box based on the status of each section
 *
 * Each section corresponds to an immediate child of the `MergeBox` component
 * The status will be used to determine the color of the border, the icon color of each section, and the color of the merge box button
 */
export class MergeBoxStatusCalculator {
  #pullRequest: JSONAPIPullRequestPayload
  #mergeRequirements: PullRequestMergeRequirementsPayload | null
  #statusChecks: StatusChecksPageData | undefined
  #sectionsInternal: Sections

  constructor(
    pullRequest: JSONAPIPullRequestPayload,
    mergeRequirements: PullRequestMergeRequirementsPayload | null,
    statusChecks: StatusChecksPageData | undefined,
  ) {
    this.#pullRequest = pullRequest
    this.#mergeRequirements = mergeRequirements
    this.#statusChecks = statusChecks
    this.#sectionsInternal = this.setSections()
  }

  get overallStatus(): MergeBoxRollupStatus {
    if (this.#pullRequest.state === 'MERGED') return 'MERGED'
    if (this.#pullRequest.state === 'CLOSED') return 'NEUTRAL'
    if (this.#pullRequest.isInMergeQueue) return 'QUEUED'
    if (this.#pullRequest.isDraft) return 'NEUTRAL'

    // Only consider the sections that will be rendered
    const relevantStatuses = Object.values(this.sections ?? []).filter(section => section.shouldConsiderStatus)

    const anyFailed = relevantStatuses.some(section => section.mergeBoxStatus === 'FAILED')
    const allPassed = relevantStatuses.every(section => section.mergeBoxStatus === 'PASSED')

    if (anyFailed && this.#pullRequest.viewerCanUpdate) {
      return 'SOME_FAILED'
    } else if (allPassed) {
      return 'ALL_PASSED'
    } else {
      return 'NEUTRAL'
    }
  }

  get sections() {
    return this.#sectionsInternal
  }

  private setSections(): Sections {
    return {
      BlockedSection: new BlockedSectionStatus(this.#pullRequest, this.#mergeRequirements, this.#statusChecks),
      ClosedOrMergedStateMergeBox: new ClosedOrMergedStateSectionStatus(
        this.#pullRequest,
        this.#mergeRequirements,
        this.#statusChecks,
      ),
      ChecksSection: new ChecksSectionStatus(this.#pullRequest, this.#mergeRequirements, this.#statusChecks),
      ConflictsSection: new ConflictsSectionStatus(this.#pullRequest, this.#mergeRequirements, this.#statusChecks),
      DraftStateSection: new DraftStateSectionStatus(this.#pullRequest, this.#mergeRequirements, this.#statusChecks),
      MergeQueueSection: new MergeQueueSectionStatus(this.#pullRequest, this.#mergeRequirements, this.#statusChecks),
      ReviewerSection: new ReviewerSectionStatus(this.#pullRequest, this.#mergeRequirements, this.#statusChecks),
    }
  }
}
