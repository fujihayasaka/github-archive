import {BaseSectionStatus} from './base-section-status'

type MergeQueueSectionStatusType = 'QUEUED'

export class MergeQueueSectionStatus extends BaseSectionStatus<MergeQueueSectionStatusType> {
  override get shouldRender() {
    return this.pullRequest.isInMergeQueue
  }

  // If the section renders, then it's in the merge queue.
  override get sectionStatus() {
    const status: MergeQueueSectionStatusType = 'QUEUED'
    return status
  }

  override get mergeBoxStatus() {
    return this.sectionStatus
  }
}
