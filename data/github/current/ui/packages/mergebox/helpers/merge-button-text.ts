import {MergeMethod, MergeQueueMethod} from '../types'

/**
 * Returns the button text depending on the merge method
 */
export function mergeButtonText({
  mergeMethod,
  confirming,
  isBypassMerge = false,
  inProgress = false,
  isAutoMergeAllowed = false,
}: {
  mergeMethod: MergeMethod
  confirming: boolean
  isBypassMerge?: boolean
  inProgress?: boolean
  isAutoMergeAllowed?: boolean
}) {
  if (inProgress) {
    const text = isAutoMergeAllowed ? 'Confirming...' : 'Merging...'
    return text
  }
  const autoMergeText = confirming ? 'Confirm auto-merge' : 'Enable auto-merge'
  const bypassText = confirming ? 'Confirm bypass rules and merge' : 'Bypass rules and merge'

  switch (mergeMethod) {
    case MergeMethod.MERGE:
      if (isAutoMergeAllowed) {
        return autoMergeText
      } else if (isBypassMerge) {
        return bypassText
      } else if (confirming) {
        return 'Confirm merge'
      } else {
        return 'Merge pull request'
      }
    case MergeMethod.SQUASH:
      if (isAutoMergeAllowed) {
        return `${autoMergeText} (squash)`
      } else if (isBypassMerge) {
        return `${bypassText} (squash)`
      } else if (confirming) {
        return 'Confirm squash and merge'
      } else {
        return 'Squash and merge'
      }

    case MergeMethod.REBASE:
      if (isAutoMergeAllowed) {
        return `${autoMergeText} (rebase)`
      } else if (isBypassMerge) {
        return `${bypassText} (rebase)`
      } else if (confirming) {
        return 'Confirm rebase and merge'
      } else {
        return 'Rebase and merge'
      }
  }
}

/**
 * Returns the button text depending on the selected merge queue method
 */
export function mergeQueueButtonText({
  mergeMethod,
  confirming,
  inProgress,
}: {
  mergeMethod: MergeQueueMethod
  confirming: boolean
  inProgress: boolean
}) {
  if (inProgress) {
    return 'Adding to merge queue...'
  }

  switch (mergeMethod) {
    case MergeQueueMethod.GROUP:
      return confirming ? 'Confirm merge when ready' : 'Merge when ready'
    case MergeQueueMethod.SOLO:
      return confirming ? 'Confirm queue and force solo merge' : 'Queue and force solo merge'
  }
}
