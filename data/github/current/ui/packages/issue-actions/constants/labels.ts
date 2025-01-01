export const LABELS = {
  actionListCompletedDescription: 'Done, closed, fixed, resolved',
  actionListNotPlannedDescription: "Won't fix, can't repro, duplicate, stale", // should we removed once issues_react_close_as_duplicate is promoted
  actionListNotPlannedNewDescription: "Won't fix, can't repro, stale",
  actionListDuplicateDescription: 'Duplicate of another issue',
  closeIssue: 'Close issue',
  closeIssueWithComment: 'Close with comment',
  closeAsCompleted: 'Close as completed',
  closeAsNotPlanned: 'Close as not planned',
  closeAsDuplicate: 'Close as duplicate',
  closeAsDuplicateOf: (issueNumber: number) => `Close as duplicate of #${issueNumber}`,
  moreOptions: 'More options',
  reOpenIssue: 'Reopen Issue',
  updateIssueRoleDescription: 'update issue state options menu',
}
