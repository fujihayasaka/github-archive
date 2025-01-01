import {BaseSectionStatus} from './base-section-status'

type ClosedOrMergedStateSectionStatusType = 'CLOSED' | 'MERGED' | 'UNKNOWN'

export class ClosedOrMergedStateSectionStatus extends BaseSectionStatus<ClosedOrMergedStateSectionStatusType> {
  override get shouldRender() {
    return this.pullRequest.state !== 'OPEN'
  }

  // If the section renders, then the PR is closed or merged
  override get sectionStatus() {
    if (this.pullRequest.state !== 'OPEN') {
      return this.pullRequest.state
    }

    return 'UNKNOWN'
  }

  override get mergeBoxStatus() {
    if (this.sectionStatus === 'MERGED') {
      return 'MERGED'
    } else {
      return 'NEUTRAL'
    }
  }
}
