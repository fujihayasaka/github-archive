import {LABELS} from '../constants/labels'

export function blockedCommentingReason(
  isRepoArchived: boolean,
  isReferenceLocked: boolean,
  customReason: string | JSX.Element | null | undefined = null,
  subjectType: string = 'issue',
) {
  if (isRepoArchived) return LABELS.repoArchived
  if (isReferenceLocked) return LABELS.issueLockedToCollaborators
  if (customReason) return customReason

  return LABELS.canNotComment(subjectType)
}
