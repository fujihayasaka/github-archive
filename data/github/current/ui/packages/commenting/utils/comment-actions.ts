interface BlockParams {
  viewerCanBlockFromOrg: boolean
  pendingBlock: boolean
  pendingUnblock: boolean
  hasAuthor: boolean
}

interface UnblockParams {
  viewerCanUnblockFromOrg: boolean
  pendingBlock: boolean
  pendingUnblock: boolean
  hasAuthor: boolean
}

export function canBlock(params: BlockParams) {
  const {viewerCanBlockFromOrg, pendingBlock, hasAuthor, pendingUnblock} = params

  if (!hasAuthor) {
    // Basic requirement for blocking is that there is an author
    return false
  }
  if (pendingBlock) {
    // The user has just blocked from this comment
    return false
  }
  if (pendingUnblock) {
    // The user has just unblocked from this comment
    return true
  }
  return viewerCanBlockFromOrg
}

export function canUnblock(params: UnblockParams) {
  const {viewerCanUnblockFromOrg, pendingBlock, hasAuthor, pendingUnblock} = params

  if (!hasAuthor) {
    // Basic requirement for unblocking is that there is an author
    return false
  }
  if (pendingUnblock) {
    // The user has just unblocked from this comment
    return false
  }
  if (pendingBlock) {
    // The user has just blocked from this comment
    return true
  }
  return viewerCanUnblockFromOrg
}

export function getCommentActionsLabel(body: string) {
  const truncationLimit = 120
  const truncate = body.length > truncationLimit
  const truncatedLabel = truncate ? `${body.slice(0, truncationLimit)}... (truncated)` : body
  return `Comment actions for comment: "${truncatedLabel}"`
}
