// Read requests for GET action
const Reads = {
  codeButton: 'code_button',
  commits: 'commits',
  header: 'header',
  mergeBox: 'merge_box',
  mergeInstructions: 'merge_instructions',
  statusChecks: 'status_checks',
  tabCounts: 'tab_counts',
  viewedFilesCount: 'viewed_files_count',
}

// Mutation requests for PUT, POST, PATCH, DELETE actions
const Mutations = {
  changeBase: 'change_base',
  deleteHeadRef: 'delete_head_ref',
  dequeuePullRequest: 'dequeue_pull_request',
  disableAutoMerge: 'disable_auto_merge',
  enableAutoMerge: 'enable_auto_merge',
  dismissReview: 'dismiss_review',
  markReadyForReview: 'mark_ready_for_review',
  merge: 'merge',
  reRequestReviewFromUser: 're_request_review_from_user',
  restoreHeadRef: 'restore_head_ref',
  updatePullRequestBranch: 'update_pull_request_branch',
  updateTitle: 'update_title',
}

export const PageData = {
  ...Reads,
  ...Mutations,
} as const

export type PageDataKey = keyof typeof PageData
export type PageDataName = (typeof PageData)[PageDataKey]
