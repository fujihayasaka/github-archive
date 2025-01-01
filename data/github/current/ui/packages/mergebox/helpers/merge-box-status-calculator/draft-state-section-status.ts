import {BaseSectionStatus} from './base-section-status'
import type {MergeBoxSectionStatus} from './types'

type DraftStateSectionStatusType = 'IS_DRAFT'

export class DraftStateSectionStatus extends BaseSectionStatus<DraftStateSectionStatusType> {
  override get shouldRender() {
    return this.pullRequest.state === 'OPEN' && this.pullRequest.isDraft
  }

  // If the section renders, then it's a draft.
  override get sectionStatus() {
    const status: DraftStateSectionStatusType = 'IS_DRAFT'
    return status
  }

  // Neutral maps to neutral, so we can just return this.
  override get mergeBoxStatus() {
    const status: MergeBoxSectionStatus = 'NEUTRAL'
    return status
  }
}
