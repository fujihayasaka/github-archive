// Read requests for GET action
const Reads = {
  codeButton: 'code_button',
  commits: 'commits',
  diffstat: 'diffstat',
  fileTree: 'file_tree',
  header: 'header',
  mergeBox: 'merge_box',
  mergeInstructions: 'merge_instructions',
  pendingReview: 'pending_review',
  statusChecks: 'status_checks',
  tabCounts: 'tab_counts',
  threadPreviews: 'thread_previews',
  //this was used for the interactions between rails/file tree, it hasn't been removed yet but we can remove
  //it eventually
  viewedFilesCount: 'viewed_files_count',
  viewedFilesCount2: 'viewed_files_count2',
  diffSummaries: 'diff_summaries',
  diffViewUserSettings: 'user_diff_view_settings',
  diffCollapsedStatus: 'diff_collapsed_status',
}

// Mutation requests for PUT, POST, PATCH, DELETE actions
const Mutations = {
  abandonReview: 'abandon_review',
  changeBase: 'change_base',
  cleanupCodespaces: 'cleanup_codespaces',
  deleteHeadRef: 'delete_head_ref',
  dequeuePullRequest: 'dequeue_pull_request',
  disableAutoMerge: 'disable_auto_merge',
  enableAutoMerge: 'enable_auto_merge',
  dismissReview: 'dismiss_review',
  markReadyForReview: 'mark_ready_for_review',
  merge: 'merge',
  reRequestReviewFromUser: 're_request_review_from_user',
  restoreHeadRef: 'restore_head_ref',
  runActionRequiredWorkflows: 'run_action_required_workflows',
  submitReview: 'submit_review',
  updatePullRequestBranch: 'update_pull_request_branch',
  updateTitle: 'update_title',
  updateDiffViewUserSettings: 'update_diff_view_user_settings',
  updateViewedFiles: 'update_viewed_files',
}

export const PageData = {
  ...Reads,
  ...Mutations,
} as const

export type PageDataKey = keyof typeof PageData
export type PageDataName = (typeof PageData)[PageDataKey]
